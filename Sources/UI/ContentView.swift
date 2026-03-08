import SwiftUI

struct ContentView: View {
    @Environment(Session.self) private var session
    @Environment(MIDIService.self) private var midiService
    @Environment(LoopEngine.self) private var engine: LoopEngine?
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: connection status + settings
            HStack {
                ConnectionStatusBar()
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Loop position
            LoopPositionIndicator()
                .padding(.horizontal)
                .padding(.vertical, 12)

            // Slot grid — takes up all available space
            SlotGrid()
                .padding(.horizontal)

            Spacer(minLength: 16)

            // Bottom actions
            HStack(spacing: 16) {
                Button {
                    engine?.sendAllNotesOff()
                } label: {
                    Label("Panic", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(ActionButtonStyle(colour: .red))

                Button {
                    engine?.sendAllNotesOff()
                    session.clearAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(ActionButtonStyle(colour: .gray))
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
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
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(colour.opacity(configuration.isPressed ? 0.6 : 1.0), in: RoundedRectangle(cornerRadius: 12))
    }
}
