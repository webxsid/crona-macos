import SwiftUI

@main
struct CronaCompanionApp: App {
    @NSApplicationDelegateAdaptor(CronaAppDelegate.self) private var appDelegate
    private let appState: CompanionAppState

    init() {
        let appState = CompanionAppState()
        self.appState = appState
        appDelegate.appState = appState
        NSApp.setActivationPolicy(.accessory)
        appState.start()
    }

    var body: some Scene {
        Settings {
            SettingsRootView(appState: appState)
                .frame(minWidth: 620, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
