import MIDIKitCore
import QuartzCore
@testable import MIDILoop

@MainActor
func recordClip(
    engine: LoopEngine,
    session: Session,
    slotIndex: Int,
    events: [RecordedEvent],
    rawDuration: TimeInterval,
    applyQuantisation: Bool = false
) {
    session.selectSlot(slotIndex)
    let slot = session.selectedSlot
    slot.startRecording()

    for event in events {
        slot.addEvent(event)
    }

    let finalDuration: TimeInterval
    if session.masterLoopDuration == nil {
        session.setMasterLoopDuration(rawDuration)
        finalDuration = rawDuration
        engine.playbackStartTime = CACurrentMediaTime() - rawDuration
    } else {
        finalDuration = session.quantisedDuration(for: rawDuration)
    }

    if applyQuantisation && session.noteQuantisation != .off {
        slot.quantiseEvents(loopDuration: finalDuration, grid: session.noteQuantisation)
    }

    slot.stopRecording(duration: finalDuration)
    engine.slotPlaybackOffsets[slot.id] = 0
}

func noteOn(_ note: UInt7, at t: TimeInterval) -> RecordedEvent {
    RecordedEvent(
        timestamp: t,
        event: .noteOn(MIDIEvent.NoteOn(note: note, velocity: .midi1(100), channel: 0))
    )
}

func noteOff(_ note: UInt7, at t: TimeInterval) -> RecordedEvent {
    RecordedEvent(
        timestamp: t,
        event: .noteOff(MIDIEvent.NoteOff(note: note, velocity: .midi1(0), channel: 0))
    )
}

func sustain(_ value: UInt7, at t: TimeInterval, channel: UInt4 = 0) -> RecordedEvent {
    RecordedEvent(timestamp: t, event: .cc(64, value: .midi1(value), channel: channel))
}

func isSustain(_ event: MIDIEvent, value: UInt7? = nil) -> Bool {
    guard case .cc(let payload) = event, payload.controller.number == 64 else { return false }
    if let value { return payload.value.midi1Value == value }
    return true
}

func isNoteOff(_ event: MIDIEvent, note: UInt7) -> Bool {
    guard case .noteOff(let payload) = event else { return false }
    return payload.note.number == note
}

func isNoteOn(_ event: MIDIEvent, note: UInt7) -> Bool {
    guard case .noteOn(let payload) = event else { return false }
    return payload.note.number == note
}
