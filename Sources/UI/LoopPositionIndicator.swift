import SwiftUI

struct LoopPositionIndicator: View {
    @Environment(Session.self) private var session

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.1))

                if let master = session.masterLoopDuration, master > 0 {
                    let fraction = min(session.loopPosition / master, 1.0)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue)
                        .frame(width: geometry.size.width * CGFloat(fraction))
                }
            }
        }
        .frame(height: 12)
    }
}
