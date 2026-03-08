import SwiftUI
import MIDIKitIO

@main
struct MIDILoopApp: App {
    @State private var session = Session()
    @State private var midiService = MIDIService()
    @State private var loopEngine: LoopEngine?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(midiService)
                .environment(midiService.midi)
                .environment(loopEngine)
                .task {
                    if loopEngine == nil {
                        loopEngine = LoopEngine(session: session, midiService: midiService)
                    }
                }
        }
    }
}
