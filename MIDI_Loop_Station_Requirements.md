# MIDI Loop Station — Requirements Document

*March 2026*

---

## Overview

An iOS app that functions as a live MIDI loop station for digital pianos and keyboards. The app records incoming MIDI into independent slots and plays them back in a loop, sending MIDI output back to the connected instrument. The performer builds up layers of sound by tapping the screen or using the soft pedal for hands-free operation.

The app produces no audio of its own. It operates purely as a MIDI recorder and playback engine, relying on the connected keyboard to generate all sound.

---

## Functional Requirements

### MIDI Connectivity

The app must accept MIDI input from and send MIDI output to an external keyboard or digital piano. Both USB MIDI and Bluetooth MIDI connections must be supported. The app must detect connected MIDI devices and allow the user to select an input and output. If a device disconnects and reconnects, the app should restore the connection automatically.

### MIDI Pass-Through

All incoming MIDI messages (except those consumed by the pedal control system) must be echoed to the MIDI output with imperceptible latency. This ensures the performer always hears themselves playing in real time, regardless of whether any recording or playback is active.

### Loop Slots

The app provides four independent loop slots. Each slot can exist in one of the following states: empty, recording, playing, or muted.

A slot transitions through states as follows: empty → recording → playing. A playing slot can be muted and unmuted. Any non-empty slot can be cleared, returning it to the empty state.

### Recording

When a slot is in the recording state, all incoming MIDI events (Note On, Note Off, Control Change, pitch bend, aftertouch, and program change) are captured with precise timestamps relative to the start of the recording. Recording begins when the user arms a slot and plays the first note. Recording stops when the user explicitly ends it or when the quantization system determines the slot has reached its target length.

### Loop Quantization

The first recorded slot establishes the master loop length. All subsequent slot recordings are quantized to exact multiples of this master length (1×, 2×, 3×, 4×). When recording a subsequent slot, the app determines the appropriate multiple based on how long the performer plays and snaps the slot duration to the nearest multiple boundary.

All playing slots remain synchronized to a shared master clock. Regardless of individual slot lengths, every slot realigns at the master loop boundary.

Clearing all slots resets the master loop length, allowing the next recording to establish a new one.

### Playback

When a slot is in the playing state, its recorded MIDI events are sent to the MIDI output in a continuous loop. Playback timing must be accurate enough that loops sound tight and rhythmically consistent over many cycles, with no perceptible drift. Multiple slots can play simultaneously, with their events interleaved on the MIDI output alongside live pass-through.

### Mute and Unmute

Each playing slot can be individually muted, silencing its MIDI output without discarding the recorded data. Unmuting resumes playback from the correct position within the loop cycle. When muting a slot, any currently sounding notes from that slot must receive corresponding Note Off messages to prevent stuck notes.

### Clearing Slots

A slot can be cleared, discarding its recorded data and returning it to the empty state. Clearing must also send Note Off messages for any notes that were sounding from that slot.

### Stuck Note Prevention

The app must track all Note On messages sent to the MIDI output (from both playback and pass-through) and ensure corresponding Note Off messages are sent whenever a loop restarts, a slot is muted, a slot is cleared, or the app is closed. An All Notes Off (CC#123) message should be available as a safety mechanism.

---

## Pedal Control

The soft pedal (una corda, default CC#67) is repurposed as a hands-free controller. The app must interpret incoming soft pedal messages as gesture commands rather than forwarding them to the MIDI output. Three gestures must be recognized:

- **Quick press:** Start or stop recording on the currently selected slot.
- **Double press:** Toggle playback on the current slot (mute/unmute).
- **Long press:** Clear the current slot and advance selection to the next empty slot.

The CC number used for pedal control must be configurable to accommodate keyboards that assign different CC numbers to the soft pedal.

---

## User Interface

The interface must be designed for live performance use. All primary actions (arming a slot, stopping recording, muting, unmuting, clearing) must be achievable with a single tap on a large touch target. The UI must be readable at arm's length, such as from a music stand or the top of a piano.

Each slot must clearly communicate its current state through colour and labelling. The app must display the current position within the master loop cycle. MIDI connection status must be visible at all times.

The app must support both iPhone and iPad screen sizes.

---

## Constraints

- The app produces no audio. All sound generation is the responsibility of the connected instrument.
- No session persistence is required for this version. Loop data exists only in memory for the duration of a session.
- No overdubbing (recording additional notes into an existing slot) is required for this version.
- The app is iOS-only.

---

## Future Considerations

The following are explicitly out of scope for the initial version but should be considered in architectural decisions where practical:

- Overdubbing into existing slots
- Saving and loading sessions to disk
- Configurable number of slots beyond four
- MIDI channel routing (assigning different channels per slot for multi-timbral playback)
- Tap tempo or explicit BPM entry as an alternative to first-loop-sets-length
- Undo for the most recent recording
