# tidal-midi (post Tidal 1.0 version)

This is a fork of the original tidal-midi that was written for Tidal 0.9. It has no relationship with the original 
[tidalcycle](http://tidalcycles.org) project. 

For minimal midi, it now works fine with Tidal 1.1.0. 

Since the original `tidal-midi` used original Params that were not compatible with Tidal 1.0, 
the devices that came with it were put into the [/Attic](Attic) directory if someday they become useful for a complete 
port.

Keep in mind that this is a simple MIDI output module for people that are not looking to run any sample playback. I use
it personally to control hardware synths based on a Raspberry PI in text mode. 

__PortMIDI__ variant. Should work on OS X, Linux and Windows.

This _still_ (and even more) __experimental__ software.

<a name="installation"></a>
# Installation

`tidal-midi` requires the latest version of `tidal`. Run these two commands
in your terminal to install the latest version:

```shell
cabal update
cabal install tidal
```

### Linux

Run the following to install `libasound2-dev` and `libportmidi-dev`:

```shell
apt-get install libasound2-dev and libportmidi-dev
```

### Mac OS X

Install PortMIDI:

```shell
brew install portmidi
```

<a name="install"></a>
## Install tidal-midi

Fork this repository and run cabal:

```shell
cabal install --lib --overwrite-policy=always --force-reinstalls
```

<a name="usage"></a>
# Usage

_This guide assumes you are already familiar with Tidal and creating patterns
with samples._

<a name="mididevices"></a>
## Get the names of MIDI devices on your system

In order to use `tidal-midi` you will need the _exact_ name of a MIDI
device on your system. You can get a list of MIDI devices on your system
by running some code in a regular `.tidal` file.

Assuming you're using the Atom editor, create a new file and save it with
a `.tidal` extension (e.g. `midi-test.tidal`). Then, type the following in
the editor:

```haskell
import Sound.Tidal.MIDI.Context

displayOutputDevices >>= putStrLn
```

Evalulate both of those above lines separately using `Shift+Enter` in Atom.
After evaluating the last line, it will output a list of MIDI devices
in your editor (in Atom, at the bottom output panel).

After listing MIDI devices on your system, take note of the device name you
will use. Devices names are case-sensitive.

For the purposes of this guide, we'll assume your device name is "USB MIDI Device".

> You only need to do this step whenever you want to get a list of devices.
> Once you take note of your system's device names, you don't need to perform
> this step ever again (unless you acquire a new MIDI device).

<a name="boot"></a>
## Boot tidal-midi

Make sure you're currently working in a file with a `.tidal` extension in
your editor (it could be the same file from the device list step above).
Then type these three lines of bootup code:

```haskell
import Sound.Tidal.MIDI.Context

attachMidi "IAC Driver Bus 1" tidalInst
instance Tidally where tidal = tidalInst
```

<a name="playingpatterns"></a>
## Playing patterns on your device

The following code will play a very simple pattern on middle-C:

```haskell
d1 $ note "0"
```

Above, the `note` param indicates a MIDI note, where `0` equals middle-C. The
following pattern plays a major scale:

```haskell
d1 $ note "0 2 4 5 7 9 11 12"
```

Alternatively, you can use `midinote` to explicitly use a MIDI note from 0 to 127:

```haskell
d1 $ midinote "60 62 64 65 67 69 71 72"
```

You can use normal TidalCycles pattern transform functions to change `tidal-midi`
patterns:

```haskell
d1 $ every 3 (rev) $ every 2 (density 2) $ note "0 2 4 5 7 9 11 12"
```

<a name="veldur"></a>
### Note length, velocity

Note length and velocity are controlled using the `dur` and `velocity`
parameters, respectively.

The value of `dur` is given in seconds:

```haskell
d1 $ note "0 2" # dur "0.05 0.2"

d1 $ note "0 2" # dur (scale 0.05 0.3 $ slow 1.5 tri1)
```

Alternatively, the `legato` parameter tells Tidal to scale the note
duration to fill it's "slot" in the pattern.  For example, the following
will give four notes each a quarter cycle in duration (values of legato
  greater or less than one will multiply the duration):

```haskell
d1 $ note "0 1 0 2" # legato "1"
```

`velocity` has a range from *0 to 1*, and equates to MIDI values *0 to 127*:

```haskell
d1 $ note "0 2 4 5 7 9 11 12" # velocity "0.5 0.75 1"

d1 $ note "0 2 4 5 7 9 11 12" # velocity (scale 0.5 1 $ slow 1.5 saw1)
```