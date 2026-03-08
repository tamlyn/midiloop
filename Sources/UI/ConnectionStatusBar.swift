import SwiftUI
import MIDIKitIO

struct ConnectionStatusBar: View {
    @Environment(ObservableMIDIManager.self) private var midiManager

    var body: some View {
        HStack {
            let outputCount = midiManager.endpoints.outputs.count
            Image(systemName: outputCount > 0 ? "pianokeys" : "pianokeys.inverse")
                .foregroundStyle(outputCount > 0 ? .green : .secondary)

            if outputCount > 0 {
                let names = midiManager.endpoints.outputs.map(\.name).joined(separator: ", ")
                Text(names)
                    .font(.subheadline)
            } else {
                Text("No MIDI device connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}
