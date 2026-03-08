import Foundation
import MIDIKitIO

/// Manages MIDI device connections, pass-through, and event routing.
@Observable
final class MIDIService {
    private let midi = MIDIManager(
        clientName: "MIDILoop",
        model: "MIDILoop",
        manufacturer: "Tamlyn"
    )

    private(set) var availableInputs: [MIDIEndpointIdentity] = []
    private(set) var availableOutputs: [MIDIEndpointIdentity] = []
    private(set) var isConnected = false

    var onMIDIEvent: ((_ event: MIDIEvent) -> Void)?

    init() {
        do {
            try midi.start()
        } catch {
            print("Failed to start MIDI manager: \(error)")
        }
    }
}
