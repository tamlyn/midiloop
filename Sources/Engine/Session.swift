import Foundation

/// Subdivisions of the master loop for note quantisation.
enum NoteQuantisation: Int, CaseIterable, Identifiable {
    case off = 0
    case quarter = 4
    case eighth = 8
    case sixteenth = 16
    case thirtySecond = 32

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .quarter: "1/4"
        case .eighth: "1/8"
        case .sixteenth: "1/16"
        case .thirtySecond: "1/32"
        }
    }
}

@MainActor @Observable
final class Session {
    let slots: [Slot] = (0..<4).map { Slot(id: $0) }
    private(set) var selectedSlotIndex: Int = 0
    private(set) var masterLoopDuration: TimeInterval?
    private(set) var loopPosition: TimeInterval = 0
    var noteQuantisation: NoteQuantisation = .off {
        didSet { UserDefaults.standard.set(noteQuantisation.rawValue, forKey: "noteQuantisation") }
    }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.object(forKey: "noteQuantisation") as? Int,
           let q = NoteQuantisation(rawValue: raw) {
            noteQuantisation = q
        }
    }

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

    /// Quantise a recording duration to the nearest power-of-2 multiple
    /// of the master loop (e.g. 1/2x, 1x, 2x, 4x).
    func quantisedDuration(for rawDuration: TimeInterval) -> TimeInterval {
        guard let master = masterLoopDuration, master > 0 else { return rawDuration }
        let ratio = rawDuration / master
        // Snap to nearest power of 2: ..., 0.25, 0.5, 1, 2, 4, 8, ...
        let power = Foundation.round(Foundation.log2(ratio))
        let multiple = Foundation.pow(2.0, power)
        return master * max(multiple, 0.25)
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
