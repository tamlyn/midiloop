import SwiftUI
import CoreAudioKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LoopEngine.self) private var engine: LoopEngine?

    var body: some View {
        NavigationStack {
            Form {
                Section("Bluetooth MIDI") {
                    BluetoothMIDIButton()
                }

                if let engine {
                    Section("Pedal Control") {
                        @Bindable var pedal = engine.pedalController
                        Picker("Control Change", selection: $pedal.controlChangeNumber) {
                            Text("CC#64 (Sustain)").tag(UInt8(64))
                            Text("CC#66 (Sostenuto)").tag(UInt8(66))
                            Text("CC#67 (Soft/Una Corda)").tag(UInt8(67))
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Wraps Apple's CABTMIDICentralViewController for Bluetooth MIDI pairing.
struct BluetoothMIDIButton: View {
    @State private var showingBluetooth = false

    var body: some View {
        Button("Connect Bluetooth MIDI Device") {
            showingBluetooth = true
        }
        .sheet(isPresented: $showingBluetooth) {
            BluetoothMIDIView()
                .ignoresSafeArea()
        }
    }
}

struct BluetoothMIDIView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let btVC = CABTMIDICentralViewController()
        let nav = UINavigationController(rootViewController: btVC)
        btVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismiss)
        )
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    class Coordinator: NSObject {
        @objc func dismiss() {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            root.dismiss(animated: true)
        }
    }
}
