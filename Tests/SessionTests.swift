import Testing
@testable import MIDILoop

@MainActor
struct SessionTests {
    // MARK: - Quantised duration (power-of-2 snapping)

    @Test func quantisedDurationWithoutMaster() {
        let session = Session()
        #expect(session.quantisedDuration(for: 3.7) == 3.7)
    }

    @Test func quantisedDurationExactMultiples() {
        let session = Session()
        session.setMasterLoopDuration(2.0)

        // Exact 1x
        #expect(session.quantisedDuration(for: 2.0) == 2.0)
        // Exact 2x
        #expect(session.quantisedDuration(for: 4.0) == 4.0)
        // Exact 4x
        #expect(session.quantisedDuration(for: 8.0) == 8.0)
    }

    @Test func quantisedDurationSnapsToNearest() {
        let session = Session()
        session.setMasterLoopDuration(2.0)

        // 2.8s is closer to 1x (2.0) than 2x (4.0)
        #expect(session.quantisedDuration(for: 2.8) == 2.0)
        // 3.5s is closer to 2x (4.0) than 1x (2.0)
        #expect(session.quantisedDuration(for: 3.5) == 4.0)
    }

    @Test func quantisedDurationHalfLoop() {
        let session = Session()
        session.setMasterLoopDuration(4.0)

        // ~1.8s should snap to 0.5x = 2.0
        #expect(session.quantisedDuration(for: 1.8) == 2.0)
    }

    @Test func quantisedDurationMinimumQuarter() {
        let session = Session()
        session.setMasterLoopDuration(4.0)

        // Very short recording should clamp to 0.25x
        #expect(session.quantisedDuration(for: 0.1) == 1.0)
    }

    // MARK: - Slot selection

    @Test func defaultSelection() {
        let session = Session()
        #expect(session.selectedSlotIndex == 0)
    }

    @Test func selectSlot() {
        let session = Session()
        session.selectSlot(2)
        #expect(session.selectedSlotIndex == 2)
    }

    @Test func selectSlotBoundsCheck() {
        let session = Session()
        session.selectSlot(5)
        #expect(session.selectedSlotIndex == 0)
        session.selectSlot(-1)
        #expect(session.selectedSlotIndex == 0)
    }

    @Test func selectNextEmptySlot() {
        let session = Session()
        session.slots[0].startRecording()
        session.slots[0].stopRecording(duration: 1.0)

        session.selectNextEmptySlot()
        #expect(session.selectedSlotIndex == 1)
    }

    @Test func selectNextEmptySlotWhenAllFull() {
        let session = Session()
        for slot in session.slots {
            slot.startRecording()
            slot.stopRecording(duration: 1.0)
        }
        session.selectSlot(0)
        session.selectNextEmptySlot()
        // Should stay at 0 — no empty slots
        #expect(session.selectedSlotIndex == 0)
    }

    // MARK: - Clear all

    @Test func clearAllResetsEverything() {
        let session = Session()
        session.setMasterLoopDuration(2.0)
        session.updateLoopPosition(1.5)
        session.selectSlot(2)
        session.slots[0].startRecording()
        session.slots[0].stopRecording(duration: 2.0)

        session.clearAll()

        #expect(session.masterLoopDuration == nil)
        #expect(session.loopPosition == 0)
        #expect(session.selectedSlotIndex == 0)
        #expect(session.allSlotsEmpty)
    }

    @Test func allSlotsEmpty() {
        let session = Session()
        #expect(session.allSlotsEmpty)

        session.slots[1].startRecording()
        #expect(!session.allSlotsEmpty)
    }

    // MARK: - Take index (colour) round-robin

    @Test func claimNextTakeIndexIncrementsRoundRobin() {
        let session = Session()
        let first = session.claimNextTakeIndex()
        let second = session.claimNextTakeIndex()
        let third = session.claimNextTakeIndex()
        #expect(first == 0)
        #expect(second == 1)
        #expect(third == 2)
    }

    @Test func clearAllDoesNotResetColourIndex() {
        let session = Session()
        _ = session.claimNextTakeIndex()
        _ = session.claimNextTakeIndex()
        session.clearAll()
        // Colour index is not reset by clearAll — each take stays unique
        // (The UI wraps via modulo, so the raw index can grow indefinitely)
        let next = session.claimNextTakeIndex()
        #expect(next == 2)
    }
}
