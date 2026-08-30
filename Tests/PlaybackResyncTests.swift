import Testing
import MIDIKitCore
import QuartzCore
@testable import MIDILoop

/// When a slot (re-)enters playback mid-loop — recording stop, unmute, undo —
/// its playback index must align silently with the current position instead of
/// burst-replaying every event behind it as one chord.
@Suite(.serialized)
@MainActor
struct PlaybackResyncTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "noteQuantisation")
        UserDefaults.standard.removeObject(forKey: "pedalCC")
    }

    @Test func stoppingRecordingBeforeLoopBoundaryDoesNotBurstReplay() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        // Empty first clip just to establish a 4s master loop
        recordClip(engine: engine, session: session, slotIndex: 0, events: [], rawDuration: 4.0)

        // Slot 1 records from a boundary; the pedal is released 0.1s early,
        // so the raw 3.9s take snaps up to 4.0s
        let now = CACurrentMediaTime()
        engine.playbackStartTime = now - 7.9
        session.selectSlot(1)
        let slot1 = session.selectedSlot
        slot1.startRecording()
        engine.recordingStartTime = now - 3.9
        slot1.addEvent(noteOn(72, at: 0.5))
        slot1.addEvent(noteOff(72, at: 1.0))
        slot1.addEvent(noteOn(76, at: 3.0))
        slot1.addEvent(noteOff(76, at: 3.5))

        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }
        engine.toggleRecording()

        #expect(slot1.duration == 4.0)
        #expect(sent.isEmpty, "Stopping recording must not replay the take")

        engine.tick(now: CACurrentMediaTime())
        #expect(sent.isEmpty, "Position ~3.9: no events due until the loop wraps")

        // Cross the loop boundary and reach the first note
        engine.tick(now: engine.playbackStartTime + 8.2)
        engine.tick(now: engine.playbackStartTime + 8.6)
        #expect(sent.contains { isNoteOn($0, note: 72) })
        #expect(!sent.contains { isNoteOn($0, note: 76) })
    }

    @Test func unmutingMidLoopDoesNotBurstReplay() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 1.0), noteOff(60, at: 1.5),
            noteOn(64, at: 3.0), noteOff(64, at: 3.5),
        ], rawDuration: 4.0)

        let slot = session.slots[0]
        engine.toggleMute(slot: slot)

        // Loop position is ~2.0 when the slot is unmuted
        engine.playbackStartTime = CACurrentMediaTime() - 6.0
        engine.toggleMute(slot: slot)
        #expect(slot.state == .playing)

        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }

        engine.tick(now: CACurrentMediaTime())
        #expect(sent.isEmpty, "Events before the unmute position must be skipped, not replayed")

        engine.tick(now: CACurrentMediaTime() + 1.1)
        #expect(sent.contains { isNoteOn($0, note: 64) })
        #expect(!sent.contains { isNoteOn($0, note: 60) })
    }

    @Test func undoResyncsPlaybackToCurrentPosition() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.5), noteOff(60, at: 1.0),
        ], rawDuration: 4.0)

        // Loop position is ~2.0 when the clear is undone
        engine.playbackStartTime = CACurrentMediaTime() - 6.0
        engine.clearSlot(session.slots[0])
        engine.undo()
        #expect(session.slots[0].state == .playing)

        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }
        engine.tick(now: CACurrentMediaTime())

        #expect(sent.isEmpty, "Events before the undo position must not burst-replay")
    }

    @Test func loopWrapFlushesTailEvents() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        // Note-off lands exactly on the loop end — a position playback can
        // never reach, so it must flush when the loop wraps
        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.5), noteOff(60, at: 4.0),
        ], rawDuration: 4.0)

        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }

        let start = engine.playbackStartTime
        engine.tick(now: start + 4.6)
        #expect(sent.contains { isNoteOn($0, note: 60) })

        engine.tick(now: start + 7.9)
        #expect(!sent.contains { isNoteOff($0, note: 60) })

        engine.tick(now: start + 8.1)
        let offs = sent.filter { isNoteOff($0, note: 60) }
        #expect(offs.count == 1, "The tail note-off plays exactly once at the wrap")

        engine.tick(now: start + 8.6)
        #expect(sent.filter { isNoteOn($0, note: 60) }.count == 2, "The note replays on the next pass")
    }

    @Test func firstLoopPlaysFromTopImmediatelyAfterStop() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        engine.startRecording()
        engine.handleIncomingEvent(.noteOn(60, velocity: .midi1(100), channel: 0))
        // Pretend the recording has been running for 2s
        engine.recordingStartTime = CACurrentMediaTime() - 2.0
        engine.handleIncomingEvent(.noteOff(60, velocity: .midi1(0), channel: 0))

        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }
        engine.toggleRecording()

        engine.tick(now: CACurrentMediaTime() + 0.05)
        #expect(sent.contains { isNoteOn($0, note: 60) },
                "The note at t=0 must replay on the very first pass")
    }
}
