import AppKit
import SwiftUI

@MainActor
final class WindowService {
    private weak var appState: CompanionAppState?
    private weak var settingsWindow: NSWindow?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var hardLimitPanel: HardLimitPanel?
    private var hardLimitWarningPanel: HardLimitWarningPanel?
    private var hardLimitWarningGlobalMonitor: Any?
    private var hardLimitWarningLocalMonitor: Any?

    func configure(appState: CompanionAppState) {
        self.appState = appState
    }

    func showSettings() {
        presentAsRegularApplication()
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func registerSettingsWindow(_ window: NSWindow) {
        guard settingsWindow !== window else { return }
        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
        }

        settingsWindow = window
        window.title = "Crona"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.contentMinSize = NSSize(width: 860, height: 620)
        if window.contentLayoutRect.width < 860 || window.contentLayoutRect.height < 620 {
            window.setContentSize(NSSize(width: 900, height: 680))
            window.center()
        }
        window.isReleasedWhenClosed = false
        presentAsRegularApplication()

        settingsWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self, weak window] in
                guard let self, self.settingsWindow === window else { return }
                self.settingsWindow = nil
                if let settingsWindowCloseObserver = self.settingsWindowCloseObserver {
                    NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
                    self.settingsWindowCloseObserver = nil
                }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func presentAsRegularApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = CronaAppIcon.image
        NSApp.unhide(nil)

        // AppKit rebuilds the Dock tile asynchronously when an accessory app
        // transitions to a regular app. Reapply the icon after that transition.
        Task { @MainActor in
            await Task.yield()
            NSApp.applicationIconImage = CronaAppIcon.image
            NSApp.dockTile.display()
            NSApp.activate(ignoringOtherApps: true)
        }
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

    func activateAppForPopup() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func showHardLimitPopup() {
        guard let appState else { return }

        let panel: HardLimitPanel
        if let existingPanel = hardLimitPanel, existingPanel.isVisible {
            panel = existingPanel
        } else {
            destroyHardLimitPanel()
            panel = makeHardLimitPanel(appState: appState)
            hardLimitPanel = panel
        }

        activateAppForPopup()
        let targetScreen = popupTargetScreen()
        position(panel: panel, on: targetScreen)

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        animatePopupEntrance(panel)
    }

    func updateHardLimitPopup() {
        guard let panel = hardLimitPanel else { return }
        let targetScreen = popupTargetScreen()
        position(panel: panel, on: targetScreen)
    }

    func closeHardLimitPopup() {
        destroyHardLimitPanel()
    }

    func showHardLimitWarningIndicator() {
        guard let appState else { return }

        let panel: HardLimitWarningPanel
        if let existingPanel = hardLimitWarningPanel {
            panel = existingPanel
            if let hostingController = panel.contentViewController as? NSHostingController<HardLimitWarningIndicatorRootView> {
                hostingController.rootView = HardLimitWarningIndicatorRootView(appState: appState)
            } else {
                panel.contentViewController = makeHardLimitWarningHostingController(
                    appState: appState
                )
            }
        } else {
            panel = makeHardLimitWarningPanel(appState: appState)
            hardLimitWarningPanel = panel
        }

        installHardLimitWarningMonitorsIfNeeded()
        positionWarning(panel: panel)
        panel.orderFrontRegardless()
        panel.alphaValue = 1
    }

    func closeHardLimitWarningIndicator() {
        hardLimitWarningPanel?.orderOut(nil)
        removeHardLimitWarningMonitors()
    }

    private func makeHardLimitPanel(appState: CompanionAppState) -> HardLimitPanel {
        let panel = HardLimitPanel(
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 420),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.worksWhenModal = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: HardLimitPopupRootView(appState: appState))
        return panel
    }

    private func destroyHardLimitPanel() {
        guard let panel = hardLimitPanel else { return }
        panel.makeFirstResponder(nil)
        panel.resignKey()
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.close()
        hardLimitPanel = nil
    }

    private func makeHardLimitWarningPanel(appState: CompanionAppState) -> HardLimitWarningPanel {
        let panel = HardLimitWarningPanel(
            contentRect: NSRect(x: 0, y: 0, width: 190, height: 54),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = makeHardLimitWarningHostingController(
            appState: appState
        )
        return panel
    }

    private func makeHardLimitWarningHostingController(
        appState: CompanionAppState
    ) -> NSHostingController<HardLimitWarningIndicatorRootView> {
        let controller = NSHostingController(
            rootView: HardLimitWarningIndicatorRootView(appState: appState)
        )
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        return controller
    }

    private func popupTargetScreen() -> NSScreen {
        if let mainScreen = NSScreen.main {
            return mainScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.screens.first!
    }

    private func position(panel: NSWindow, on screen: NSScreen) {
        let targetFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: targetFrame.midX - (panelSize.width / 2),
            y: targetFrame.midY - (panelSize.height / 2)
        )
        panel.setFrameOrigin(origin)
    }

    private func positionWarning(panel: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? popupTargetScreen()
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let offsetX: CGFloat = 18
        let offsetY: CGFloat = 18

        let originX = min(
            max(visibleFrame.minX + 12, mouseLocation.x + offsetX),
            visibleFrame.maxX - panelSize.width - 12
        )
        let originY = min(
            max(visibleFrame.minY + 12, mouseLocation.y - panelSize.height - offsetY),
            visibleFrame.maxY - panelSize.height - 12
        )

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func animatePopupEntrance(_ panel: NSPanel) {
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func installHardLimitWarningMonitorsIfNeeded() {
        guard hardLimitWarningGlobalMonitor == nil, hardLimitWarningLocalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        hardLimitWarningGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.hardLimitWarningPanel, panel.isVisible else { return }
                self.positionWarning(panel: panel)
            }
        }

        hardLimitWarningLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, let panel = self.hardLimitWarningPanel, panel.isVisible else { return event }
            self.positionWarning(panel: panel)
            return event
        }
    }

    private func removeHardLimitWarningMonitors() {
        if let hardLimitWarningGlobalMonitor {
            NSEvent.removeMonitor(hardLimitWarningGlobalMonitor)
            self.hardLimitWarningGlobalMonitor = nil
        }
        if let hardLimitWarningLocalMonitor {
            NSEvent.removeMonitor(hardLimitWarningLocalMonitor)
            self.hardLimitWarningLocalMonitor = nil
        }
    }
}

private final class HardLimitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class HardLimitWarningPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
