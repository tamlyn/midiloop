import SwiftUI

enum Theme {
    // Backgrounds
    static let background = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let panel = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let panelLight = Color(red: 0.20, green: 0.20, blue: 0.22)

    // Text
    static let textPrimary = Color(red: 0.85, green: 0.85, blue: 0.87)
    static let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.58)

    // Per-slot colours (FL Studio channel rack style)
    static let slotColours: [Color] = [
        Color(red: 0.35, green: 0.62, blue: 0.58),  // teal
        Color(red: 0.68, green: 0.45, blue: 0.65),  // mauve
        Color(red: 0.72, green: 0.58, blue: 0.30),  // amber
        Color(red: 0.55, green: 0.62, blue: 0.75),  // slate blue
    ]

    // State colours
    static let armed = Color(red: 0.75, green: 0.55, blue: 0.20)
    static let recording = Color(red: 0.75, green: 0.28, blue: 0.25)

    // Slot corner radius (more angular than before)
    static let slotRadius: CGFloat = 6
    static let buttonRadius: CGFloat = 6

    static func slotColour(index: Int) -> Color {
        slotColours[index % slotColours.count]
    }
}
