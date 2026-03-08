import SwiftUI

struct SlotGrid: View {
    @Environment(Session.self) private var session

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(session.slots) { slot in
                SlotView(slot: slot, isSelected: slot.id == session.selectedSlotIndex)
                    .onTapGesture {
                        handleTap(slot)
                    }
            }
        }
        .padding(.horizontal)
    }

    private func handleTap(_ slot: Slot) {
        let index = slot.id
        if index == session.selectedSlotIndex {
            // Tap on selected slot: toggle state
            switch slot.state {
            case .empty:
                slot.startRecording()
            case .recording:
                // TODO: stop recording via engine
                break
            case .playing:
                slot.toggleMute()
            case .muted:
                slot.toggleMute()
            }
        } else {
            session.selectSlot(index)
        }
    }
}

struct SlotView: View {
    let slot: Slot
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Slot \(slot.id + 1)")
                .font(.title2.bold())

            Text(stateLabel)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(backgroundColour, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? .white : .clear, lineWidth: 3)
        )
    }

    private var stateLabel: String {
        switch slot.state {
        case .empty: "Empty"
        case .recording: "Recording"
        case .playing: "Playing"
        case .muted: "Muted"
        }
    }

    private var backgroundColour: Color {
        switch slot.state {
        case .empty: .gray.opacity(0.3)
        case .recording: .red.opacity(0.7)
        case .playing: .green.opacity(0.7)
        case .muted: .orange.opacity(0.5)
        }
    }
}
