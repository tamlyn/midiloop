import SwiftUI

struct ContentView: View {
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 24) {
            ConnectionStatusBar()

            LoopPositionIndicator()

            SlotGrid()

            HStack(spacing: 16) {
                Button("All Notes Off") {
                    // TODO: send CC#123
                }
                .buttonStyle(ActionButtonStyle(colour: .red))

                Button("Clear All") {
                    session.clearAll()
                }
                .buttonStyle(ActionButtonStyle(colour: .gray))
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct ActionButtonStyle: ButtonStyle {
    let colour: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(colour.opacity(configuration.isPressed ? 0.6 : 1.0), in: RoundedRectangle(cornerRadius: 12))
    }
}
