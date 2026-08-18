import AppKit

final class CronaAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var appState: CompanionAppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = CronaAppIcon.image
        appState?.windowService.initializeApplicationActivationPolicy()
        appState?.statusBarService.installIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.appState?.presentPrimarySurfaceWhenNoWindowIsActive()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            appState?.presentPrimarySurfaceWhenNoWindowIsActive()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.windowService.shutdown()
        appState?.stop()
    }
}
