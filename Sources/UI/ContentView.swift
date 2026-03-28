import SwiftUI

struct ContentView: View {
    @Environment(Session.self) private var session
    @Environment(MIDIService.self) private var midiService
    @Environment(LoopEngine.self) private var engine: LoopEngine?
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: connection status + actions + settings
            HStack(spacing: 12) {
                ConnectionStatusBar()

                Spacer()

                Button {
                    engine?.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(ActionButtonStyle(colour: Theme.panelLight))
                .disabled(!(engine?.canUndo ?? false))

                Button {
                    engine?.sendAllNotesOff()
                } label: {
                    Label("Panic", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(ActionButtonStyle(colour: Theme.recording))

                Button {
                    engine?.clearAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(ActionButtonStyle(colour: Theme.panelLight))

                Button("Settings", systemImage: "gearshape.fill") {
                    showingSettings = true
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .padding(8)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Slot grid — takes up all available space
            SlotGrid()
                .padding(.horizontal)
                .padding(.top, 12)

            Spacer(minLength: 16)
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct ActionButtonStyle: ButtonStyle {
    let colour: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                colour.opacity(configuration.isPressed ? 0.6 : 1.0),
                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
            )
    }
}
