import SwiftUI

struct SlotGrid: View {
    @Environment(Session.self) private var session
    @Environment(LoopEngine.self) private var engine: LoopEngine?

    var body: some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                slotButton(session.slots[0])
                slotButton(session.slots[1])
            }
            GridRow {
                slotButton(session.slots[2])
                slotButton(session.slots[3])
            }
        }
    }

    @ViewBuilder
    private func slotButton(_ slot: Slot) -> some View {
        let isSelected = slot.id == session.selectedSlotIndex
        SlotView(slot: slot, isSelected: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .onTapGesture {
                handleTap(slot)
            }
            .onLongPressGesture {
                engine?.clearSlot(slot)
            }
    }

    private func handleTap(_ slot: Slot) {
        if slot.id == session.selectedSlotIndex {
            switch slot.state {
            case .empty, .armed, .recording:
                engine?.toggleRecording()
            case .playing, .muted:
                engine?.toggleMute()
            }
        } else {
            session.selectSlot(slot.id)
        }
    }
}

struct SlotView: View {
    let slot: Slot
    let isSelected: Bool

    private var hasNotes: Bool {
        !slot.noteBars.isEmpty
    }

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColour)

            if hasNotes {
                // Piano roll fills the tile
                NoteRollView(
                    noteBars: slot.noteBars,
                    duration: slot.duration,
                    playbackPosition: slot.playbackPosition,
                    isPlaying: slot.state == .playing
                )
                .padding(12)
                .allowsHitTesting(false)

                // Slot number and state as overlay at top-left
                VStack {
                    HStack {
                        Text("\(slot.id + 1)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        Text(stateLabel)
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .padding(12)
                    Spacer()
                }
            } else {
                // Empty/recording state: large centred content
                VStack(spacing: 12) {
                    Text("\(slot.id + 1)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))

                    Text(stateLabel)
                        .font(.title3.weight(.semibold))

                    if slot.state == .armed || slot.state == .recording {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .modifier(PulseAnimation())
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? .white : .clear, lineWidth: 4)
        )
    }

    private var stateLabel: String {
        switch slot.state {
        case .empty: "EMPTY"
        case .armed: "ARMED"
        case .recording: "REC"
        case .playing: "PLAY"
        case .muted: "MUTED"
        }
    }

    private var backgroundColour: Color {
        switch slot.state {
        case .empty: .gray.opacity(0.25)
        case .armed: .red.opacity(0.4)
        case .recording: .red
        case .playing: .green.opacity(0.75)
        case .muted: .orange.opacity(0.5)
        }
    }
}

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
