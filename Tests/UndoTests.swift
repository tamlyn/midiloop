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

    // MARK: - Clear slot undo

    @Test func undoClearSlotRestoresContent() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
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
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
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
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
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

    // MARK: - Move undo

    @Test func undoMoveRestoresSourceAndClearsTarget() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        let source = session.slots[0]
        let target = session.slots[1]
        #expect(source.state == .playing)
        #expect(target.state == .empty)

        engine.moveSlot(from: source, to: target)
        #expect(source.state == .empty)
        #expect(target.state == .playing)
        #expect(target.events.count == 2)

        engine.undo()
        #expect(source.state == .playing)
        #expect(source.events.count == 2)
        #expect(source.duration == 1.0)
        #expect(target.state == .empty)
        #expect(target.events.isEmpty)
    }

    // MARK: - Merge undo

    @Test func undoMergeRestoresBothSlots() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
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
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
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
        #expect(engine.canUndo)

        engine.undo()
        #expect(slot.state == .empty)
        #expect(slot.events.isEmpty)
        #expect(session.masterLoopDuration == nil)
    }

    @Test func undoRecordingFromArmedRestoresToEmpty() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        let slot = session.slots[0]
        // Simulate pedal flow: arm then snapshot (as LoopEngine does)
        slot.arm()
        #expect(slot.state == .armed)
        engine.capturePendingRecordingSnapshot(for: slot)

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)
        engine.commitPendingRecordingUndo()

        #expect(slot.state == .playing)

        engine.undo()
        // Armed is transient (pedal held) — undo should restore to empty
        #expect(slot.state == .empty)
        #expect(slot.events.isEmpty)
    }

    // MARK: - Stack behaviour

    @Test func undoWhenEmptyIsNoOp() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        #expect(!engine.canUndo)
        engine.undo()
        #expect(!engine.canUndo)
    }

    @Test func clearAllClearsUndoStack() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        engine.clearSlot(session.slots[0])
        #expect(engine.canUndo)

        engine.clearAll()
        #expect(!engine.canUndo)
    }

    @Test func undoStackRespectsMaxDepth() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
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

        #expect(engine.undoCount <= 10)
    }
}
