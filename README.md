# MIDI Loop Station

An iOS app that functions as a live MIDI loop station for digital pianos and keyboards. Record incoming MIDI into independent slots and play them back in a loop, sending MIDI output back to the connected instrument. Build up layers of sound by tapping the screen or using the soft pedal for hands-free operation.

The app produces no audio of its own — it operates purely as a MIDI recorder and playback engine, relying on the connected keyboard to generate all sound.

## Features

- **4 independent loop slots** — record, play, mute, and clear each slot independently
- **MIDI pass-through** — hear yourself playing in real time with imperceptible latency
- **Loop quantisation** — first recording sets the master loop length; subsequent recordings snap to exact multiples
- **Note quantisation** — optionally snap notes to a grid (1/4, 1/8, 1/16, 1/32) when recording stops
- **Pedal control** — use the soft pedal (or any configurable CC) for hands-free operation:
  - Quick press: start/stop recording
  - Double press: mute/unmute
  - Long press: clear slot and advance
- **USB and Bluetooth MIDI** — connect to any CoreMIDI-compatible device
- **Stuck note prevention** — tracks all sounding notes and sends Note Off on mute, clear, loop restart, and app background
- **Live performance UI** — large touch targets readable at arm's length, dark theme

## Requirements

- iOS 18.0+
- iPhone or iPad
- A MIDI keyboard or digital piano (USB or Bluetooth)

## Building

The project uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to manage the Xcode project.

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project MIDILoop.xcodeproj -scheme MIDILoop -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## Dependencies

- [MIDIKit](https://github.com/orchetect/MIDIKit) — Swift CoreMIDI wrapper

## Licence

TBD
