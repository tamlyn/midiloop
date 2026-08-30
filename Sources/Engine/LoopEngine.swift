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

    /// Channels where the player is currently holding the sustain pedal,
    /// tracked from incoming CC64 so recordings can capture pre-held sustain.
    private var heldSustainChannels: Set<UInt4> = []

    /// Set when recording stops, to prevent quickPress from toggling mute.
    private var suppressNextQuickPress = false

    private var recordingTakeIndex: Int = 0

    /// Undo stack for reversible operations.
    private var undoStack: [UndoEntry] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var undoCount: Int { undoStack.count }
    private(set) var pendingRecordingSnapshot: UndoEntry?
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

    func handleIncomingEvent(_ event: MIDIEvent) {
        if case .cc(let payload) = event {
            if pedalController.handleCC(
                number: UInt8(payload.controller.number),
                value: UInt8(payload.value.midi1Value)
            ) {
                return
            }
            if payload.controller.number == 64 {
                if payload.value.midi1Value >= 64 {
                    heldSustainChannels.insert(payload.channel)
                } else {
                    heldSustainChannels.remove(payload.channel)
                }
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
                injectHeldSustain(into: selectedSlot)
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
        slotPlaybackOffsets[slot.id] = startTime - playbackStartTime
        resyncPlayback(for: slot, at: startTime + rawDuration)

        commitPendingRecordingUndo()
    }

    /// Aligns a slot's playback index with the current loop position without
    /// sending anything, so playback resumes cleanly instead of bursting
    /// through every event between the stale index and the current position.
    private func resyncPlayback(for slot: Slot, at now: CFTimeInterval = CACurrentMediaTime()) {
        guard slot.duration > 0 else { return }
        let position = (now - playbackStartTime - slotPlaybackOffsets[slot.id])
            .truncatingRemainder(dividingBy: slot.duration)
        slotPlaybackPositions[slot.id] = position
        slotPlaybackIndices[slot.id] =
            slot.events.firstIndex { $0.timestamp >= position } ?? slot.events.count
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
            injectHeldSustain(into: slot)
            for item in earlyMIDIEvents {
                slot.addEvent(RecordedEvent(timestamp: 0.0, takeIndex: recordingTakeIndex, event: item.event))
            }
        }
        preRollBuffer.removeAll()
    }

    /// If the sustain pedal is already down when recording starts, record it
    /// at the top of the loop so playback sustains the same way.
    private func injectHeldSustain(into slot: Slot) {
        for channel in heldSustainChannels {
            slot.addEvent(RecordedEvent(
                timestamp: 0.0,
                takeIndex: recordingTakeIndex,
                event: .cc(64, value: .midi1(127), channel: channel)
            ))
        }
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
        toggleMute(slot: session.selectedSlot)
    }

    /// Toggle mute on a specific slot (for tap gesture on any slot).
    func toggleMute(slot: Slot) {
        if slot.state == .playing {
            silence(slot)
            slot.toggleMute()
        } else if slot.state == .muted {
            resyncPlayback(for: slot)
            slot.toggleMute()
        }
    }

    /// Cuts everything this slot is sounding: note-offs for active notes and
    /// sustain-off for any channel where its playback holds the pedal.
    private func silence(_ slot: Slot) {
        midiService.sendNoteOffs(for: slot.activeNotes)
        midiService.sendSustainOff(channels: slot.sustainChannels)
        slot.clearActiveNotes()
    }

    // MARK: - Move & Merge

    /// Move a slot's content to an empty target slot.
    func moveSlot(from source: Slot, to target: Slot) {
        guard target.state == .empty else { return }
        pushUndo(label: "Move", slots: [source, target])
        silence(source)

        target.acceptTransfer(from: source)
        slotPlaybackOffsets[target.id] = slotPlaybackOffsets[source.id]
        slotPlaybackIndices[target.id] = slotPlaybackIndices[source.id]
        slotPlaybackPositions[target.id] = slotPlaybackPositions[source.id]

        source.clear()
        slotPlaybackOffsets[source.id] = 0
        slotPlaybackIndices[source.id] = 0
        slotPlaybackPositions[source.id] = 0
    }

    /// Merge a slot's events into another non-empty slot.
    func mergeSlot(source: Slot, into target: Slot) {
        pushUndo(label: "Merge", slots: [source, target])
        silence(source)

        target.mergeEvents(from: source)

        source.clear()
        slotPlaybackOffsets[source.id] = 0
        slotPlaybackIndices[source.id] = 0

        // Merged-in events behind the current position must not burst-replay
        resyncPlayback(for: target)
    }

    // MARK: - Clear

    func clearAndAdvance() {
        let slot = session.selectedSlot
        if slot.state != .empty {
            pushUndo(label: "Clear", slots: [slot])
            silence(slot)
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
        lastMasterPosition = 0
        undoStack.removeAll()
        pendingRecordingSnapshot = nil
    }

    func clearSlot(_ slot: Slot) {
        pushUndo(label: "Clear", slots: [slot])
        silence(slot)
        slot.clear()

        if session.allSlotsEmpty {
            session.clearAll()
        }
    }

    // MARK: - Undo

    private func makeUndoEntry(label: String, slots: [Slot]) -> UndoEntry {
        UndoEntry(
            label: label,
            slotSnapshots: slots.map { $0.snapshot() },
            playbackOffsets: slotPlaybackOffsets,
            masterLoopDuration: session.masterLoopDuration,
            selectedSlotIndex: session.selectedSlotIndex
        )
    }

    private func appendToUndoStack(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
    }

    private func pushUndo(label: String, slots: [Slot]) {
        appendToUndoStack(makeUndoEntry(label: label, slots: slots))
    }

    func capturePendingRecordingSnapshot(for slot: Slot) {
        pendingRecordingSnapshot = makeUndoEntry(label: "Record", slots: [slot])
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }

        // Silence any active notes in affected slots
        for snapshot in entry.slotSnapshots {
            let slot = session.slots[snapshot.slotId]
            silence(slot)
            slot.restore(from: snapshot)
            // Armed is transient (pedal held) — never restore to it
            if slot.state == .armed {
                slot.clear()
            }
        }

        slotPlaybackOffsets = entry.playbackOffsets

        // Restore session state
        session.restoreMasterLoopDuration(entry.masterLoopDuration)
        session.selectSlot(entry.selectedSlotIndex)

        // Indices from snapshot time are stale — realign with the clock
        for snapshot in entry.slotSnapshots {
            resyncPlayback(for: session.slots[snapshot.slotId])
        }
    }

    func commitPendingRecordingUndo() {
        if let snapshot = pendingRecordingSnapshot {
            appendToUndoStack(snapshot)
            pendingRecordingSnapshot = nil
        }
    }

    // MARK: - Playback Loop

    private func startPlaybackLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(playbackTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func playbackTick() {
        tick(now: CACurrentMediaTime())
    }

    func tick(now: CFTimeInterval) {
        guard let masterDuration = session.masterLoopDuration else { return }

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
            guard slot.state == .playing || slot.state == .muted, slot.duration > 0 else { continue }

            let slotElapsed = elapsed - slotPlaybackOffsets[slot.id]
            let slotPosition = slotElapsed.truncatingRemainder(dividingBy: slot.duration)
            let wrapped = slotPosition < slotPlaybackPositions[slot.id]
            slotPlaybackPositions[slot.id] = slotPosition

            guard slot.state == .playing, !slot.events.isEmpty else { continue }
            var idx = slotPlaybackIndices[slot.id]

            if wrapped {
                // Play out the tail the previous tick didn't reach — notably
                // note-offs landing exactly on the loop end — then cut
                // anything still sounding before restarting the loop.
                while idx < slot.events.count {
                    play(slot.events[idx], on: slot)
                    idx += 1
                }
                silence(slot)
                idx = 0
            }

            while idx < slot.events.count && slot.events[idx].timestamp <= slotPosition {
                play(slot.events[idx], on: slot)
                idx += 1
            }
            slotPlaybackIndices[slot.id] = idx
        }
    }

    private func play(_ recorded: RecordedEvent, on slot: Slot) {
        midiService.send(event: recorded.event)
        trackNote(event: recorded.event, slot: slot)
    }

    private func trackNote(event: MIDIEvent, slot: Slot) {
        switch event {
        case .noteOn(let payload):
            slot.trackNoteOn(note: payload.note.number, channel: payload.channel)
        case .noteOff(let payload):
            slot.trackNoteOff(note: payload.note.number, channel: payload.channel)
        case .cc(let payload) where payload.controller.number == 64:
            slot.trackSustain(channel: payload.channel, down: payload.value.midi1Value >= 64)
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
