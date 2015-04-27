A command-line utility that makes the Mac text-to-speech voices sing tunes.

You specify the melody in [ABC notation](http://abcnotation.com).
Syllables are automatically matched to the notes. Slurred notes are sung on one syllable.

```
Usage: perl sing.pl [opts] [melody] [lyrics...]
  (melody in abc notation, enclosed in quotes if necessary)

  -l file      read lyrics from file
  -m file      read melody from file
  -n number    shift pitch by half-steps
  -o number    shift pitch by octaves
  -p           print tone command instead of singing  
  -t number    multiply tempo by number
  -v name      specify voice to sing with
```

The notes are read from the abc data in simple sequence: ie, sing does not currently support repeat signs etc.

### Examples ###

```
perl sing.pl GCEA2 My dog has fleas
perl sing.pl -v Alex -o-1 -t 0.5 GCEA2 My dog has fleas
perl sing.pl 'C2 CC3 C C-D2C B,4' Ground control to major Tom
```

Ties and slurs:

```
perl sing.pl 'GCEA-|A' My dog has fleas
perl sing.pl GCEC4-A4 My dog has fleas
perl sing.pl 'GCE(C4A4)' My dog has fleas
```

Triplet:

```
perl sing.pl '(3ACE)G2' My dog has fleas
```


### Details ###

The way this works is to send the speech synthesizer exact pitch and duration instructions for each phoneme, using the TUNE command (see Apple's [docs](http://developer.apple.com/library/mac/#documentation/UserExperience/Conceptual/SpeechSynthesisProgrammingGuide/FineTuning/FineTuning.html)). You can see the TUNE command that sing creates by using the `-p` option.

