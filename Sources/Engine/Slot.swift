import Foundation
import MIDIKitIO

struct RecordedEvent {
    let timestamp: TimeInterval
    let takeIndex: Int
    let event: MIDIEvent

    init(timestamp: TimeInterval, takeIndex: Int = 0, event: MIDIEvent) {
        self.timestamp = timestamp
        self.takeIndex = takeIndex
        self.event = event
    }
}

enum SlotState {
    case empty
    /// Waiting for the next master loop boundary to begin recording.
    case armed
    case recording
    case playing
    case muted
}

@MainActor @Observable
final class Slot: Identifiable {
    let id: Int
    private(set) var state: SlotState = .empty
    private(set) var events: [RecordedEvent] = []
    private(set) var duration: TimeInterval = 0

    /// Notes currently sounding from this slot's playback.
    private(set) var activeNotes: Set<NoteKey> = []

    init(id: Int) {
        self.id = id
    }

    func arm() {
        guard state == .empty else { return }
        state = .armed
        events = []
    }

    func startRecording() {
        guard state == .empty || state == .armed else { return }
        state = .recording
        events = []
    }

    func addEvent(_ event: RecordedEvent) {
        guard state == .recording else { return }
        events.append(event)
    }

    func quantiseEvents(loopDuration: TimeInterval, grid: NoteQuantisation) {
        guard state == .recording else { return }
        events = NoteQuantiser.quantise(events: events, loopDuration: loopDuration, grid: grid)
    }

    func stopRecording(duration: TimeInterval) {
        guard state == .recording else { return }
        self.duration = duration
        state = .playing
    }

    func toggleMute() {
        switch state {
        case .playing:
            state = .muted
        case .muted:
            state = .playing
        default:
            break
        }
    }

    func clear() {
        state = .empty
        events = []
        duration = 0
        activeNotes = []
    }

    func trackNoteOn(note: UInt7, channel: UInt4) {
        activeNotes.insert(NoteKey(note: note, channel: channel))
    }

    func trackNoteOff(note: UInt7, channel: UInt4) {
        activeNotes.remove(NoteKey(note: note, channel: channel))
    }

    func clearActiveNotes() {
        activeNotes = []
    }

    func snapshot() -> SlotSnapshot {
        SlotSnapshot(
            slotId: id,
            state: state,
            events: events,
            duration: duration
        )
    }

    func restore(from snapshot: SlotSnapshot) {
        state = snapshot.state
        events = snapshot.events
        duration = snapshot.duration
        activeNotes = []
    }

    /// Accepts events and state from another slot (for drag-to-move).
    func acceptTransfer(from source: Slot) {
        events = source.events
        duration = source.duration
        state = source.state == .muted ? .muted : .playing
    }

    /// Merges events from another slot into this one. The resulting duration
    /// is the longer of the two; the shorter clip's events are looped to fill.
    func mergeEvents(from source: Slot) {
        guard duration > 0, source.duration > 0 else { return }
        let targetDuration = max(duration, source.duration)

        // Loop this slot's own events if the source is longer
        if source.duration > duration {
            events = Self.loopEvents(events, originalDuration: duration, targetDuration: targetDuration)
        }

        // Loop source events to fill the target duration
        let sourceEvents = Self.loopEvents(source.events, originalDuration: source.duration, targetDuration: targetDuration)

        events.append(contentsOf: sourceEvents)
        events.sort { $0.timestamp < $1.timestamp }
        duration = targetDuration
    }

    /// Repeats events to fill a longer duration.
    static func loopEvents(
        _ events: [RecordedEvent],
        originalDuration: TimeInterval,
        targetDuration: TimeInterval
    ) -> [RecordedEvent] {
        guard originalDuration > 0 else { return events }
        let repetitions = Int(ceil(targetDuration / originalDuration))
        var result: [RecordedEvent] = []
        for i in 0..<repetitions {
            let offset = Double(i) * originalDuration
            for event in events {
                let t = event.timestamp + offset
                guard t < targetDuration else { continue }
                result.append(RecordedEvent(
                    timestamp: t,
                    takeIndex: event.takeIndex,
                    event: event.event
                ))
            }
        }
        return result
    }

}

/// Identifies a sounding note for stuck note prevention.
struct NoteKey: Hashable {
    let note: UInt7
    let channel: UInt4
}
