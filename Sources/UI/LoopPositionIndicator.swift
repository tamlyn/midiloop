import SwiftUI

struct LoopPositionIndicator: View {
    @Environment(Session.self) private var session

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.3))

                if let master = session.masterLoopDuration, master > 0 {
                    let fraction = session.loopPosition / master
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.blue)
                        .frame(width: geometry.size.width * CGFloat(fraction))
                }
            }
        }
        .frame(height: 8)
        .padding(.horizontal)
    }
}
