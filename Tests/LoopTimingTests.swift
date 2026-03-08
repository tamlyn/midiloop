import Testing
import MIDIKitCore
import QuartzCore
@testable import MIDILoop

@MainActor
struct LoopTimingTests {
    // MARK: - Armed state transitions

    @Test func armFromEmptyWhenMasterExists() {
        let slot = Slot(id: 0)
        slot.arm()
        #expect(slot.state == .armed)
    }

    @Test func armedToRecording() {
        let slot = Slot(id: 0)
        slot.arm()
        slot.startRecording()
        #expect(slot.state == .recording)
    }

    @Test func armedToClearOnCancel() {
        let slot = Slot(id: 0)
        slot.arm()
        slot.clear()
        #expect(slot.state == .empty)
    }

    @Test func armedSlotHasNoEvents() {
        let slot = Slot(id: 0)
        slot.arm()
        #expect(slot.events.isEmpty)
        #expect(slot.noteBars.isEmpty)
    }

    // MARK: - Power-of-2 quantisation

    @Test func quantiseDurationSnapsToPowerOf2() {
        let session = Session()
        session.setMasterLoopDuration(4.0)

        // ~3s should snap to 1x (4.0), not 0.75x
        #expect(session.quantisedDuration(for: 3.0) == 4.0)

        // ~5s should snap to 1x (4.0), not 1.25x
        #expect(session.quantisedDuration(for: 5.0) == 4.0)

        // ~6s should snap to 2x (8.0), not 1.5x
        #expect(session.quantisedDuration(for: 6.0) == 8.0)

        // ~3s with 2.0 master: snap to 1x (2.0)
        let session2 = Session()
        session2.setMasterLoopDuration(2.0)
        #expect(session2.quantisedDuration(for: 3.0) == 4.0)
    }

    @Test func quantiseDurationNeverSnapsToLinearMultiples() {
        let session = Session()
        session.setMasterLoopDuration(2.0)

        // 5s should NOT snap to 3x (6.0) — should snap to 2x (4.0) or 4x (8.0)
        let result = session.quantisedDuration(for: 5.0)
        #expect(result == 4.0 || result == 8.0)
        #expect(result != 6.0)

        // 7s should snap to 4x (8.0), NOT 3x (6.0) or 3.5x
        let result2 = session.quantisedDuration(for: 7.0)
        #expect(result2 == 8.0)
    }

    @Test func quantiseDurationAllowsHalves() {
        let session = Session()
        session.setMasterLoopDuration(4.0)

        // 1.5s should snap to 0.5x (2.0)
        #expect(session.quantisedDuration(for: 1.5) == 2.0)

        // 2.0 exactly = 0.5x
        #expect(session.quantisedDuration(for: 2.0) == 2.0)
    }

    @Test func quantiseDurationMinimumIsQuarter() {
        let session = Session()
        session.setMasterLoopDuration(4.0)

        // Very short: should clamp to 0.25x (1.0)
        #expect(session.quantisedDuration(for: 0.3) == 1.0)
        #expect(session.quantisedDuration(for: 0.01) == 1.0)
    }

    // MARK: - Bug 2: Subsequent loop should not be shorter

    /// When recording a loop that's slightly shorter than the master,
    /// it should snap to 1x, not 0.5x.
    @Test func recordingSlightlyShorterThanMasterSnapsTo1x() {
        let session = Session()
        session.setMasterLoopDuration(4.0)

        // User records for 3.5s — should snap to 1x (4.0), not 0.5x (2.0)
        let duration = session.quantisedDuration(for: 3.5)
        #expect(duration == 4.0)
    }

    /// When recording starts at the loop boundary and the user holds
    /// for almost exactly 1 loop, it should snap to 1x.
    @Test func recordingAlmostExactlyOneMasterLoopSnapsTo1x() {
        let session = Session()
        session.setMasterLoopDuration(4.0)

        // 3.8s ≈ 0.95x — should snap to 1x (4.0)
        #expect(session.quantisedDuration(for: 3.8) == 4.0)

        // 4.2s ≈ 1.05x — should snap to 1x (4.0)
        #expect(session.quantisedDuration(for: 4.2) == 4.0)
    }

    // MARK: - Playback phase alignment

    /// A slot recorded at an odd master boundary must have a playback offset
    /// so its events align with the playback cycle. Without the offset,
    /// events fire at the wrong position within the slot's loop.
    @Test func subsequentSlotPlaybackOffset() {
        let session = Session()
        let midiService = MIDIService()
        let engine = LoopEngine(session: session, midiService: midiService)
        defer { engine.stop() }

        let masterDuration: TimeInterval = 4.0

        // Set up state as if first loop has been recorded
        session.setMasterLoopDuration(masterDuration)
        let now = CACurrentMediaTime()
        engine.playbackStartTime = now - 12.0

        // Record slot 1 starting at boundary 1 (elapsed = 4s from playbackStart)
        session.selectSlot(1)
        let slot1 = session.selectedSlot
        slot1.startRecording()
        // Started 8s ago = playbackStart + 4s (one master boundary)
        engine.recordingStartTime = now - 8.0

        slot1.addEvent(RecordedEvent(
            timestamp: 0.0,
            event: .noteOn(60, velocity: .midi1(64), channel: 0)
        ))
        slot1.addEvent(RecordedEvent(
            timestamp: 1.0,
            event: .noteOff(60, velocity: .midi1(0), channel: 0)
        ))

        // Stop recording — rawDuration will be ~8s, quantised to 2x master
        engine.toggleRecording()

        #expect(slot1.state == .playing)
        #expect(slot1.duration == 8.0)

        // Offset should be ~4.0 (one master boundary from playbackStart)
        let offset = engine.slotPlaybackOffsets[1]
        #expect(offset > 3.5 && offset < 4.5)
    }
}
