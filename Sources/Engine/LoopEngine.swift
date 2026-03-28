import Foundation
import MIDIKitIO
import QuartzCore

/// Coordinates recording, playback, and pedal control.
/// All methods run on the main actor.
@MainActor @Observable
final class LoopEngine {
    let session: Session
    let midiService: MIDIService
    let pedalController: PedalController

    private var displayLink: CADisplayLink?
    var recordingStartTime: CFTimeInterval?
    var playbackStartTime: CFTimeInterval = 0

    private var slotPlaybackIndices: [Int] = [0, 0, 0, 0]
    var slotPlaybackOffsets: [TimeInterval] = [0, 0, 0, 0]
    private(set) var slotPlaybackPositions: [TimeInterval] = [0, 0, 0, 0]

    /// Events received while a slot is armed, kept for pre-roll capture.
    var preRollBuffer: [(event: MIDIEvent, wallTime: CFTimeInterval)] = []

    /// Tracks the last master loop position to detect boundary crossings.
    private var lastMasterPosition: TimeInterval = 0

    /// Set when recording stops, to prevent quickPress from toggling mute.
    private var suppressNextQuickPress = false

    /// Colour index for the current recording take.
    private var recordingTakeIndex: Int = 0

    /// Undo stack for reversible operations.
    private var undoStack: [UndoEntry] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var undoCount: Int { undoStack.count }
    var pendingRecordingSnapshot: UndoEntry?
    private let maxUndoDepth = 10

    init(session: Session, midiService: MIDIService, pedalController: PedalController) {
        self.session = session
        self.midiService = midiService
        self.pedalController = pedalController

        midiService.consumedCCs = [pedalController.controlChangeNumber]

        midiService.onMIDIEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleIncomingEvent(event)
            }
        }

        pedalController.onPedalEvent = { [weak self] event in
            self?.handlePedalEvent(event)
        }

        pedalController.onCCNumberChanged = { [weak midiService] cc in
            midiService?.consumedCCs = [cc]
        }

        startPlaybackLoop()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - Incoming MIDI

    private func handleIncomingEvent(_ event: MIDIEvent) {
        if case .cc(let payload) = event {
            if pedalController.handleCC(
                number: UInt8(payload.controller.number),
                value: UInt8(payload.value.midi1Value)
            ) {
                return
            }
        }

        let selectedSlot = session.selectedSlot

        // First loop: armed slot transitions to recording on first note
        if selectedSlot.state == .armed && session.masterLoopDuration == nil {
            if case .noteOn = event {
                capturePendingRecordingSnapshot(for: selectedSlot)
                selectedSlot.startRecording()
                recordingStartTime = CACurrentMediaTime()
                recordingTakeIndex = session.claimNextTakeIndex()
            } else {
                return
            }
        }

        // Buffer events while armed, for pre-roll capture at the loop boundary
        if selectedSlot.state == .armed && session.masterLoopDuration != nil {
            let now = CACurrentMediaTime()
            preRollBuffer.append((event: event, wallTime: now))
            preRollBuffer.removeAll { now - $0.wallTime > 1.0 }
            return
        }

        if selectedSlot.state == .recording {
            guard let startTime = recordingStartTime else { return }
            let timestamp = CACurrentMediaTime() - startTime
            selectedSlot.addEvent(RecordedEvent(timestamp: timestamp, takeIndex: recordingTakeIndex, event: event))
        }
    }

    // MARK: - Pedal Events

    private func handlePedalEvent(_ event: PedalEvent) {
        let slot = session.selectedSlot

        switch event {
        case .down:
            if slot.state == .empty {
                slot.arm()
            }

        case .up:
            if slot.state == .recording {
                stopRecording(slot)
                suppressNextQuickPress = true
            } else if slot.state == .armed {
                // Released before recording started — cancel
                slot.clear()
                preRollBuffer.removeAll()
                pendingRecordingSnapshot = nil
                suppressNextQuickPress = true
            }

        case .quickPress:
            if suppressNextQuickPress {
                suppressNextQuickPress = false
                return
            }
            if slot.state == .playing || slot.state == .muted {
                toggleMute()
            }

        case .longPress:
            if slot.state != .recording && slot.state != .armed {
                clearAndAdvance()
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        let slot = session.selectedSlot
        guard slot.state == .empty else { return }
        slot.arm()
    }

    func toggleRecording() {
        let slot = session.selectedSlot
        switch slot.state {
        case .empty:
            startRecording()
        case .armed:
            slot.clear()
            pendingRecordingSnapshot = nil
        case .recording:
            stopRecording(slot)
        default:
            break
        }
    }

    private func stopRecording(_ slot: Slot) {
        guard let startTime = recordingStartTime else {
            slot.clear()
            return
        }

        let rawDuration = CACurrentMediaTime() - startTime

        let finalDuration: TimeInterval
        if session.masterLoopDuration == nil {
            session.setMasterLoopDuration(rawDuration)
            finalDuration = rawDuration
            playbackStartTime = startTime
        } else {
            finalDuration = session.quantisedDuration(for: rawDuration)
        }

        if session.noteQuantisation != .off {
            slot.quantiseEvents(loopDuration: finalDuration, grid: session.noteQuantisation)
        }

        slot.stopRecording(duration: finalDuration)
        slotPlaybackIndices[slot.id] = 0
        slotPlaybackOffsets[slot.id] = startTime - playbackStartTime

        commitPendingRecordingUndo()
    }

    // MARK: - Armed → Recording transition

    /// Called from playbackTick when the master loop wraps around.
    func transitionArmedSlots(boundaryTime: CFTimeInterval) {
        let preRollWindow = computePreRollWindow()
        let cutoff = boundaryTime - preRollWindow
        let earlyMIDIEvents = preRollBuffer
            .filter { $0.wallTime >= cutoff && $0.wallTime < boundaryTime }

        for slot in session.slots where slot.state == .armed {
            capturePendingRecordingSnapshot(for: slot)
            slot.startRecording()
            recordingStartTime = boundaryTime
            recordingTakeIndex = session.claimNextTakeIndex()
            for item in earlyMIDIEvents {
                slot.addEvent(RecordedEvent(timestamp: 0.0, takeIndex: recordingTakeIndex, event: item.event))
            }
        }
        preRollBuffer.removeAll()
    }

    private func computePreRollWindow() -> TimeInterval {
        guard let masterDuration = session.masterLoopDuration else { return 0 }
        if session.noteQuantisation != .off {
            let gridInterval = masterDuration / Double(session.noteQuantisation.rawValue)
            return min(gridInterval / 2.0, 0.5)
        }
        return 0.030
    }

    // MARK: - Mute/Unmute

    func toggleMute() {
        let slot = session.selectedSlot
        if slot.state == .playing {
            midiService.sendNoteOffs(for: slot.activeNotes)
            slot.clearActiveNotes()
            slot.toggleMute()
        } else if slot.state == .muted {
            slot.toggleMute()
        }
    }

    /// Toggle mute on a specific slot (for tap gesture on any slot).
    func toggleMute(slot: Slot) {
        if slot.state == .playing {
            midiService.sendNoteOffs(for: slot.activeNotes)
            slot.clearActiveNotes()
            slot.toggleMute()
        } else if slot.state == .muted {
            slot.toggleMute()
        }
    }

    // MARK: - Move & Merge

    /// Move a slot's content to an empty target slot.
    func moveSlot(from source: Slot, to target: Slot) {
        guard target.state == .empty else { return }
        midiService.sendNoteOffs(for: source.activeNotes)
        source.clearActiveNotes()

        target.acceptTransfer(from: source)
        slotPlaybackOffsets[target.id] = slotPlaybackOffsets[source.id]
        slotPlaybackIndices[target.id] = slotPlaybackIndices[source.id]

        source.clear()
        slotPlaybackOffsets[source.id] = 0
        slotPlaybackIndices[source.id] = 0
    }

    /// Merge a slot's events into another non-empty slot.
    func mergeSlot(source: Slot, into target: Slot) {
        pushUndo(label: "Merge", slots: [source, target])
        midiService.sendNoteOffs(for: source.activeNotes)
        source.clearActiveNotes()

        target.mergeEvents(from: source)

        source.clear()
        slotPlaybackOffsets[source.id] = 0
        slotPlaybackIndices[source.id] = 0

        // Reset target playback index so merged events play correctly
        slotPlaybackIndices[target.id] = 0
    }

    // MARK: - Clear

    func clearAndAdvance() {
        let slot = session.selectedSlot
        if slot.state != .empty {
            pushUndo(label: "Clear", slots: [slot])
            midiService.sendNoteOffs(for: slot.activeNotes)
            slot.clear()

            if session.allSlotsEmpty {
                session.clearAll()
            }

            session.selectNextEmptySlot()
        }
    }

    func clearAll() {
        sendAllNotesOff()
        session.clearAll()
        slotPlaybackIndices = [0, 0, 0, 0]
        slotPlaybackOffsets = [0, 0, 0, 0]
        slotPlaybackPositions = [0, 0, 0, 0]
        undoStack.removeAll()
        pendingRecordingSnapshot = nil
    }

    func clearSlot(_ slot: Slot) {
        pushUndo(label: "Clear", slots: [slot])
        midiService.sendNoteOffs(for: slot.activeNotes)
        slot.clear()

        if session.allSlotsEmpty {
            session.clearAll()
        }
    }

    // MARK: - Undo

    private func pushUndo(label: String, slots: [Slot]) {
        let entry = UndoEntry(
            label: label,
            slotSnapshots: slots.map { $0.snapshot() },
            playbackIndices: slotPlaybackIndices,
            playbackOffsets: slotPlaybackOffsets,
            masterLoopDuration: session.masterLoopDuration,
            selectedSlotIndex: session.selectedSlotIndex
        )
        undoStack.append(entry)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
    }

    func capturePendingRecordingSnapshot(for slot: Slot) {
        pendingRecordingSnapshot = UndoEntry(
            label: "Record",
            slotSnapshots: [slot.snapshot()],
            playbackIndices: slotPlaybackIndices,
            playbackOffsets: slotPlaybackOffsets,
            masterLoopDuration: session.masterLoopDuration,
            selectedSlotIndex: session.selectedSlotIndex
        )
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }

        // Silence any active notes in affected slots
        for snapshot in entry.slotSnapshots {
            let slot = session.slots[snapshot.slotId]
            midiService.sendNoteOffs(for: slot.activeNotes)
            slot.restore(from: snapshot)
        }

        // Restore engine playback state
        slotPlaybackIndices = entry.playbackIndices
        slotPlaybackOffsets = entry.playbackOffsets

        // Restore session state
        session.restoreMasterLoopDuration(entry.masterLoopDuration)
        session.selectSlot(entry.selectedSlotIndex)
    }

    func commitPendingRecordingUndo() {
        if let snapshot = pendingRecordingSnapshot {
            undoStack.append(snapshot)
            if undoStack.count > maxUndoDepth {
                undoStack.removeFirst()
            }
            pendingRecordingSnapshot = nil
        }
    }

    func clearUndoStack() {
        undoStack.removeAll()
    }

    // MARK: - Playback Loop

    private func startPlaybackLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(playbackTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func playbackTick() {
        guard let masterDuration = session.masterLoopDuration else { return }

        let now = CACurrentMediaTime()
        let elapsed = now - playbackStartTime
        let masterPosition = elapsed.truncatingRemainder(dividingBy: masterDuration)

        // Detect master loop boundary crossing
        if masterPosition < lastMasterPosition {
            // The loop just wrapped — transition any armed slots
            let boundaryTime = now - masterPosition
            transitionArmedSlots(boundaryTime: boundaryTime)
        }
        lastMasterPosition = masterPosition
        session.updateLoopPosition(masterPosition)

        for slot in session.slots {
            guard slot.state == .playing || slot.state == .muted else { continue }
            guard slot.duration > 0 else { continue }

            let slotElapsed = elapsed - slotPlaybackOffsets[slot.id]
            let slotPosition = slotElapsed.truncatingRemainder(dividingBy: slot.duration)
            slotPlaybackPositions[slot.id] = slotPosition

            guard slot.state == .playing, !slot.events.isEmpty else { continue }
            let index = slotPlaybackIndices[slot.id]

            // Detect loop wrap-around
            if index > 0 && index < slot.events.count {
                if slotPosition < slot.events[index - 1].timestamp {
                    midiService.sendNoteOffs(for: slot.activeNotes)
                    slot.clearActiveNotes()
                    slotPlaybackIndices[slot.id] = 0
                }
            } else if index >= slot.events.count {
                if let lastTimestamp = slot.events.last?.timestamp, slotPosition < lastTimestamp {
                    midiService.sendNoteOffs(for: slot.activeNotes)
                    slot.clearActiveNotes()
                    slotPlaybackIndices[slot.id] = 0
                }
            }

            var idx = slotPlaybackIndices[slot.id]
            while idx < slot.events.count && slot.events[idx].timestamp <= slotPosition {
                let recorded = slot.events[idx]
                midiService.send(event: recorded.event)
                trackNote(event: recorded.event, slot: slot)
                idx += 1
            }
            slotPlaybackIndices[slot.id] = idx
        }
    }

    private func trackNote(event: MIDIEvent, slot: Slot) {
        switch event {
        case .noteOn(let payload):
            slot.trackNoteOn(note: payload.note.number, channel: payload.channel)
        case .noteOff(let payload):
            slot.trackNoteOff(note: payload.note.number, channel: payload.channel)
        default:
            break
        }
    }

    // MARK: - Cleanup

    func sendAllNotesOff() {
        midiService.sendAllNotesOff()
        for slot in session.slots {
            slot.clearActiveNotes()
        }
    }
}
