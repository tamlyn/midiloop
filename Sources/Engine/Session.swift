import Foundation

@Observable
final class Session {
    let slots: [Slot] = (0..<4).map { Slot(id: $0) }
    private(set) var selectedSlotIndex: Int = 0
    private(set) var masterLoopDuration: TimeInterval?
    private(set) var loopPosition: TimeInterval = 0

    var selectedSlot: Slot { slots[selectedSlotIndex] }

    func selectSlot(_ index: Int) {
        guard index >= 0 && index < slots.count else { return }
        selectedSlotIndex = index
    }

    func selectNextEmptySlot() {
        if let index = slots.firstIndex(where: { $0.state == .empty }) {
            selectedSlotIndex = index
        }
    }

    /// Sets the master loop duration from the first recording.
    /// Subsequent recordings snap to multiples of this.
    func setMasterLoopDuration(_ duration: TimeInterval) {
        masterLoopDuration = duration
    }

    /// Quantise a recording duration to the nearest multiple of the master loop.
    func quantisedDuration(for rawDuration: TimeInterval) -> TimeInterval {
        guard let master = masterLoopDuration else { return rawDuration }
        let multiple = max(1, Int(round(rawDuration / master)))
        return master * Double(multiple)
    }

    func clearAll() {
        for slot in slots { slot.clear() }
        masterLoopDuration = nil
        loopPosition = 0
        selectedSlotIndex = 0
    }

    /// Returns true if all slots are empty (master loop should be reset).
    var allSlotsEmpty: Bool {
        slots.allSatisfy { $0.state == .empty }
    }

    func updateLoopPosition(_ position: TimeInterval) {
        loopPosition = position
    }
}
