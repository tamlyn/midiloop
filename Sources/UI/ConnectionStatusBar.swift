import SwiftUI

struct ConnectionStatusBar: View {
    // TODO: observe MIDI connection state

    var body: some View {
        HStack {
            Image(systemName: "pianokeys")
            Text("No device connected")
                .font(.subheadline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}
