import SwiftUI

@main
struct CronaCompanionApp: App {
    @NSApplicationDelegateAdaptor(CronaAppDelegate.self) private var appDelegate
    private let appState: CompanionAppState

    init() {
        let appState = CompanionAppState()
        self.appState = appState
        appDelegate.appState = appState
        NSApp.applicationIconImage = CronaAppIcon.image
        NSApp.setActivationPolicy(.accessory)
        appState.start()
    }

    var body: some Scene {
        Settings {
            SettingsRootView(appState: appState)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 900, height: 680)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
