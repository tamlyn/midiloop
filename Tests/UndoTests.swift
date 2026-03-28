import Testing
import MIDIKitCore
import QuartzCore
@testable import MIDILoop

@Suite(.serialized)
@MainActor
struct UndoTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "noteQuantisation")
        UserDefaults.standard.removeObject(forKey: "pedalCC")
    }

    // MARK: - Helpers

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

        for event in events {
            slot.addEvent(event)
        }

        let finalDuration: TimeInterval
        if session.masterLoopDuration == nil {
            session.setMasterLoopDuration(rawDuration)
            finalDuration = rawDuration
            engine.playbackStartTime = CACurrentMediaTime() - rawDuration
        } else {
            finalDuration = session.quantisedDuration(for: rawDuration)
        }

        slot.stopRecording(duration: finalDuration)
        engine.slotPlaybackOffsets[slot.id] = 0
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

    // MARK: - Clear slot undo

    @Test func undoClearSlotRestoresContent() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        let slot = session.slots[0]
        #expect(slot.state == .playing)
        #expect(slot.events.count == 2)

        engine.clearSlot(slot)
        #expect(slot.state == .empty)
        #expect(slot.events.isEmpty)

        engine.undo()
        #expect(slot.state == .playing)
        #expect(slot.events.count == 2)
        #expect(slot.duration == 1.0)
    }

    @Test func undoClearLastSlotRestoresMasterLoopDuration() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 2.0)

        let slot = session.slots[0]
        #expect(session.masterLoopDuration == 2.0)

        engine.clearSlot(slot)
        #expect(session.masterLoopDuration == nil)

        engine.undo()
        #expect(session.masterLoopDuration == 2.0)
        #expect(slot.state == .playing)
    }

    @Test func undoClearAndAdvanceRestoresSelectedSlot() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        session.selectSlot(0)
        #expect(session.selectedSlotIndex == 0)

        engine.clearAndAdvance()
        #expect(session.slots[0].state == .empty)
        // selectedSlotIndex moved to next empty

        engine.undo()
        #expect(session.slots[0].state == .playing)
        #expect(session.selectedSlotIndex == 0)
    }

    // MARK: - Merge undo

    @Test func undoMergeRestoresBothSlots() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        recordClip(engine: engine, session: session, slotIndex: 1, events: [
            noteOn(64, at: 0.0), noteOff(64, at: 0.5),
        ], rawDuration: 1.0)

        let source = session.slots[1]
        let target = session.slots[0]
        #expect(target.events.count == 2)
        #expect(source.events.count == 2)

        engine.mergeSlot(source: source, into: target)
        #expect(source.state == .empty)
        #expect(target.events.count == 4)

        engine.undo()
        #expect(source.state == .playing)
        #expect(source.events.count == 2)
        #expect(target.events.count == 2)
        #expect(target.duration == 1.0)
    }

    // MARK: - Recording undo

    @Test func undoRecordingRestoresEmptySlot() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        // Capture the empty snapshot before recording
        let slot = session.slots[0]
        engine.capturePendingRecordingSnapshot(for: slot)

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        // Push the pending snapshot (recordClip bypasses engine.stopRecording)
        engine.commitPendingRecordingUndo()

        #expect(slot.state == .playing)
        #expect(!engine.undoStack.isEmpty)

        engine.undo()
        #expect(slot.state == .empty)
        #expect(slot.events.isEmpty)
        #expect(session.masterLoopDuration == nil)
    }

    // MARK: - Stack behaviour

    @Test func undoWhenEmptyIsNoOp() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        #expect(engine.undoStack.isEmpty)
        engine.undo()
        #expect(engine.undoStack.isEmpty)
    }

    @Test func clearAllClearsUndoStack() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        engine.clearSlot(session.slots[0])
        #expect(!engine.undoStack.isEmpty)

        engine.clearAll()
        #expect(engine.undoStack.isEmpty)
    }

    @Test func undoStackRespectsMaxDepth() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi)
        defer { engine.stop() }

        // Record a clip so we have something to clear repeatedly
        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        // Push 15 undo entries by clearing and re-recording
        for _ in 0..<15 {
            let slot = session.slots[0]
            if slot.state != .empty {
                engine.clearSlot(slot)
            }
            recordClip(engine: engine, session: session, slotIndex: 0, events: [
                noteOn(60, at: 0.0), noteOff(60, at: 0.5),
            ], rawDuration: 1.0)
        }

        #expect(engine.undoStack.count <= 10)
    }
}
