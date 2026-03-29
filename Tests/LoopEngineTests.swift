import Testing
import MIDIKitCore
import QuartzCore
@testable import MIDILoop

@Suite(.serialized)
@MainActor
struct LoopEngineTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "noteQuantisation")
        UserDefaults.standard.removeObject(forKey: "pedalCC")
    }

    // MARK: - Move slot

    @Test func moveSlotTransfersContentToEmptyTarget() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        let source = session.slots[0]
        let target = session.slots[2]

        engine.moveSlot(from: source, to: target)

        #expect(source.state == .empty)
        #expect(source.events.isEmpty)
        #expect(target.state == .playing)
        #expect(target.events.count == 2)
        #expect(target.duration == 1.0)
    }

    @Test func moveSlotTransfersPlaybackOffsets() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        engine.slotPlaybackOffsets[0] = 3.5

        let source = session.slots[0]
        let target = session.slots[1]

        engine.moveSlot(from: source, to: target)

        #expect(engine.slotPlaybackOffsets[1] == 3.5)
        #expect(engine.slotPlaybackOffsets[0] == 0)
    }

    @Test func moveSlotDoesNothingIfTargetNotEmpty() {
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

        let source = session.slots[0]
        let target = session.slots[1]

        engine.moveSlot(from: source, to: target)

        // Both should remain unchanged
        #expect(source.state == .playing)
        #expect(target.state == .playing)
        #expect(source.events.count == 2)
        #expect(target.events.count == 2)
    }

    @Test func moveSlotPreservesMutedState() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        let source = session.slots[0]
        source.toggleMute()
        #expect(source.state == .muted)

        let target = session.slots[1]
        engine.moveSlot(from: source, to: target)

        #expect(target.state == .muted)
    }

    // MARK: - Toggle mute on specific slot

    @Test func toggleMuteOnSpecificSlot() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 1, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        let slot = session.slots[1]
        #expect(slot.state == .playing)

        // Mute a non-selected slot
        session.selectSlot(0)
        engine.toggleMute(slot: slot)
        #expect(slot.state == .muted)

        engine.toggleMute(slot: slot)
        #expect(slot.state == .playing)
    }

    @Test func toggleMuteOnEmptySlotDoesNothing() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        let slot = session.slots[0]
        engine.toggleMute(slot: slot)
        #expect(slot.state == .empty)
    }

    // MARK: - Clear slot

    @Test func clearSlotResetsToEmpty() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        let slot = session.slots[0]
        engine.clearSlot(slot)

        #expect(slot.state == .empty)
        #expect(slot.events.isEmpty)
    }

    @Test func clearLastSlotResetsMasterLoop() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        #expect(session.masterLoopDuration == 1.0)

        engine.clearSlot(session.slots[0])
        #expect(session.masterLoopDuration == nil)
    }

    // MARK: - canUndo

    @Test func canUndoReflectsStackState() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        #expect(!engine.canUndo)

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 1.0)

        engine.clearSlot(session.slots[0])
        #expect(engine.canUndo)

        engine.undo()
        #expect(!engine.canUndo)
    }
}
