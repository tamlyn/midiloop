import SwiftUI
import MIDIKitIO

@main
struct MIDILoopApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = Session()
    @State private var midiService = MIDIService()
    @State private var pedalController = PedalController()
    @State private var loopEngine: LoopEngine?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(midiService)
                .environment(midiService.midi)
                .environment(pedalController)
                .environment(loopEngine)
                .task {
                    if loopEngine == nil {
                        loopEngine = LoopEngine(session: session, midiService: midiService, pedalController: pedalController)
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                loopEngine?.sendAllNotesOff()
            }
        }
    }
}
