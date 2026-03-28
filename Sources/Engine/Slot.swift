import Foundation
import MIDIKitIO

struct RecordedEvent {
    let timestamp: TimeInterval
    let colourIndex: Int
    let event: MIDIEvent

    init(timestamp: TimeInterval, colourIndex: Int = 0, event: MIDIEvent) {
        self.timestamp = timestamp
        self.colourIndex = colourIndex
        self.event = event
    }
}

/// A note rendered as a horizontal bar in the piano roll.
struct NoteBar {
    let note: UInt8
    let startTime: TimeInterval
    let endTime: TimeInterval
    let colourIndex: Int

    init(note: UInt8, startTime: TimeInterval, endTime: TimeInterval, colourIndex: Int = 0) {
        self.note = note
        self.startTime = startTime
        self.endTime = endTime
        self.colourIndex = colourIndex
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

    /// Accepts events and state from another slot (for drag-to-move).
    func acceptTransfer(from source: Slot) {
        events = source.events
        duration = source.duration
        noteBars = source.noteBars
        state = source.state == .muted ? .muted : .playing
        playbackPosition = source.playbackPosition
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
        noteBars = Self.buildNoteBars(from: events, duration: duration)
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
                    colourIndex: event.colourIndex,
                    event: event.event
                ))
            }
        }
        return result
    }

    /// Pairs note-on/off events into bars for visualisation.
    static func buildNoteBars(from events: [RecordedEvent], duration: TimeInterval) -> [NoteBar] {
        // Track open notes: (note, channel) -> (start time, colourIndex)
        var open: [NoteKey: (start: TimeInterval, colourIndex: Int)] = [:]
        var bars: [NoteBar] = []

        for recorded in events {
            switch recorded.event {
            case .noteOn(let payload):
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                open[key] = (start: recorded.timestamp, colourIndex: recorded.colourIndex)

            case .noteOff(let payload):
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                if let info = open.removeValue(forKey: key) {
                    bars.append(NoteBar(
                        note: UInt8(payload.note.number),
                        startTime: info.start,
                        endTime: recorded.timestamp,
                        colourIndex: info.colourIndex
                    ))
                }

            default:
                break
            }
        }

        // Close any notes still open at the end of the loop
        for (key, info) in open {
            bars.append(NoteBar(
                note: UInt8(key.note),
                startTime: info.start,
                endTime: duration,
                colourIndex: info.colourIndex
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
