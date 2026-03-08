import Foundation
import MIDIKitIO

struct RecordedEvent {
    let timestamp: TimeInterval
    let event: MIDIEvent
}

enum SlotState {
    case empty
    case recording
    case playing
    case muted
}

@Observable
final class Slot: Identifiable {
    let id: Int
    private(set) var state: SlotState = .empty
    private(set) var events: [RecordedEvent] = []
    private(set) var duration: TimeInterval = 0

    /// Notes currently sounding from this slot's playback.
    /// Tracked for stuck note prevention.
    private(set) var activeNotes: Set<NoteKey> = []

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
}

/// Identifies a sounding note for stuck note prevention.
struct NoteKey: Hashable {
    let note: UInt7
    let channel: UInt4
}
