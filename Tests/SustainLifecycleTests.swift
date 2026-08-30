import Testing
import MIDIKitCore
import QuartzCore
@testable import MIDILoop

/// Notes or sustain pedal held across recording boundaries must not leave the
/// loop permanently sustaining, and every path that cuts playback must also
/// release the sustain pedal.
@Suite(.serialized)
@MainActor
struct SustainLifecycleTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "noteQuantisation")
        UserDefaults.standard.removeObject(forKey: "pedalCC")
    }

    // MARK: - Closing open notes/sustain at recording stop

    @Test func stopRecordingClosesHeldNote() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.addEvent(noteOn(60, at: 0.5))
        // Key still held when recording stops — no note-off recorded
        slot.stopRecording(duration: 2.0)

        #expect(slot.events.count == 2)
        let closing = slot.events.last!
        #expect(isNoteOff(closing.event, note: 60))
        #expect(closing.timestamp == 2.0)
    }

    @Test func stopRecordingClosesHeldSustain() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.addEvent(sustain(127, at: 0.2))
        slot.addEvent(noteOn(60, at: 0.5))
        slot.addEvent(noteOff(60, at: 1.0))
        // Pedal still down when recording stops
        slot.stopRecording(duration: 2.0)

        #expect(slot.events.count == 4)
        let closing = slot.events.last!
        #expect(isSustain(closing.event, value: 0))
        #expect(closing.timestamp == 2.0)
    }

    @Test func stopRecordingLeavesClosedNotesAndSustainAlone() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.addEvent(sustain(127, at: 0.2))
        slot.addEvent(noteOn(60, at: 0.5))
        slot.addEvent(noteOff(60, at: 1.0))
        slot.addEvent(sustain(0, at: 1.5))
        slot.stopRecording(duration: 2.0)

        #expect(slot.events.count == 4)
    }

    @Test func stopRecordingTrimsEventsPastDuration() {
        let slot = Slot(id: 0)
        slot.startRecording()
        slot.addEvent(noteOn(60, at: 0.5))
        slot.addEvent(noteOff(60, at: 2.5))
        slot.addEvent(noteOn(64, at: 2.2))
        slot.addEvent(noteOff(64, at: 2.8))
        // Duration snapped down below the last recorded events
        slot.stopRecording(duration: 2.0)

        #expect(slot.events.allSatisfy { $0.timestamp <= 2.0 })
        // Note 64 started after the cut — gone entirely
        #expect(!slot.events.contains { isNoteOn($0.event, note: 64) || isNoteOff($0.event, note: 64) })
        // Note 60's off was trimmed, so it closes at the loop end instead
        #expect(slot.events.contains { isNoteOff($0.event, note: 60) && $0.timestamp == 2.0 })
    }

    // MARK: - Capturing sustain already held at recording start

    @Test func sustainHeldBeforeFirstRecordingIsCaptured() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        // Player presses sustain, then arms and plays the first note
        engine.handleIncomingEvent(.cc(64, value: .midi1(127), channel: 0))
        engine.startRecording()
        engine.handleIncomingEvent(.noteOn(60, velocity: .midi1(100), channel: 0))

        let slot = session.slots[0]
        #expect(slot.state == .recording)
        #expect(isSustain(slot.events[0].event, value: 127))
        #expect(slot.events[0].timestamp == 0.0)
        #expect(slot.events.contains { isNoteOn($0.event, note: 60) })
    }

    @Test func sustainReleasedBeforeRecordingIsNotCaptured() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        engine.handleIncomingEvent(.cc(64, value: .midi1(127), channel: 0))
        engine.handleIncomingEvent(.cc(64, value: .midi1(0), channel: 0))
        engine.startRecording()
        engine.handleIncomingEvent(.noteOn(60, velocity: .midi1(100), channel: 0))

        let slot = session.slots[0]
        #expect(!slot.events.contains { isSustain($0.event) })
    }

    @Test func sustainHeldAtBoundaryTransitionIsCaptured() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        // Pedal goes down while slot 0 plays, then slot 1 arms and the
        // boundary transition starts its recording
        engine.handleIncomingEvent(.cc(64, value: .midi1(127), channel: 0))
        session.selectSlot(1)
        session.selectedSlot.arm()
        engine.transitionArmedSlots(boundaryTime: CACurrentMediaTime())

        let slot1 = session.slots[1]
        #expect(slot1.state == .recording)
        #expect(slot1.events.contains { isSustain($0.event, value: 127) && $0.timestamp == 0.0 })
    }

    // MARK: - Sustain-off on cut paths

    @Test func muteReleasesSustain() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        let slot = session.slots[0]
        slot.trackNoteOn(note: 60, channel: 0)
        slot.trackSustain(channel: 0, down: true)

        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }
        engine.toggleMute(slot: slot)

        #expect(slot.state == .muted)
        #expect(sent.contains { isNoteOff($0, note: 60) })
        #expect(sent.contains { isSustain($0, value: 0) })
        #expect(slot.activeNotes.isEmpty)
        #expect(slot.sustainChannels.isEmpty)
    }

    @Test func clearReleasesSustain() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            noteOn(60, at: 0.0), noteOff(60, at: 0.5),
        ], rawDuration: 4.0)

        let slot = session.slots[0]
        slot.trackSustain(channel: 0, down: true)

        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }
        engine.clearSlot(slot)

        #expect(sent.contains { isSustain($0, value: 0) })
    }

    @Test func sendAllNotesOffReleasesSustainOnAllChannels() {
        let midi = MIDIService()
        var sent: [MIDIEvent] = []
        midi.sendMonitor = { sent.append(contentsOf: $0) }

        midi.sendAllNotesOff()

        let sustainOffs = sent.filter { isSustain($0, value: 0) }
        #expect(sustainOffs.count == 16)
    }

    // MARK: - Playback sustain tracking

    @Test func playedSustainIsTrackedOnSlot() {
        let session = Session()
        let midi = MIDIService()
        let engine = LoopEngine(session: session, midiService: midi, pedalController: PedalController())
        defer { engine.stop() }

        recordClip(engine: engine, session: session, slotIndex: 0, events: [
            sustain(127, at: 0.1),
            noteOn(60, at: 0.2), noteOff(60, at: 0.5),
            sustain(0, at: 1.0),
        ], rawDuration: 4.0)

        let slot = session.slots[0]
        engine.tick(now: engine.playbackStartTime + 4.3)
        #expect(slot.sustainChannels == [0])

        engine.tick(now: engine.playbackStartTime + 5.1)
        #expect(slot.sustainChannels.isEmpty)
    }
}
