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
    private var recordingStartTime: CFTimeInterval?
    private var playbackStartTime: CFTimeInterval = 0

    private var slotPlaybackIndices: [Int] = [0, 0, 0, 0]

    /// Tracks the last master loop position to detect boundary crossings.
    private var lastMasterPosition: TimeInterval = 0

    /// Set when recording stops, to prevent quickPress from toggling mute.
    private var suppressNextQuickPress = false

    init(session: Session, midiService: MIDIService) {
        self.session = session
        self.midiService = midiService
        self.pedalController = PedalController()

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
                selectedSlot.startRecording()
                recordingStartTime = CACurrentMediaTime()
            } else {
                return
            }
        }

        if selectedSlot.state == .recording {
            guard let startTime = recordingStartTime else { return }
            let timestamp = CACurrentMediaTime() - startTime
            selectedSlot.addEvent(RecordedEvent(timestamp: timestamp, event: event))
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

        if session.noteQuantisation != .off, let master = session.masterLoopDuration {
            slot.quantiseEvents(loopDuration: master, grid: session.noteQuantisation)
        }

        slot.stopRecording(duration: finalDuration)
        slotPlaybackIndices[slot.id] = 0
    }

    // MARK: - Armed → Recording transition

    /// Called from playbackTick when the master loop wraps around.
    private func transitionArmedSlots(boundaryTime: CFTimeInterval) {
        for slot in session.slots where slot.state == .armed {
            slot.startRecording()
            recordingStartTime = boundaryTime
        }
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

    // MARK: - Clear

    func clearAndAdvance() {
        let slot = session.selectedSlot
        if slot.state != .empty {
            midiService.sendNoteOffs(for: slot.activeNotes)
            slot.clear()

            if session.allSlotsEmpty {
                session.clearAll()
            }

            session.selectNextEmptySlot()
        }
    }

    func clearSlot(_ slot: Slot) {
        midiService.sendNoteOffs(for: slot.activeNotes)
        slot.clear()

        if session.allSlotsEmpty {
            session.clearAll()
        }
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

            let slotPosition = elapsed.truncatingRemainder(dividingBy: slot.duration)
            slot.playbackPosition = slotPosition

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
