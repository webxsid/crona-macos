import AppKit

final class CronaAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var appState: CompanionAppState?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appState?.windowService.showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
    }
}
