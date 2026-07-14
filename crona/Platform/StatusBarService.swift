import AppKit
import SwiftUI

@MainActor
final class StatusBarService: NSObject, NSPopoverDelegate {
    private weak var appState: CompanionAppState?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var monitor: Any?
    private var lastRenderedTitle = ""
    private var lastRenderedSymbolName = ""
    private var pendingUpdate = false

    func configure(appState: CompanionAppState) {
        self.appState = appState
    }

    func installIfNeeded() {
        guard let button = statusItem.button, let appState else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 620)
        popover.contentViewController = NSHostingController(rootView: PopoverRootView(appState: appState))
        updateStatusItem()
    }

    func updateStatusItem() {
        guard !pendingUpdate else { return }
        pendingUpdate = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingUpdate = false
            self.applyStatusItemUpdate()
        }
    }

    private func applyStatusItemUpdate() {
        guard let button = statusItem.button, let appState else { return }
        let model = appState.popoverModel
        let nextTitle = MenuBarTextFormatter.statusItemTitle(
            preferences: appState.preferences.preferences,
            connectionState: model.connectionState,
            timerSnapshot: model.timerSnapshot
        )
        let nextSymbolName = model.statusSymbolName

        if lastRenderedSymbolName != nextSymbolName {
            button.image = NSImage(systemSymbolName: nextSymbolName, accessibilityDescription: "Crona")
            lastRenderedSymbolName = nextSymbolName
        }

        if lastRenderedTitle != nextTitle {
            button.title = nextTitle
            lastRenderedTitle = nextTitle
        }
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let appState else { return }
        if let hostingController = popover.contentViewController as? NSHostingController<PopoverRootView> {
            hostingController.rootView = PopoverRootView(appState: appState)
        } else {
            popover.contentViewController = NSHostingController(rootView: PopoverRootView(appState: appState))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        startEventMonitor()
    }

    private func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }

    private func startEventMonitor() {
        stopEventMonitor()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover(nil)
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopEventMonitor()
    }
}
