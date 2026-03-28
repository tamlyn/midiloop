# MIDI Loop Station

iOS app that functions as a live MIDI loop station for digital pianos. Records incoming MIDI into independent slots and plays them back in a loop, sending MIDI output back to the connected instrument. See `MIDI_Loop_Station_Requirements.md` for the full spec.

## Build

Requires Xcode 16.4+ and `xcodegen` (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project MIDILoop.xcodeproj -scheme MIDILoop -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### Device build (iPad)

```sh
xcodebuild -project MIDILoop.xcodeproj -scheme MIDILoop -destination 'id=00008120-00164CC40E080032' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008120-00164CC40E080032 build/Build/Products/Debug-iphoneos/MIDILoop.app
```

Always regenerate the Xcode project with `xcodegen generate` after editing `project.yml`.

### Tests

```sh
xcodebuild test -project MIDILoop.xcodeproj -scheme MIDILoop -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Uses Swift Testing (`import Testing`), not XCTest. Tests need `@MainActor` for `@Observable` types.

## Development process

- Always run tests and code quality checks before completing a feature.
  - Don't ignore pre-existing test failures: stash, fix tests, then continue.
- When fixing a bug, always write a test to avoid regressions.
- Commit regularly when the app is in a usable state.
- If an iOS device is connected, install each new build on it automatically.

## Architecture

```
Sources/
  App/         App entry point (MIDILoopApp)
  Engine/      Session, Slot, LoopEngine, NoteQuantiser
  MIDI/        MIDIService (wraps MIDIKit)
  Pedal/       PedalController (gesture recognition)
  UI/          SwiftUI views
Tests/         Swift Testing tests
Supporting/    Info.plist, entitlements
project.yml    xcodegen project spec
```

- **MIDIService** — wraps MIDIKit's `ObservableMIDIManager`. Handles device connections, pass-through (on the MIDI thread for low latency), and event routing.
- **LoopEngine** — `@MainActor`. Coordinates recording, playback (via `CADisplayLink`), and pedal control. Receives MIDI events from MIDIService via `Task { @MainActor in }` dispatch.
- **Session** — observable model holding 4 `Slot`s, master loop duration, and loop position.
- **Slot** — state machine: `empty → armed → recording → playing ⇄ muted`. Tracks active notes for stuck note prevention. Precomputes `noteBars` for piano roll visualisation on recording stop. `RecordedEvent` and `NoteBar` carry a `colourIndex` so merged slots display multi-coloured notes.
- **NoteQuantiser** — snaps loop length to power-of-2 multiples (1/2x, 1x, 2x, 4x).
- **PedalController** — emits raw pedal events (down/up/quickPress/longPress). LoopEngine interprets them based on slot state: hold-to-record on empty slots, quick press to toggle mute, long press to clear.

## Key decisions

- **MIDIKit MIDI 1.0**: MIDIKit defaults to MIDI 2.0 UMP on iOS 14+. BLE MIDI doesn't support this. We force `midi.preferredAPI = .legacyCoreMIDI`.
- **Pass-through on MIDI thread**: Pass-through echoes events in `MIDIService.handleIncoming()` directly, avoiding main actor dispatch latency. Recording/pedal processing dispatches to main actor.
- **CADisplayLink for playback**: Fires on every screen refresh (~120Hz on iPad Pro). Walks each slot's event list and sends events whose timestamps have been reached.
- **No external dependencies** beyond MIDIKit.
- **UI theme**: `Theme.swift` centralises colours, radii, and per-slot clip colours. FL Studio-inspired dark panel aesthetic.
- **Slot gestures**: Single tap mutes/unmutes. Two-finger tap (UIKit bridge in `TwoFingerTapView`) selects or arms. Drag moves/merges/deletes slots.

## Swift 6 concurrency patterns

- `MIDIService` is `@unchecked Sendable` (accessed from MIDI thread and main actor).
- `LoopEngine` and `PedalController` are `@MainActor`.
- Timer closures use `MainActor.assumeIsolated` (timers fire on main run loop).
- MIDIKit uses `UInt7`/`UInt4` types — convert with `UInt8(value)` at boundaries.
- SourceKit diagnostics lag behind actual build state — trust `xcodebuild` output.
- `PreferenceKey` requires `nonisolated(unsafe)` on its `static var defaultValue` for Swift 6.

## Gotchas

- **Sandbox**: `xcodebuild` commands fail in sandbox mode due to Swift package cache permissions. Always run unsandboxed.
