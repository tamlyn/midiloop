import SwiftUI
import MIDIKitIO

struct ConnectionStatusBar: View {
    @Environment(ObservableMIDIManager.self) private var midiManager

    var body: some View {
        HStack(spacing: 8) {
            let outputCount = midiManager.endpoints.outputs.count
            Circle()
                .fill(outputCount > 0 ? Theme.takeColours[0] : Theme.recording)
                .frame(width: 8, height: 8)

            if outputCount > 0 {
                let names = midiManager.endpoints.outputs.map(\.name).joined(separator: ", ")
                Text(names)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            } else {
                Text("No MIDI device")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
