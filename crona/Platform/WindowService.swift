import AppKit
import SwiftUI

@MainActor
final class WindowService {
    private weak var appState: CompanionAppState?

    func configure(appState: CompanionAppState) {
        self.appState = appState
    }

    func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openTUI(using command: String) {
        let sanitized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", sanitized]
        do {
            try process.run()
        } catch {
            appState?.daemonConnection.lastErrorDescription = "Failed to open TUI: \(error.localizedDescription)"
        }
    }
}
