import Testing
import MIDIKitCore
import QuartzCore
@testable import MIDILoop

/// Integration tests that simulate incoming MIDI events through the full
/// LoopEngine → Session → Slot pipeline and assert on the resulting clip state.
/// Focuses on multi-clip scenarios where the second clip is longer than the first.
@MainActor
struct ClipRecordingIntegrationTests {

    // MARK: - Helpers

    /// Records a clip on the selected slot by adding events and triggering stop
    /// with a controlled raw duration.
    private func recordClip(
        engine: LoopEngine,
        session: Session,
        slotIndex: Int,
        events: [RecordedEvent],
        rawDuration: TimeInterval
    ) {
        session.selectSlot(slotIndex)
        let slot = session.selectedSlot
        slot.startRecording()
        engine.recordingStartTime = CACurrentMediaTime()

        for event in events {
            slot.addEvent(event)
        }

        // Adjust so CACurrentMediaTime() - recordingStartTime == rawDuration
        engine.recordingStartTime = CACurrentMediaTime() - rawDuration
        engine.toggleRecording()
    }

    private func noteOn(_ note: UInt7, at t: TimeInterval) -> RecordedEvent {
        RecordedEvent(
            timestamp: t,
            event: .noteOn(MIDIEvent.NoteOn(note: note, velocity: .midi1(100), channel: 0))
        )
    }

    private func noteOff(_ note: UInt7, at t: TimeInterval) -> RecordedEvent {
        RecordedEvent(
            timestamp: t,
            event: .noteOff(MIDIEvent.NoteOff(note: note, velocity: .midi1(0), channel: 0))
        )
    }

    // MARK: - Test 1: Baseline first clip

    @Test func firstClipSetsCorrectDurationAndNoteBars() {
        let session = Session()
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        let events: [RecordedEvent] = [
            noteOn(60, at: 0.0),
            noteOff(60, at: 0.5),
            noteOn(64, at: 1.0),
            noteOff(64, at: 1.5),
        ]

        recordClip(engine: engine, session: session, slotIndex: 0, events: events, rawDuration: 4.0)

        let slot = session.slots[0]
        #expect(slot.state == .playing)
        #expect(slot.duration == 4.0)
        #expect(session.masterLoopDuration == 4.0)
        #expect(slot.events.count == 4)
        #expect(slot.noteBars.count == 2)

        // First note: C4 from 0.0 to 0.5
        let bar0 = slot.noteBars.first { $0.note == 60 }!
        #expect(bar0.startTime == 0.0)
        #expect(bar0.endTime == 0.5)

        // Second note: E4 from 1.0 to 1.5
        let bar1 = slot.noteBars.first { $0.note == 64 }!
        #expect(bar1.startTime == 1.0)
        #expect(bar1.endTime == 1.5)
    }

    // MARK: - Test 2: Second clip shorter than master snaps to 1x

    @Test func secondClipShorterThanMasterSnapsTo1x() {
        let session = Session()
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        // First clip: 4s master
        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        // Second clip: ~3.5s raw → should snap to 4.0 (1x master)
        recordClip(engine: engine, session: session, slotIndex: 1, events: [
            noteOn(72, at: 0.0),
            noteOff(72, at: 1.0),
        ], rawDuration: 3.5)

        let slot1 = session.slots[1]
        #expect(slot1.state == .playing)
        #expect(slot1.duration == 4.0)
        #expect(slot1.noteBars.count == 1)

        let bar = slot1.noteBars[0]
        #expect(bar.note == 72)
        #expect(bar.startTime == 0.0)
        #expect(bar.endTime == 1.0)
    }

    // MARK: - Test 3: Second clip longer (2x master), no quantisation

    @Test func secondClipLongerThanMasterQuantisesTo2x() {
        let session = Session()
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        // First clip: 4s master
        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        // Second clip: ~7.8s raw → should snap to 8.0 (2x master)
        // Notes span both halves of the 2x clip
        recordClip(engine: engine, session: session, slotIndex: 1, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 1.0),
            noteOn(64, at: 4.5),
            noteOff(64, at: 5.5),
            noteOn(67, at: 6.0),
            noteOff(67, at: 7.5),
        ], rawDuration: 7.8)

        let slot1 = session.slots[1]
        #expect(slot1.state == .playing)
        #expect(slot1.duration == 8.0)
        #expect(slot1.noteBars.count == 3)

        // Note in first half: preserved
        let barC = slot1.noteBars.first { $0.note == 60 }!
        #expect(barC.startTime == 0.0)
        #expect(barC.endTime == 1.0)

        // Note in second half: must NOT be clamped to master boundary
        let barE = slot1.noteBars.first { $0.note == 64 }!
        #expect(barE.startTime == 4.5)
        #expect(barE.endTime == 5.5)

        // Note near end
        let barG = slot1.noteBars.first { $0.note == 67 }!
        #expect(barG.startTime == 6.0)
        #expect(barG.endTime == 7.5)
    }

    // MARK: - Test 4: Second clip longer WITH quantisation (the bug)

    @Test func secondClipLongerWithQuantisationPreservesNoteLengths() {
        let session = Session()
        session.noteQuantisation = .quarter
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        // First clip: 4s master
        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        // Second clip: 2x master with notes in second half
        // Note at t=5.0 should NOT have its note-off clamped to 4.0
        recordClip(engine: engine, session: session, slotIndex: 1, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 1.0),
            noteOn(64, at: 5.0),
            noteOff(64, at: 6.0),
        ], rawDuration: 7.8)

        let slot1 = session.slots[1]
        #expect(slot1.state == .playing)
        #expect(slot1.duration == 8.0)
        #expect(slot1.noteBars.count == 2)

        // Note in first half: quantised to grid, duration preserved
        let barC = slot1.noteBars.first { $0.note == 60 }!
        #expect(barC.startTime >= 0.0)
        #expect(barC.endTime > barC.startTime)
        #expect(barC.endTime <= 2.0) // reasonable upper bound

        // Note in second half: must survive past master boundary (4.0)
        let barE = slot1.noteBars.first { $0.note == 64 }!
        #expect(barE.startTime > 4.0, "Note-on in second half should be past master boundary")
        #expect(barE.endTime > 4.0, "Note-off in second half must NOT be clamped to master duration")
        #expect(barE.endTime > barE.startTime, "Note must have positive duration")
        #expect(barE.endTime <= 8.0, "Note-off should not exceed slot duration")
    }

    // MARK: - Test 5: Unclosed notes in longer clip close at slot duration

    @Test func unclosedNotesInLongerClipCloseAtSlotDuration() {
        let session = Session()
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        // First clip: 4s master
        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        // Second clip: 2x with an unclosed note in the second half
        recordClip(engine: engine, session: session, slotIndex: 1, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 2.0),
            noteOn(64, at: 5.0),
            // No noteOff for 64 — held through end
        ], rawDuration: 7.8)

        let slot1 = session.slots[1]
        #expect(slot1.duration == 8.0)
        #expect(slot1.noteBars.count == 2)

        // Closed note: normal
        let barC = slot1.noteBars.first { $0.note == 60 }!
        #expect(barC.endTime == 2.0)

        // Unclosed note: should close at slot duration (8.0), not master (4.0)
        let barE = slot1.noteBars.first { $0.note == 64 }!
        #expect(barE.startTime == 5.0)
        #expect(barE.endTime == 8.0, "Unclosed note should close at slot duration, not master duration")
    }

    // MARK: - Test 6: Event timestamps preserved in longer clip

    @Test func eventTimestampsPreservedInLongerClip() {
        let session = Session()
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        // First clip: 4s master
        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0),
            noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        let timestamps: [TimeInterval] = [0.1, 0.6, 2.0, 2.5, 4.1, 4.6, 6.0, 7.0]
        var events: [RecordedEvent] = []
        let notes: [UInt7] = [60, 60, 64, 64, 67, 67, 72, 72]
        for (i, t) in timestamps.enumerated() {
            if i % 2 == 0 {
                events.append(noteOn(notes[i], at: t))
            } else {
                events.append(noteOff(notes[i], at: t))
            }
        }

        recordClip(engine: engine, session: session, slotIndex: 1, events: events, rawDuration: 7.9)

        let slot1 = session.slots[1]
        #expect(slot1.duration == 8.0)

        // All events should have timestamps within [0, duration]
        for event in slot1.events {
            #expect(event.timestamp >= 0, "Event timestamp should be non-negative")
            #expect(event.timestamp <= slot1.duration, "Event timestamp should not exceed slot duration")
        }

        // All note bars should be within bounds
        for bar in slot1.noteBars {
            #expect(bar.startTime >= 0)
            #expect(bar.endTime <= slot1.duration)
            #expect(bar.endTime > bar.startTime, "Note bar must have positive duration")
        }
    }

    // MARK: - Test 7: Playback offset correct for longer second clip

    @Test func playbackOffsetCorrectForLongerSecondClip() {
        let session = Session()
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        // Simulate first clip already recorded
        session.setMasterLoopDuration(4.0)
        let now = CACurrentMediaTime()
        engine.playbackStartTime = now - 16.0 // started 16s ago
        session.slots[0].startRecording()
        session.slots[0].addEvent(noteOn(60, at: 0.0))
        session.slots[0].addEvent(noteOff(60, at: 0.5))
        session.slots[0].stopRecording(duration: 4.0)

        // Record slot 1 starting at a known offset
        session.selectSlot(1)
        let slot1 = session.selectedSlot
        slot1.startRecording()
        // Recording started 8s ago = playbackStart + 8s (two master boundaries)
        engine.recordingStartTime = now - 8.0

        slot1.addEvent(noteOn(64, at: 0.0))
        slot1.addEvent(noteOff(64, at: 1.0))
        slot1.addEvent(noteOn(67, at: 4.5))
        slot1.addEvent(noteOff(67, at: 5.5))

        engine.toggleRecording()

        #expect(slot1.state == .playing)
        #expect(slot1.duration == 8.0)

        // Offset = recordingStartTime - playbackStartTime = (now-8) - (now-16) = 8.0
        let offset = engine.slotPlaybackOffsets[1]
        #expect(offset > 7.5 && offset < 8.5, "Playback offset should be ~8.0s from playback start")
    }
}
