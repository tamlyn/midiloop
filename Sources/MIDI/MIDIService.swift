import Foundation
import MIDIKitIO

/// Manages MIDI connections and event routing.
/// Pass-through happens directly on the MIDI thread for minimum latency.
/// Other event processing is forwarded via a callback.
@Observable
final class MIDIService: @unchecked Sendable {
    let midi: ObservableMIDIManager

    /// Called on a background thread with each incoming MIDI event.
    /// Set by LoopEngine to receive events for recording/pedal processing.
    var onMIDIEvent: (@Sendable (_ event: MIDIEvent) -> Void)?

    /// When true, incoming events are echoed to the output immediately.
    var passThrough = true {
        didSet { UserDefaults.standard.set(passThrough, forKey: "passThrough") }
    }

    /// CC numbers that should NOT be passed through (consumed by pedal control).
    var consumedCCs: Set<UInt8> = [67]

    static let inputConnectionTag = "MainInput"
    static let outputConnectionTag = "MainOutput"

    init() {
        if UserDefaults.standard.object(forKey: "passThrough") != nil {
            passThrough = UserDefaults.standard.bool(forKey: "passThrough")
        }

        midi = ObservableMIDIManager(
            clientName: "MIDILoop",
            model: "MIDILoop",
            manufacturer: "Tamlyn"
        )

        // BLE MIDI only supports MIDI 1.0
        midi.preferredAPI = .legacyCoreMIDI

        do {
            try midi.start()
        } catch {
            print("Failed to start MIDI manager: \(error)")
        }

        setupConnections()
    }

    private func setupConnections() {
        do {
            try midi.addInputConnection(
                to: .allOutputs,
                tag: Self.inputConnectionTag,
                filter: .owned(),
                receiver: .events { [weak self] events, _, _ in
                    guard let self else { return }
                    for event in events {
                        self.handleIncoming(event)
                    }
                }
            )
        } catch {
            print("Failed to create input connection: \(error)")
        }

        do {
            try midi.addOutputConnection(
                to: .allInputs,
                tag: Self.outputConnectionTag,
                filter: .owned()
            )
        } catch {
            print("Failed to create output connection: \(error)")
        }
    }

    private func handleIncoming(_ event: MIDIEvent) {
        if passThrough {
            let shouldPassThrough: Bool
            if case .cc(let payload) = event {
                shouldPassThrough = !consumedCCs.contains(UInt8(payload.controller.number))
            } else {
                shouldPassThrough = true
            }
            if shouldPassThrough {
                send(event: event)
            }
        }

        onMIDIEvent?(event)
    }

    func send(event: MIDIEvent) {
        guard let connection = midi.managedOutputConnections[Self.outputConnectionTag] else {
            return
        }
        do {
            try connection.send(event: event)
        } catch {}
    }

    func send(events: [MIDIEvent]) {
        guard let connection = midi.managedOutputConnections[Self.outputConnectionTag] else {
            return
        }
        do {
            try connection.send(events: events)
        } catch {}
    }

    func sendNoteOffs(for notes: Set<NoteKey>) {
        let events = notes.map { key in
            MIDIEvent.noteOff(key.note, velocity: .midi1(0), channel: key.channel)
        }
        send(events: events)
    }

    func sendAllNotesOff() {
        let events = (0..<16).map { channel in
            MIDIEvent.cc(123, value: .midi1(0), channel: UInt4(channel))
        }
        send(events: events)
    }
}
