import SwiftUI
import MIDIKitIO

struct ConnectionStatusBar: View {
    @Environment(ObservableMIDIManager.self) private var midiManager

    var body: some View {
        HStack(spacing: 8) {
            let outputCount = midiManager.endpoints.outputs.count
            Circle()
                .fill(outputCount > 0 ? .green : .red)
                .frame(width: 10, height: 10)

            if outputCount > 0 {
                let names = midiManager.endpoints.outputs.map(\.name).joined(separator: ", ")
                Text(names)
                    .font(.subheadline)
                    .lineLimit(1)
            } else {
                Text("No MIDI device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
