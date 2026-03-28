import SwiftUI

struct SlotGrid: View {
    @Environment(Session.self) private var session
    @Environment(LoopEngine.self) private var engine: LoopEngine?

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                SlotButton(slot: session.slots[0], session: session, engine: engine)
                SlotButton(slot: session.slots[1], session: session, engine: engine)
            }
            GridRow {
                SlotButton(slot: session.slots[2], session: session, engine: engine)
                SlotButton(slot: session.slots[3], session: session, engine: engine)
            }
        }
    }
}

private struct SlotButton: View {
    let slot: Slot
    let session: Session
    let engine: LoopEngine?

    var body: some View {
        let isSelected = slot.id == session.selectedSlotIndex
        SlotView(slot: slot, isSelected: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous))
            .onTapGesture {
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
            .onLongPressGesture {
                engine?.clearSlot(slot)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Slot \(slot.id + 1)")
            .accessibilityValue(slotAccessibilityValue)
    }

    private var slotAccessibilityValue: String {
        switch slot.state {
        case .empty: "Empty"
        case .armed: "Armed"
        case .recording: "Recording"
        case .playing: "Playing"
        case .muted: "Muted"
        }
    }
}

struct SlotView: View {
    let slot: Slot
    let isSelected: Bool

    private var hasNotes: Bool {
        !slot.noteBars.isEmpty
    }

    private var clipColour: Color {
        Theme.slotColour(index: slot.id)
    }

    private var accentColour: Color {
        switch slot.state {
        case .armed: Theme.armed
        case .recording: Theme.recording
        default: clipColour
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Dark panel background
            RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous)
                .fill(Theme.panel)

            // Coloured left accent strip
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.slotRadius,
                bottomLeadingRadius: Theme.slotRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(accentColour)
            .frame(width: 5)

            if hasNotes {
                // Piano roll fills the tile
                NoteRollView(
                    noteBars: slot.noteBars,
                    duration: slot.displayDuration,
                    playbackPosition: slot.playbackPosition,
                    showPlayhead: slot.state == .playing || slot.state == .muted,
                    noteColour: slot.state == .muted
                        ? clipColour.opacity(0.35)
                        : clipColour
                )
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .allowsHitTesting(false)

                // Slot number and state overlay
                VStack {
                    HStack(spacing: 6) {
                        Text("\(slot.id + 1)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentColour)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        Text(stateLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        if slot.state == .recording {
                            Circle()
                                .fill(Theme.recording)
                                .frame(width: 8, height: 8)
                                .modifier(PulseAnimation())
                        }
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    Spacer()
                }
            } else {
                // Empty/recording state: centred content
                VStack(spacing: 8) {
                    Text("\(slot.id + 1)")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColour)

                    Text(stateLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)

                    if slot.state == .armed || slot.state == .recording {
                        Circle()
                            .fill(accentColour)
                            .frame(width: 10, height: 10)
                            .modifier(PulseAnimation())
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous)
                .stroke(
                    isSelected ? accentColour.opacity(0.8) : Theme.panelLight.opacity(0.5),
                    lineWidth: isSelected ? 2 : 1
                )
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
