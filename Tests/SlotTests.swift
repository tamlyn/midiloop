import Testing
import MIDIKitCore
@testable import MIDILoop

@MainActor
struct SlotTests {
    // MARK: - State transitions

    @Test func newSlotIsEmpty() {
        let slot = Slot(id: 0)
        #expect(slot.state == .empty)
        #expect(slot.events.isEmpty)
        #expect(slot.noteBars.isEmpty)
        #expect(slot.duration == 0)
    }

    @Test func armFromEmpty() {
        let slot = Slot(id: 0)
        slot.arm()
        #expect(slot.state == .armed)
    }

    @Test func armIgnoredWhenNotEmpty() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.arm()
        #expect(slot.state == .recording)
    }

    @Test func startRecordingFromEmpty() {
        let slot = Slot(id: 0)
        slot.startRecording()
        #expect(slot.state == .recording)
    }

    @Test func startRecordingFromArmed() {
        let slot = Slot(id: 0)
        slot.arm()
        slot.startRecording()
        #expect(slot.state == .recording)
    }

    @Test func startRecordingClearsOldEvents() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.addEvent(RecordedEvent(
            timestamp: 0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        slot.stopRecording(duration: 1.0)
        #expect(slot.state == .playing)

        // Can't start recording from .playing — clear first
        slot.clear()
        slot.startRecording()
        #expect(slot.events.isEmpty)
    }

    @Test func stopRecordingTransitionsToPlaying() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.stopRecording(duration: 2.0)
        #expect(slot.state == .playing)
        #expect(slot.duration == 2.0)
    }

    @Test func stopRecordingIgnoredWhenNotRecording() {
        let slot = Slot(id: 0)
        slot.stopRecording(duration: 1.0)
        #expect(slot.state == .empty)
    }

    @Test func toggleMutePlaying() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.stopRecording(duration: 1.0)
        #expect(slot.state == .playing)

        slot.toggleMute()
        #expect(slot.state == .muted)

        slot.toggleMute()
        #expect(slot.state == .playing)
    }

    @Test func toggleMuteIgnoredWhenEmpty() {
        let slot = Slot(id: 0)
        slot.toggleMute()
        #expect(slot.state == .empty)
    }

    @Test func clearResetsEverything() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.addEvent(RecordedEvent(
            timestamp: 0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        slot.stopRecording(duration: 2.0)
        slot.playbackPosition = 1.5

        slot.clear()
        #expect(slot.state == .empty)
        #expect(slot.events.isEmpty)
        #expect(slot.noteBars.isEmpty)
        #expect(slot.duration == 0)
        #expect(slot.playbackPosition == 0)
        #expect(slot.activeNotes.isEmpty)
    }

    // MARK: - Event recording

    @Test func addEventDuringRecording() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.addEvent(RecordedEvent(
            timestamp: 0.5,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        #expect(slot.events.count == 1)
    }

    @Test func addEventIgnoredWhenNotRecording() {
        let slot = Slot(id: 0)
        slot.addEvent(RecordedEvent(
            timestamp: 0.5,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        #expect(slot.events.isEmpty)
    }

    // MARK: - Note bar computation

    @Test func noteBarsPairedCorrectly() {
        let slot = Slot(id: 0)
        slot.startRecording()

        slot.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        slot.addEvent(RecordedEvent(
            timestamp: 0.5,
            event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))
        ))

        slot.stopRecording(duration: 1.0)

        #expect(slot.noteBars.count == 1)
        #expect(slot.noteBars[0].note == 60)
        #expect(slot.noteBars[0].startTime == 0.0)
        #expect(slot.noteBars[0].endTime == 0.5)
    }

    @Test func unclosedNoteClosesAtLoopEnd() {
        let slot = Slot(id: 0)
        slot.startRecording()

        slot.addEvent(RecordedEvent(
            timestamp: 0.8,
            event: .noteOn(MIDIEvent.NoteOn(note: 64, velocity: .midi1(80), channel: 0))
        ))
        // No note-off

        slot.stopRecording(duration: 1.0)

        #expect(slot.noteBars.count == 1)
        #expect(slot.noteBars[0].startTime == 0.8)
        #expect(slot.noteBars[0].endTime == 1.0)
    }

    @Test func multipleNoteBars() {
        let slot = Slot(id: 0)
        slot.startRecording()

        // Two notes, one after the other
        slot.addEvent(RecordedEvent(timestamp: 0.0, event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))))
        slot.addEvent(RecordedEvent(timestamp: 0.3, event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))))
        slot.addEvent(RecordedEvent(timestamp: 0.5, event: .noteOn(MIDIEvent.NoteOn(note: 64, velocity: .midi1(90), channel: 0))))
        slot.addEvent(RecordedEvent(timestamp: 0.8, event: .noteOff(MIDIEvent.NoteOff(note: 64, velocity: .midi1(0), channel: 0))))

        slot.stopRecording(duration: 1.0)

        #expect(slot.noteBars.count == 2)
    }

    // MARK: - Active note tracking

    @Test func trackActiveNotes() {
        let slot = Slot(id: 0)
        slot.trackNoteOn(note: 60, channel: 0)
        #expect(slot.activeNotes.count == 1)

        slot.trackNoteOff(note: 60, channel: 0)
        #expect(slot.activeNotes.isEmpty)
    }

    @Test func clearActiveNotes() {
        let slot = Slot(id: 0)
        slot.trackNoteOn(note: 60, channel: 0)
        slot.trackNoteOn(note: 64, channel: 0)
        slot.clearActiveNotes()
        #expect(slot.activeNotes.isEmpty)
    }
}
