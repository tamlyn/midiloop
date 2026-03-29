import SwiftUI

/// Mini piano roll visualisation for a slot's recorded notes.
struct NoteRollView: View {
    let noteBars: [NoteBar]
    let duration: TimeInterval
    var dimmed: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let noteRange = computeNoteRange()
            let pitchSpan = max(1, Int(noteRange.max) - Int(noteRange.min))
            let totalPitchSpan = CGFloat(pitchSpan + 2)
            let barHeight = geometry.size.height / totalPitchSpan

            ZStack(alignment: .topLeading) {
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

/// Playhead line that reads position from the engine environment.
/// Separated from NoteRollView so position updates (~120Hz) don't
/// trigger note bar recomputation.
struct PlayheadOverlay: View {
    @Environment(LoopEngine.self) private var engine: LoopEngine?
    let slotId: Int
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            if duration > 0, let position = engine?.slotPlaybackPositions[slotId] {
                let x = CGFloat(position / duration) * geometry.size.width
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.6))
                    .frame(width: 1.5)
                    .offset(x: x)
            }
        }
    }
}
