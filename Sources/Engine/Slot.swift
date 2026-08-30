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

    /// Channels where this slot's playback is holding the sustain pedal down.
    private(set) var sustainChannels: Set<UInt4> = []

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
        events = Self.closeOpenNotes(in: Self.trim(events, to: duration), at: duration)
        self.duration = duration
        state = .playing
    }

    /// Drops events beyond a (possibly snapped-down) duration. Note-offs
    /// landing exactly on the boundary are kept so notes can end there.
    private static func trim(_ events: [RecordedEvent], to duration: TimeInterval) -> [RecordedEvent] {
        events.filter { recorded in
            if case .noteOn = recorded.event {
                return recorded.timestamp < duration
            }
            return recorded.timestamp <= duration
        }
    }

    /// Appends note-offs (and sustain-off) at the loop end for anything still
    /// sounding, so keys or the sustain pedal held past the end of recording
    /// don't leave the loop sustaining forever on playback.
    private static func closeOpenNotes(in events: [RecordedEvent], at duration: TimeInterval) -> [RecordedEvent] {
        var openNotes: [NoteKey: Int] = [:]
        var openSustains: [UInt4: Int] = [:]

        for recorded in events {
            switch recorded.event {
            case .noteOn(let payload):
                openNotes[NoteKey(note: payload.note.number, channel: payload.channel)] = recorded.takeIndex
            case .noteOff(let payload):
                openNotes.removeValue(forKey: NoteKey(note: payload.note.number, channel: payload.channel))
            case .cc(let payload) where payload.controller.number == 64:
                if payload.value.midi1Value >= 64 {
                    openSustains[payload.channel] = recorded.takeIndex
                } else {
                    openSustains.removeValue(forKey: payload.channel)
                }
            default:
                break
            }
        }

        var closed = events
        for (key, takeIndex) in openNotes {
            closed.append(RecordedEvent(
                timestamp: duration,
                takeIndex: takeIndex,
                event: .noteOff(key.note, velocity: .midi1(0), channel: key.channel)
            ))
        }
        for (channel, takeIndex) in openSustains {
            closed.append(RecordedEvent(
                timestamp: duration,
                takeIndex: takeIndex,
                event: .cc(64, value: .midi1(0), channel: channel)
            ))
        }
        return closed
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
        sustainChannels = []
    }

    func trackNoteOn(note: UInt7, channel: UInt4) {
        activeNotes.insert(NoteKey(note: note, channel: channel))
    }

    func trackNoteOff(note: UInt7, channel: UInt4) {
        activeNotes.remove(NoteKey(note: note, channel: channel))
    }

    func trackSustain(channel: UInt4, down: Bool) {
        if down {
            sustainChannels.insert(channel)
        } else {
            sustainChannels.remove(channel)
        }
    }

    func clearActiveNotes() {
        activeNotes = []
        sustainChannels = []
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
        sustainChannels = []
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
