import Foundation
import MIDIKitIO

struct RecordedEvent {
    let timestamp: TimeInterval
    let event: MIDIEvent
}

/// A note rendered as a horizontal bar in the piano roll.
struct NoteBar {
    let note: UInt8
    let startTime: TimeInterval
    let endTime: TimeInterval
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
    private(set) var noteBars: [NoteBar] = []

    /// Duration suitable for display: uses the latest event timestamp while
    /// recording (before the final duration is known), otherwise the real duration.
    var displayDuration: TimeInterval {
        if state == .recording, let last = events.last {
            return last.timestamp
        }
        return duration
    }

    /// Current position within this slot's loop cycle, updated by the engine.
    var playbackPosition: TimeInterval = 0

    /// Notes currently sounding from this slot's playback.
    private(set) var activeNotes: Set<NoteKey> = []

    init(id: Int) {
        self.id = id
    }

    func arm() {
        guard state == .empty else { return }
        state = .armed
        events = []
        noteBars = []
    }

    func startRecording() {
        guard state == .empty || state == .armed else { return }
        state = .recording
        events = []
        noteBars = []
    }

    func addEvent(_ event: RecordedEvent) {
        guard state == .recording else { return }
        events.append(event)
        // Rebuild bars so the piano roll updates live during recording.
        // Open notes close at the current timestamp.
        noteBars = Self.buildNoteBars(from: events, duration: event.timestamp)
    }

    func quantiseEvents(loopDuration: TimeInterval, grid: NoteQuantisation) {
        guard state == .recording else { return }
        events = NoteQuantiser.quantise(events: events, loopDuration: loopDuration, grid: grid)
    }

    func stopRecording(duration: TimeInterval) {
        guard state == .recording else { return }
        self.duration = duration
        noteBars = Self.buildNoteBars(from: events, duration: duration)
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
        noteBars = []
        playbackPosition = 0
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

    // MARK: - Note bar computation

    /// Pairs note-on/off events into bars for visualisation.
    private static func buildNoteBars(from events: [RecordedEvent], duration: TimeInterval) -> [NoteBar] {
        // Track open notes: (note, channel) -> start time
        var open: [NoteKey: TimeInterval] = [:]
        var bars: [NoteBar] = []

        for recorded in events {
            switch recorded.event {
            case .noteOn(let payload):
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                open[key] = recorded.timestamp

            case .noteOff(let payload):
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                if let start = open.removeValue(forKey: key) {
                    bars.append(NoteBar(
                        note: UInt8(payload.note.number),
                        startTime: start,
                        endTime: recorded.timestamp
                    ))
                }

            default:
                break
            }
        }

        // Close any notes still open at the end of the loop
        for (key, start) in open {
            bars.append(NoteBar(
                note: UInt8(key.note),
                startTime: start,
                endTime: duration
            ))
        }

        return bars
    }
}

/// Identifies a sounding note for stuck note prevention.
struct NoteKey: Hashable {
    let note: UInt7
    let channel: UInt4
}
