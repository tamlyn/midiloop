import Foundation

enum SlotState {
    case empty
    case recording
    case playing
    case muted
}

struct RecordedEvent {
    let timestamp: TimeInterval
    let bytes: [UInt8]
}

@Observable
final class Slot: Identifiable {
    let id: Int
    private(set) var state: SlotState = .empty
    private(set) var events: [RecordedEvent] = []
    private(set) var duration: TimeInterval = 0

    init(id: Int) {
        self.id = id
    }

    func startRecording() {
        guard state == .empty else { return }
        state = .recording
        events = []
    }

    func addEvent(_ event: RecordedEvent) {
        guard state == .recording else { return }
        events.append(event)
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
    }
}
