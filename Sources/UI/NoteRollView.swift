import SwiftUI

/// Mini piano roll visualisation for a slot's recorded notes.
struct NoteRollView: View {
    let noteBars: [NoteBar]
    let duration: TimeInterval
    let playbackPosition: TimeInterval
    let showPlayhead: Bool
    var dimmed: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let noteRange = computeNoteRange()
            let pitchSpan = max(1, Int(noteRange.max) - Int(noteRange.min))
            // Add padding above and below
            let totalPitchSpan = CGFloat(pitchSpan + 2)
            let barHeight = geometry.size.height / totalPitchSpan

            ZStack(alignment: .topLeading) {
                // Note bars
                ForEach(Array(noteBars.enumerated()), id: \.offset) { _, bar in
                    let x = xPosition(bar.startTime, in: geometry.size.width)
                    let width = max(2, xPosition(bar.endTime, in: geometry.size.width) - x)
                    let pitchOffset = CGFloat(Int(noteRange.max) - Int(bar.note) + 1)
                    let y = pitchOffset * barHeight
                    let colour = Theme.takeColour(index: bar.takeIndex)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(colour.opacity(dimmed ? 0.25 : 0.7))
                        .frame(width: width, height: max(barHeight - 1, 2))
                        .offset(x: x, y: y)
                }

                // Playhead
                if showPlayhead && duration > 0 {
                    let headX = xPosition(playbackPosition, in: geometry.size.width)
                    Rectangle()
                        .fill(Theme.textPrimary.opacity(0.6))
                        .frame(width: 1.5)
                        .offset(x: headX)
                }
            }
        }
    }

    private func xPosition(_ time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func computeNoteRange() -> (min: UInt8, max: UInt8) {
        guard !noteBars.isEmpty else { return (60, 72) }
        let notes = noteBars.map(\.note)
        return (notes.min()!, notes.max()!)
    }
}
