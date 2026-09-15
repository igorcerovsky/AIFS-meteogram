import SwiftUI

@main
struct MeteogramApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 620)
                #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Meteogram") {
                Button("Refresh Forecast") {
                    NotificationCenter.default.post(name: .refreshMeteogram, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}

extension Notification.Name {
    static let refreshMeteogram = Notification.Name("refreshMeteogram")
}
