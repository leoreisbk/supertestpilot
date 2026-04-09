import SwiftUI

@main
struct TestPilotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 760, height: 540)
        .windowResizability(.contentMinSize)
    }
}
