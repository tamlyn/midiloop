import Foundation

enum PedalEvent {
    case down
    case up
    /// Quick press completed (down then up within threshold, no double detected)
    case quickPress
    /// Held beyond the long-press threshold
    case longPress
}

/// Filters soft pedal CC messages and emits pedal events.
/// Reports down/up immediately, plus gesture detection (quick/long press).
@MainActor @Observable
final class PedalController {
    var controlChangeNumber: UInt8 = 67 {
        didSet { onCCNumberChanged?(controlChangeNumber) }
    }
    var onPedalEvent: ((PedalEvent) -> Void)?
    var onCCNumberChanged: ((_ cc: UInt8) -> Void)?

    private let longPressThreshold: TimeInterval = 0.5

    private var pressTime: Date?
    private var longPressFired = false
    private var longPressTimer: Timer?

    /// Call when a CC message is received. Returns true if consumed.
    func handleCC(number: UInt8, value: UInt8) -> Bool {
        guard number == controlChangeNumber else { return false }

        if value >= 64 {
            pedalDown()
        } else {
            pedalUp()
        }

        return true
    }

    private func pedalDown() {
        pressTime = Date()
        longPressFired = false

        // Always emit down immediately
        onPedalEvent?(.down)

        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.longPressFired = true
                self?.onPedalEvent?(.longPress)
            }
        }
    }

    private func pedalUp() {
        longPressTimer?.invalidate()
        longPressTimer = nil

        // Always emit up immediately
        onPedalEvent?(.up)

        guard let press = pressTime else { return }
        let holdDuration = Date().timeIntervalSince(press)
        pressTime = nil

        // If it was a short press and long-press didn't fire, emit quickPress
        if holdDuration < longPressThreshold && !longPressFired {
            onPedalEvent?(.quickPress)
        }
    }
}
