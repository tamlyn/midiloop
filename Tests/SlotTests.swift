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

    // MARK: - Accept transfer (drag-to-move)

    @Test func acceptTransferCopiesStateFromSource() {
        let source = Slot(id: 0)
        source.startRecording()
        source.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        source.addEvent(RecordedEvent(
            timestamp: 0.5,
            event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))
        ))
        source.stopRecording(duration: 1.0)

        let target = Slot(id: 1)
        target.acceptTransfer(from: source)

        #expect(target.events.count == 2)
        #expect(target.duration == 1.0)
        #expect(target.state == .playing)
    }

    @Test func acceptTransferFromMutedSlotStaysMuted() {
        let source = Slot(id: 0)
        source.startRecording()
        source.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        source.stopRecording(duration: 1.0)
        source.toggleMute()
        #expect(source.state == .muted)

        let target = Slot(id: 1)
        target.acceptTransfer(from: source)

        #expect(target.state == .muted)
        #expect(target.events.count == 1)
        #expect(target.duration == 1.0)
    }

    // MARK: - Loop events

    @Test func loopEventsRepeatsToFillDuration() {
        let events = [
            RecordedEvent(
                timestamp: 0.0,
                event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
            ),
            RecordedEvent(
                timestamp: 0.5,
                event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))
            ),
        ]

        let looped = Slot.loopEvents(events, originalDuration: 1.0, targetDuration: 3.0)

        // 3 repetitions: 0-1s, 1-2s, 2-3s
        #expect(looped.count == 6)
        #expect(looped[0].timestamp == 0.0)
        #expect(looped[1].timestamp == 0.5)
        #expect(looped[2].timestamp == 1.0)
        #expect(looped[3].timestamp == 1.5)
        #expect(looped[4].timestamp == 2.0)
        #expect(looped[5].timestamp == 2.5)
    }

    @Test func loopEventsExcludesEventsAtOrPastTarget() {
        let events = [
            RecordedEvent(
                timestamp: 0.0,
                event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
            ),
            RecordedEvent(
                timestamp: 0.9,
                event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))
            ),
        ]

        let looped = Slot.loopEvents(events, originalDuration: 1.0, targetDuration: 1.5)

        // Rep 0: 0.0, 0.9; Rep 1: 1.0 (ok), 1.9 (>=1.5, excluded)
        #expect(looped.count == 3)
        #expect(looped[2].timestamp == 1.0)
    }

    @Test func loopEventsPreservesTakeIndex() {
        let events = [
            RecordedEvent(
                timestamp: 0.0,
                colourIndex: 3,
                event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
            ),
        ]

        let looped = Slot.loopEvents(events, originalDuration: 1.0, targetDuration: 2.0)

        #expect(looped.count == 2)
        #expect(looped[0].colourIndex == 3)
        #expect(looped[1].colourIndex == 3)
    }

    @Test func loopEventsWithZeroDurationReturnsOriginal() {
        let events = [
            RecordedEvent(
                timestamp: 0.0,
                event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
            ),
        ]

        let looped = Slot.loopEvents(events, originalDuration: 0.0, targetDuration: 2.0)
        #expect(looped.count == 1)
    }

    // MARK: - Merge events

    @Test func mergeEventsCombinesTwoSlots() {
        let slot1 = Slot(id: 0)
        slot1.startRecording()
        slot1.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        slot1.addEvent(RecordedEvent(
            timestamp: 0.5,
            event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))
        ))
        slot1.stopRecording(duration: 1.0)

        let slot2 = Slot(id: 1)
        slot2.startRecording()
        slot2.addEvent(RecordedEvent(
            timestamp: 0.2,
            event: .noteOn(MIDIEvent.NoteOn(note: 64, velocity: .midi1(100), channel: 0))
        ))
        slot2.addEvent(RecordedEvent(
            timestamp: 0.7,
            event: .noteOff(MIDIEvent.NoteOff(note: 64, velocity: .midi1(0), channel: 0))
        ))
        slot2.stopRecording(duration: 1.0)

        slot1.mergeEvents(from: slot2)

        #expect(slot1.events.count == 4)
        #expect(slot1.duration == 1.0)
        // Events should be sorted by timestamp
        for i in 1..<slot1.events.count {
            #expect(slot1.events[i].timestamp >= slot1.events[i - 1].timestamp)
        }
    }

    @Test func mergeEventsLoopsShorterSlot() {
        let long = Slot(id: 0)
        long.startRecording()
        long.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        long.addEvent(RecordedEvent(
            timestamp: 1.5,
            event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))
        ))
        long.stopRecording(duration: 2.0)

        let short = Slot(id: 1)
        short.startRecording()
        short.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 64, velocity: .midi1(100), channel: 0))
        ))
        short.addEvent(RecordedEvent(
            timestamp: 0.5,
            event: .noteOff(MIDIEvent.NoteOff(note: 64, velocity: .midi1(0), channel: 0))
        ))
        short.stopRecording(duration: 1.0)

        long.mergeEvents(from: short)

        #expect(long.duration == 2.0)
        // Long had 2 events, short looped to 2.0s = 2 reps of 2 events = 4, total = 6
        #expect(long.events.count == 6)
    }

    @Test func mergeEventsExpandsShorterTarget() {
        let short = Slot(id: 0)
        short.startRecording()
        short.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 60, velocity: .midi1(100), channel: 0))
        ))
        short.addEvent(RecordedEvent(
            timestamp: 0.5,
            event: .noteOff(MIDIEvent.NoteOff(note: 60, velocity: .midi1(0), channel: 0))
        ))
        short.stopRecording(duration: 1.0)

        let long = Slot(id: 1)
        long.startRecording()
        long.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(MIDIEvent.NoteOn(note: 64, velocity: .midi1(100), channel: 0))
        ))
        long.addEvent(RecordedEvent(
            timestamp: 1.5,
            event: .noteOff(MIDIEvent.NoteOff(note: 64, velocity: .midi1(0), channel: 0))
        ))
        long.stopRecording(duration: 2.0)

        // Merging a longer source into a shorter target should expand the target
        short.mergeEvents(from: long)

        #expect(short.duration == 2.0)
        // Short looped to 2.0s = 2 reps of 2 events = 4, plus long's 2 events = 6
        #expect(short.events.count == 6)
    }

    // MARK: - Snapshot and restore

    @Test func snapshotAndRestorePreservesState() {
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

        let snapshot = slot.snapshot()

        // Modify the slot
        slot.clear()
        #expect(slot.state == .empty)

        // Restore
        slot.restore(from: snapshot)
        #expect(slot.state == .playing)
        #expect(slot.events.count == 2)
        #expect(slot.duration == 1.0)
        #expect(slot.activeNotes.isEmpty)
    }
}
