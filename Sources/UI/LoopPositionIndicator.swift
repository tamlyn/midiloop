import SwiftUI

struct LoopPositionIndicator: View {
    @Environment(Session.self) private var session

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.panelLight)

                if let master = session.masterLoopDuration, master > 0 {
                    let fraction = min(session.loopPosition / master, 1.0)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.slotColours[0])
                        .frame(width: geometry.size.width * CGFloat(fraction))
                }
            }
        }
        .frame(height: 8)
    }
}
