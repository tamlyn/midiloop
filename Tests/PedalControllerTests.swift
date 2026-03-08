import Foundation
import Testing
@testable import MIDILoop

@MainActor
struct PedalControllerTests {
    // MARK: - Basic events

    @Test func pedalDownEmitsDown() {
        let pedal = PedalController()
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        pedal.handleCC(number: 67, value: 127)
        #expect(events == [.down])
    }

    @Test func pedalUpEmitsUp() {
        let pedal = PedalController()
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        pedal.handleCC(number: 67, value: 127)
        events.removeAll()
        pedal.handleCC(number: 67, value: 0)

        // Should get .up immediately (quickPress comes later via timer)
        #expect(events.first == .up)
    }

    @Test func wrongCCNumberIgnored() {
        let pedal = PedalController()
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        let consumed = pedal.handleCC(number: 64, value: 127)
        #expect(!consumed)
        #expect(events.isEmpty)
    }

    @Test func configurableCCNumber() {
        let pedal = PedalController()
        pedal.controlChangeNumber = 64
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        let consumed = pedal.handleCC(number: 64, value: 127)
        #expect(consumed)
        #expect(events == [.down])
    }

    // MARK: - Threshold = 64

    @Test func valueBelow64IsRelease() {
        let pedal = PedalController()
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        pedal.handleCC(number: 67, value: 127)
        events.removeAll()
        pedal.handleCC(number: 67, value: 63)

        #expect(events.first == .up)
    }

    @Test func valueExactly64IsPress() {
        let pedal = PedalController()
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        pedal.handleCC(number: 67, value: 64)
        #expect(events == [.down])
    }

    // MARK: - Bug: quickPress after recording stop

    /// Verifies that a short pedal press (< 0.5s) emits quickPress after up.
    /// This is the sequence that caused Bug 1: if recording just stopped on .up,
    /// the subsequent .quickPress would toggle mute on the now-playing slot.
    @Test func shortPressEmitsQuickPressAfterUp() async throws {
        let pedal = PedalController()
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        pedal.handleCC(number: 67, value: 127)
        // Short hold — release before long-press threshold
        try await Task.sleep(for: .milliseconds(50))
        pedal.handleCC(number: 67, value: 0)

        // .up should be immediate
        #expect(events.contains(.up))

        // .quickPress comes after a timer delay, so wait for it
        try await Task.sleep(for: .milliseconds(600))

        #expect(events.contains(.quickPress))
        // Verify ordering: down, up, quickPress
        let downIdx = events.firstIndex(of: .down)!
        let upIdx = events.firstIndex(of: .up)!
        let quickIdx = events.firstIndex(of: .quickPress)!
        #expect(downIdx < upIdx)
        #expect(upIdx < quickIdx)
    }

    /// Verifies that a long pedal press (> 0.5s) does NOT emit quickPress.
    /// This is the normal recording scenario.
    @Test func longPressDoesNotEmitQuickPress() async throws {
        let pedal = PedalController()
        var events: [PedalEvent] = []
        pedal.onPedalEvent = { events.append($0) }

        pedal.handleCC(number: 67, value: 127)
        // Hold past the long-press threshold
        try await Task.sleep(for: .milliseconds(600))
        pedal.handleCC(number: 67, value: 0)

        // Wait for any delayed events
        try await Task.sleep(for: .milliseconds(600))

        #expect(events.contains(.down))
        #expect(events.contains(.longPress))
        #expect(events.contains(.up))
        #expect(!events.contains(.quickPress))
    }
}

extension PedalEvent: @retroactive Equatable {
    public static func == (lhs: PedalEvent, rhs: PedalEvent) -> Bool {
        switch (lhs, rhs) {
        case (.down, .down), (.up, .up), (.quickPress, .quickPress), (.longPress, .longPress):
            true
        default:
            false
        }
    }
}
