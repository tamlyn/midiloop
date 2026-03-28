import SwiftUI
import UIKit

struct SlotGrid: View {
    @Environment(Session.self) private var session
    @Environment(LoopEngine.self) private var engine: LoopEngine?

    @State private var draggedSlotId: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var slotFrames: [Int: CGRect] = [:]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                slotCell(0)
                slotCell(1)
            }
            GridRow {
                slotCell(2)
                slotCell(3)
            }
        }
        .coordinateSpace(name: "grid")
    }

    @ViewBuilder
    private func slotCell(_ index: Int) -> some View {
        let slot = session.slots[index]
        let isSelected = slot.id == session.selectedSlotIndex
        let isDragging = draggedSlotId == slot.id
        let isDropTarget = draggedSlotId != nil && draggedSlotId != slot.id

        SlotView(slot: slot, isSelected: isSelected, showNotes: !isDragging)
            .overlay {
                if isDropTarget {
                    dropTargetOverlay(for: slot)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SlotFrameKey.self,
                        value: [slot.id: geo.frame(in: .named("grid"))]
                    )
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous))
            .overlay {
                TwoFingerTapView {
                    handleTwoFingerTap(slot)
                }
            }
            .onTapGesture {
                if slot.state == .playing || slot.state == .muted {
                    engine?.toggleMute(slot: slot)
                }
            }
            .gesture(dragGesture(for: slot))
            .zIndex(isDragging ? 1 : 0)
            .overlay {
                if isDragging {
                    SlotView(slot: slot, isSelected: false, showLabel: false)
                        .offset(dragOffset)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Slot \(slot.id + 1)")
            .accessibilityValue(slotAccessibilityValue(slot))
            .onPreferenceChange(SlotFrameKey.self) { frames in
                slotFrames.merge(frames) { _, new in new }
            }
    }

    // MARK: - Two-finger tap

    private func handleTwoFingerTap(_ slot: Slot) {
        if slot.id == session.selectedSlotIndex {
            // Already selected — arm for recording
            engine?.toggleRecording()
        } else {
            session.selectSlot(slot.id)
        }
    }

    // MARK: - Drag

    private func dragGesture(for slot: Slot) -> some Gesture {
        DragGesture(coordinateSpace: .named("grid"))
            .onChanged { value in
                guard slot.state == .playing || slot.state == .muted else { return }
                draggedSlotId = slot.id
                dragOffset = value.translation
            }
            .onEnded { value in
                guard draggedSlotId == slot.id else { return }
                handleDrop(source: slot, at: value.location)
                draggedSlotId = nil
                dragOffset = .zero
            }
    }

    private func handleDrop(source: Slot, at location: CGPoint) {
        // Check if dropped on another slot
        for (id, frame) in slotFrames where id != source.id {
            if frame.contains(location) {
                let target = session.slots[id]
                if target.state == .empty {
                    engine?.moveSlot(from: source, to: target)
                } else {
                    engine?.mergeSlot(source: source, into: target)
                }
                return
            }
        }

        // Dropped outside all slots — delete
        let droppedOnSelf = slotFrames[source.id].map { $0.contains(location) } ?? false
        if !droppedOnSelf {
            engine?.clearSlot(source)
        }
    }

    @ViewBuilder
    private func dropTargetOverlay(for slot: Slot) -> some View {
        RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous)
            .stroke(Theme.textSecondary.opacity(0.5), lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous)
                    .fill(Theme.panelLight.opacity(0.3))
            )
    }

    private func slotAccessibilityValue(_ slot: Slot) -> String {
        switch slot.state {
        case .empty: "Empty"
        case .armed: "Armed"
        case .recording: "Recording"
        case .playing: "Playing"
        case .muted: "Muted"
        }
    }
}

private struct SlotFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct SlotView: View {
    let slot: Slot
    let isSelected: Bool
    var showNotes: Bool = true
    var showLabel: Bool = true

    private var hasNotes: Bool {
        showNotes && !slot.noteBars.isEmpty
    }

    private var accentColour: Color {
        switch slot.state {
        case .armed: Theme.armed
        case .recording: Theme.recording
        default: Theme.textSecondary
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Dark panel background
            RoundedRectangle(cornerRadius: Theme.slotRadius, style: .continuous)
                .fill(Theme.panel)

            if hasNotes {
                // Piano roll fills the tile
                NoteRollView(
                    noteBars: slot.noteBars,
                    duration: slot.displayDuration,
                    playbackPosition: slot.playbackPosition,
                    showPlayhead: slot.state == .playing || slot.state == .muted,
                    dimmed: slot.state == .muted
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .allowsHitTesting(false)

                if showLabel {
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
                        .padding(.leading, 8)
                        .padding(.top, 8)
                        Spacer()
                    }
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
                    isSelected ? Theme.textSecondary.opacity(0.6) : Theme.panelLight.opacity(0.5),
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

/// Transparent overlay that detects two-finger taps via UIKit.
private struct TwoFingerTapView: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.numberOfTouchesRequired = 2
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
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
