#perl -w
use strict;
use Getopt::Std;

my $usage = <<END;

Usage: perl sing.pl [opts] [melody] [lyrics...]
  (melody in abc notation, enclosed in quotes if necessary)

  -l file      read lyrics from file
  -m file    read melody from file
  -n number    shift pitch by half-steps
  -o number    shift pitch by octaves
  -t number    multiply tempo by number
  -v name      specify voice to sing with

END

# performs applescript
sub osascript($) { system 'osascript', map { ('-e', $_) } split(/\n/, $_[0]); }

sub min($$) {
  return $_[0] > $_[1] ? $_[1] : $_[0];
}

sub slurp($) {
  my $file = shift;
  my $text = do { local( @ARGV, $/ ) = $file ; <> };
  return $text;
}

sub assert { 
  my $assertion = shift;
  die @_ ? $_[0] : "Assertion failed" unless $assertion;
}

# phonemes
my $vowels = 'AE|EY|AO|AX|IY|EH|IH|AY|IX|AA|UW|UH|UX|OW|AW|OY';
my $consonants = 'b|C|d|D|f|g|h|J|k|l|m|n|N|p|r|s|S|t|T|v|w|y|z|Z';
my $punctuation = '\.|!|\?|,|:';
my $stress = '~|_|\+';

# splits a phoneme string into syllables
sub split_syllables($) {
  return grep /\S/, map { 
    # explicitly divide regular syllable breaks 
    # (one consonant goes with following vowel, others stay with preceding)
    while (s/($vowels)($consonants*)($consonants)(\d?)($vowels)/$1$2=$3$4$5/g) {}
    # now each syllable starts with a word stress or =
    # and is possibly followed by punctuation
    m/((?:$stress|=)(?:\d*(?:$vowels|$consonants))+($punctuation)*)/g 
  } split / /, $_[0];
}

# splits a phoneme string into individual phonemes
sub split_phonemes($) {
  return map { 
    # each unit is a vowel, consonant, stress marker, or punctuation
    # possibly starting with the syllable divider
    # possibly (in the case of vowels) starting with a 1 or 2
    m/(=?\d?(?:$vowels|$consonants|$punctuation|$stress))/g 
  } split / /, $_[0];
}

# sets a single syllable to a set of notes
sub set_syllable($@) {
  my $syllable = shift;
  my @notes = @_;
  die "no notes supplied!" unless @notes;
  #print "syllable: $syllable\n";
  #print "lengths: ", join " ", map { $_->{'length'} } @_;
  #print "\n\n";

  my @phonemes = split_phonemes $syllable;

  # get total syllable length
  my $total_length = 0;
  for (@notes) { $total_length += $_->{'length'} }

  # count the consonants
  my $before_vowel = 0;
  my $after_vowel = 0;
  my $vowel_reached = 0;
  for (@phonemes) {
    if (m/$vowels/) { $vowel_reached = 1; }
    elsif (m/$consonants/) {
      if ($vowel_reached) { $after_vowel += 1 }
      else { $before_vowel += 1 }
    }
  }

  # calculate consonant length (no more than 3/4 the total)
  my $consonant_length = $before_vowel + $after_vowel == 0 ? 0 : min(95, ($total_length * 0.75)/($before_vowel + $after_vowel));

  # subtract consonant duration from the notes
  # TODO: deal with note not long enough
  $notes[0]{'length'} -= $before_vowel * $consonant_length;
  $notes[-1]{'length'} -= $after_vowel * $consonant_length;
  if ($notes[0]{'length'} <= 0 || $notes[-1]{'length'} <= 0) {
    die "Not enough room for consonants!\n";
  }

  # get total vowel length
  my $vowel_length = $total_length - $consonant_length * ($before_vowel + $after_vowel);
  
  # distribute the pitches across the syllable
  my $pitch = $notes[0]{'pitch'};
  my @song = ();
  for (@phonemes) {
    if (m/$stress|$punctuation/) {
      push @song, "$_";
    } elsif (m/$consonants/) {
      push @song, "$_ {D $consonant_length; P $pitch:0 $pitch:100}";
    } elsif (m/$vowels/) {
      my $start = 0;
      my @pitches = ();
      for (@notes) {
	$pitch = $_->{'pitch'};
	my $length = $_->{'length'};
	push @pitches, "$pitch:$start";
	$start += ($length/$vowel_length) * 100;
	push @pitches, "$pitch:" . ($start - 1);
      }
      push @pitches, "$pitch:100";
      push @song, "$_ {D $vowel_length; P " . (join " ", @pitches) . "}";
    }
  }
  
  return @song;
}



#
# main routine
#

(my $dir = $0) =~ s|[^/]+$||;
$dir = './' unless $dir;
#print "$dir\n";

my %opts;
getopt('mlnotv', \%opts);

if ($opts{'h'}) {
  print $usage;
  exit;
}

my $pitch_shift = $opts{'o'} * 12 + $opts{'n'};
my $voice = $opts{'v'};
my $lyrics_file = $opts{'l'};
my $melody_file = $opts{'m'};
my $tempo_factor = $opts{'t'};

my $melody = $melody_file ? slurp($melody_file) : shift @ARGV;
my $lyrics = $lyrics_file ? slurp($lyrics_file) : join " ", @ARGV;

my $pad_syllable = "_UW";

# extract pitch/duration of notes and tie (slur) data from abc notation
# using the javascript module
my $jsc = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Resources/jsc';
$melody =~ s/'/\\'/g;
my $tune = `$jsc ${dir}abc2pd.js -- '$melody'`;
#print $tune;
$tune =~ s/\n//;
my @tune = split / /, $tune;

# sanity check
my @numbers = grep !m/^TIE$/, @tune;
assert(@numbers % 2 == 0, "must be an even number of numbers");
assert(0 == (grep m/[^0-9.-]/, @numbers));

# read this data into a useful structure
# each syllable has a setting, the setting is 1 or more notes, the notes are pitch/duration pairs
my @settings = ([]);
while (@tune) {
  my $pitch = shift @tune;
  my $length = shift @tune;
  push @{$settings[-1]}, {'pitch' => $pitch, 'length' => $length};
  if ($tune[0] eq 'TIE') {
    shift @tune; # consume the TIE token
  } else {
    push @settings, ([]); # advance to the next syllable
  }
}

# apply pitch shift
my $factor = 2**($pitch_shift/12);
#print "factor: $factor\n";
if ($factor != 1) {
  for my $setting (@settings) {
    for my $note (@$setting) {
      #print "pitch change: ", $note->{'pitch'};
      $note->{'pitch'} *= $factor;
      #print " => ", $note->{'pitch'}, "\n";
    }
  }
}

# apply tempo factor
#print "tempo factor: $tempo_factor\n";
$tempo_factor = 0 + $tempo_factor;
if ($tempo_factor && 1 != $tempo_factor) {
  for my $setting (@settings) {
    for my $note(@$setting) {
      $note->{'length'} /= $tempo_factor;
    }
  }
}

#print join "\n", map { join "; ", map { 'P ' . $_->{pitch} . ' D' . $_->{length} } @{$_} } @settings;
#print "\n";

# convert the lyrics to phonemes and split into syllables
my @syllables = ();
$lyrics =~ s/'/\\'/g; # make it safe for quoting
$voice =~ s/"/\\"/g; # make it safe for quoting
if ($lyrics) {
  my $opts = $voice ? qq(-v "$voice") : '';
  (my $phonemes = `${dir}phonemes $opts '$lyrics'`) =~ s/\n|\.//g;
  @syllables = split_syllables $phonemes;
  #print "phonemes: $phonemes\n";
  #print join "\n", @syllables;
}

# apply the settings to the syllables
my @song = ();
for my $setting (@settings) {
  my $pitch = $setting->[0]->{pitch};
  my $length = $setting->[0]->{length};
  #print "P $pitch D $length\n";
  if (!$pitch) {
    assert(1 == @$setting, "rests cannot be tied");
    push @song, "% {D $length}";
  } else {
    my $syllable = @syllables ? shift @syllables : $pad_syllable;
    push @song, set_syllable $syllable, @$setting;
  }
}

#print join "\n", @song;
#print "\n";

# wrap it all in a TUNE command
unshift @song, "[[inpt TUNE]]";
push @song, "[[inpt TEXT]]";

# say it
my $song = join " ", @song;
my $using = $voice ? qq(using "$voice") : '';
#print qq(say "$song" $using);
osascript qq(say "$song" $using);

