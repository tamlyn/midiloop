import Foundation
import MIDIKitIO

/// Snaps note-on events to a grid and adjusts note-offs to preserve duration.
enum NoteQuantiser {
    static func quantise(
        events: [RecordedEvent],
        loopDuration: TimeInterval,
        grid: NoteQuantisation
    ) -> [RecordedEvent] {
        guard grid != .off, grid.rawValue > 0 else { return events }

        let gridInterval = loopDuration / Double(grid.rawValue)

        // First pass: build a map of note-on timestamp adjustments.
        // We pair each note-on with its note-off to preserve duration.
        var result: [RecordedEvent] = []
        // Track the delta applied to each note-on so we can shift its note-off
        var activeDeltas: [NoteKey: TimeInterval] = [:]

        for recorded in events {
            switch recorded.event {
            case .noteOn(let payload):
                let snapped = snapToGrid(recorded.timestamp, gridInterval: gridInterval)
                let delta = snapped - recorded.timestamp
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                activeDeltas[key] = delta
                result.append(RecordedEvent(
                    timestamp: max(0, snapped),
                    takeIndex: recorded.takeIndex,
                    event: recorded.event
                ))

            case .noteOff(let payload):
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                let delta = activeDeltas.removeValue(forKey: key) ?? 0
                let adjusted = recorded.timestamp + delta
                result.append(RecordedEvent(
                    timestamp: max(0, min(adjusted, loopDuration)),
                    takeIndex: recorded.takeIndex,
                    event: recorded.event
                ))

            default:
                // Non-note events (CC, pitch bend, etc.): snap to grid too
                let snapped = snapToGrid(recorded.timestamp, gridInterval: gridInterval)
                result.append(RecordedEvent(
                    timestamp: max(0, snapped),
                    takeIndex: recorded.takeIndex,
                    event: recorded.event
                ))
            }
        }

        // Re-sort by timestamp since snapping can reorder events
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    private static func snapToGrid(_ timestamp: TimeInterval, gridInterval: TimeInterval) -> TimeInterval {
        round(timestamp / gridInterval) * gridInterval
    }
}
