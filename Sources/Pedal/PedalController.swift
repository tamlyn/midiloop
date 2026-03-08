import Foundation

enum PedalGesture {
    case quickPress
    case doublePress
    case longPress
}

/// Recognises gestures from soft pedal CC messages.
/// Quick press: press and release within the threshold.
/// Double press: two quick presses within the double-press window.
/// Long press: held beyond the long-press threshold.
@Observable
final class PedalController {
    var controlChangeNumber: UInt8 = 67
    var onGesture: ((PedalGesture) -> Void)?

    private let longPressThreshold: TimeInterval = 0.5
    private let doublePressWindow: TimeInterval = 0.35

    private var pressTime: Date?
    private var lastQuickPressTime: Date?
    private var longPressTimer: Timer?

    /// Call when a CC message is received. Returns true if consumed.
    func handleCC(number: UInt8, value: UInt8) -> Bool {
        guard number == controlChangeNumber else { return false }

        let isPressed = value >= 64

        if isPressed {
            pedalDown()
        } else {
            pedalUp()
        }

        return true
    }

    private func pedalDown() {
        pressTime = Date()
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
            self?.onGesture?(.longPress)
            self?.pressTime = nil
        }
    }

    private func pedalUp() {
        longPressTimer?.invalidate()
        longPressTimer = nil

        guard let press = pressTime else { return }
        let holdDuration = Date().timeIntervalSince(press)
        pressTime = nil

        guard holdDuration < longPressThreshold else { return }

        // Quick press detected — check for double press
        if let lastQuick = lastQuickPressTime,
           Date().timeIntervalSince(lastQuick) < doublePressWindow {
            lastQuickPressTime = nil
            onGesture?(.doublePress)
        } else {
            lastQuickPressTime = Date()
            // Delay to see if a second press follows
            Timer.scheduledTimer(withTimeInterval: doublePressWindow, repeats: false) { [weak self] _ in
                guard let self, self.lastQuickPressTime != nil else { return }
                self.lastQuickPressTime = nil
                self.onGesture?(.quickPress)
            }
        }
    }
}
