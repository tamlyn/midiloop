import SwiftUI

@main
struct MIDILoopApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}
