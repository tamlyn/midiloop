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
@MainActor @Observable
final class PedalController {
    var controlChangeNumber: UInt8 = 67 {
        didSet { onCCNumberChanged?(controlChangeNumber) }
    }
    var onGesture: ((PedalGesture) -> Void)?
    var onCCNumberChanged: ((_ cc: UInt8) -> Void)?

    private let longPressThreshold: TimeInterval = 0.5
    private let doublePressWindow: TimeInterval = 0.35

    private var pressTime: Date?
    private var lastQuickPressTime: Date?
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
        longPressTimer?.invalidate()

        // Timer fires on the main run loop — safe to access main actor state
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onGesture?(.longPress)
                self?.pressTime = nil
            }
        }
    }

    private func pedalUp() {
        longPressTimer?.invalidate()
        longPressTimer = nil

        guard let press = pressTime else { return }
        let holdDuration = Date().timeIntervalSince(press)
        pressTime = nil

        guard holdDuration < longPressThreshold else { return }

        if let lastQuick = lastQuickPressTime,
           Date().timeIntervalSince(lastQuick) < doublePressWindow {
            lastQuickPressTime = nil
            onGesture?(.doublePress)
        } else {
            lastQuickPressTime = Date()
            Timer.scheduledTimer(withTimeInterval: doublePressWindow, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.lastQuickPressTime != nil else { return }
                    self.lastQuickPressTime = nil
                    self.onGesture?(.quickPress)
                }
            }
        }
    }
}
