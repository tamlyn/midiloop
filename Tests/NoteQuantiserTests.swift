import Foundation
import Testing
import MIDIKitCore
@testable import MIDILoop

struct NoteQuantiserTests {
    @Test func offQuantisationReturnsUnchanged() {
        let events = [
            RecordedEvent(timestamp: 0.13, event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))),
            RecordedEvent(timestamp: 0.63, event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))),
        ]
        let result = NoteQuantiser.quantise(events: events, loopDuration: 2.0, grid: .off)
        #expect(result.count == 2)
        #expect(result[0].timestamp == 0.13)
        #expect(result[1].timestamp == 0.63)
    }

    @Test func quarterNoteSnapping() {
        // Loop = 2.0s, quarter grid = 2.0/4 = 0.5s intervals
        // Note-on at 0.13 should snap to 0.0
        // Note-off should shift by the same delta (-0.13) → 0.63 - 0.13 = 0.5
        let events = [
            RecordedEvent(timestamp: 0.13, event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))),
            RecordedEvent(timestamp: 0.63, event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))),
        ]
        let result = NoteQuantiser.quantise(events: events, loopDuration: 2.0, grid: .quarter)
        #expect(result.count == 2)
        #expect(isClose(result[0].timestamp, 0.0))
        #expect(isClose(result[1].timestamp, 0.5))
    }

    @Test func noteOffPreservesDuration() {
        // Note-on at 0.4 snaps to 0.5 (delta = +0.1)
        // Note-off at 0.8 should become 0.9 (preserving 0.4s duration)
        let events = [
            RecordedEvent(timestamp: 0.4, event: .noteOn(MIDIEvent.NoteOn(note: 64, velocity: .midi1(90), channel: 0))),
            RecordedEvent(timestamp: 0.8, event: .noteOff(MIDIEvent.NoteOff(note: 64, velocity: .midi1(0), channel: 0))),
        ]
        let result = NoteQuantiser.quantise(events: events, loopDuration: 2.0, grid: .quarter)
        #expect(isClose(result[0].timestamp, 0.5))
        #expect(isClose(result[1].timestamp, 0.9))
    }

    @Test func noteOnSnappedToLoopEndWrapsToStart() {
        // 1.8 snaps to 2.0 — the loop end, where it could never play.
        // It wraps to 0.0 and the note-off follows, preserving duration.
        let events = [
            RecordedEvent(timestamp: 1.8, event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))),
            RecordedEvent(timestamp: 1.9, event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))),
        ]
        let result = NoteQuantiser.quantise(events: events, loopDuration: 2.0, grid: .quarter)
        #expect(isClose(result[0].timestamp, 0.0))
        #expect(isClose(result[1].timestamp, 0.1))
    }

    @Test func noteOffClampedToLoopDuration() {
        // Note-on snaps forward; its note-off shift would exceed loop duration
        let events = [
            RecordedEvent(timestamp: 1.4, event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))),
            RecordedEvent(timestamp: 1.95, event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))),
        ]
        // 1.4 snaps to 1.5 (delta +0.1), note-off would be 2.05 but clamps to 2.0
        let result = NoteQuantiser.quantise(events: events, loopDuration: 2.0, grid: .quarter)
        #expect(isClose(result[0].timestamp, 1.5))
        #expect(isClose(result[1].timestamp, 2.0))
    }

    @Test func ccEventsKeepTheirTiming() {
        let events = [
            RecordedEvent(timestamp: 0.13, event: .cc(64, value: .midi1(127), channel: 0)),
            RecordedEvent(timestamp: 0.87, event: .cc(64, value: .midi1(0), channel: 0)),
        ]
        let result = NoteQuantiser.quantise(events: events, loopDuration: 2.0, grid: .quarter)
        #expect(result[0].timestamp == 0.13)
        #expect(result[1].timestamp == 0.87)
    }

    @Test func resultsSortedByTimestamp() {
        // Two notes that would reorder after snapping
        let events = [
            RecordedEvent(timestamp: 0.4, event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))),
            RecordedEvent(timestamp: 0.45, event: .noteOn(MIDIEvent.NoteOn(note: 64, velocity: .midi1(90), channel: 0))),
            RecordedEvent(timestamp: 0.6, event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))),
            RecordedEvent(timestamp: 0.7, event: .noteOff(MIDIEvent.NoteOff(note: 64, velocity: .midi1(0), channel: 0))),
        ]
        let result = NoteQuantiser.quantise(events: events, loopDuration: 2.0, grid: .quarter)
        for i in 1..<result.count {
            #expect(result[i].timestamp >= result[i - 1].timestamp)
        }
    }

    private func isClose(_ a: TimeInterval, _ b: TimeInterval, tolerance: TimeInterval = 0.001) -> Bool {
        abs(a - b) < tolerance
    }
}
