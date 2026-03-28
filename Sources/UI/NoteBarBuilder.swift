import Foundation
import MIDIKitIO

/// A note rendered as a horizontal bar in the piano roll.
struct NoteBar {
    let note: UInt8
    let startTime: TimeInterval
    let endTime: TimeInterval
    let takeIndex: Int

    init(note: UInt8, startTime: TimeInterval, endTime: TimeInterval, takeIndex: Int = 0) {
        self.note = note
        self.startTime = startTime
        self.endTime = endTime
        self.takeIndex = takeIndex
    }
}

/// Pairs note-on/off events into bars for piano roll visualisation.
enum NoteBarBuilder {
    static func buildNoteBars(from events: [RecordedEvent], duration: TimeInterval) -> [NoteBar] {
        var open: [NoteKey: (start: TimeInterval, takeIndex: Int)] = [:]
        var bars: [NoteBar] = []

        for recorded in events {
            switch recorded.event {
            case .noteOn(let payload):
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                open[key] = (start: recorded.timestamp, takeIndex: recorded.takeIndex)

            case .noteOff(let payload):
                let key = NoteKey(note: payload.note.number, channel: payload.channel)
                if let info = open.removeValue(forKey: key) {
                    bars.append(NoteBar(
                        note: UInt8(payload.note.number),
                        startTime: info.start,
                        endTime: recorded.timestamp,
                        takeIndex: info.takeIndex
                    ))
                }

            default:
                break
            }
        }

        for (key, info) in open {
            bars.append(NoteBar(
                note: UInt8(key.note),
                startTime: info.start,
                endTime: duration,
                takeIndex: info.takeIndex
            ))
        }

        return bars
    }
}
