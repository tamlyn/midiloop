import Foundation

struct SlotSnapshot {
    let slotId: Int
    let state: SlotState
    let events: [RecordedEvent]
    let duration: TimeInterval
}

struct UndoEntry {
    let label: String
    let slotSnapshots: [SlotSnapshot]
    let playbackIndices: [Int]
    let playbackOffsets: [TimeInterval]
    let masterLoopDuration: TimeInterval?
    let selectedSlotIndex: Int
}
