import SwiftUI

@main
struct SharpViewerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 700, minHeight: 450)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 600)
    }
}
