# MIDI Loop Station

An iOS app that functions as a live MIDI loop station for digital pianos and keyboards. Record incoming MIDI into independent slots and play them back in a loop, sending MIDI output back to the connected instrument. Build up layers of sound by tapping the screen or using the soft pedal for hands-free operation.

The app produces no audio of its own — it operates purely as a MIDI recorder and playback engine, relying on the connected keyboard to generate all sound.

## Features

- **4 independent loop slots** — record, play, mute, and clear each slot independently
- **MIDI pass-through** — hear yourself playing in real time with imperceptible latency
- **Loop quantisation** — first recording sets the master loop length; subsequent recordings snap to exact multiples
- **Note quantisation** — optionally snap notes to a grid (1/4, 1/8, 1/16, 1/32) when recording stops
- **Pre-roll capture** — notes played just before the loop boundary are included in the recording
- **Pedal control** — use the soft pedal (or any configurable CC) for hands-free operation:
  - Hold: arm and record on empty slot, release to stop
  - Quick press: toggle mute
  - Long press: clear slot and advance to next
- **USB and Bluetooth MIDI** — connect to any CoreMIDI-compatible device
- **Stuck note prevention** — tracks all sounding notes and sends Note Off on mute, clear, loop restart, and app background
- **Live performance UI** — large touch targets readable at arm's length, dark theme

## Requirements

- iOS 18.0+
- iPhone or iPad
- A MIDI synth or digital piano (USB or Bluetooth) that creates its own sound

## Building

Requires Xcode 16.4+ and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project MIDILoop.xcodeproj -scheme MIDILoop -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Run tests with:

```sh
xcodebuild test -project MIDILoop.xcodeproj -scheme MIDILoop -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Dependencies

- [MIDIKit](https://github.com/orchetect/MIDIKit) — Swift CoreMIDI wrapper

## Licence

TBD
