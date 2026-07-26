import AppKit
import SwiftUI

enum StatusPopupSizing {
    static let minimumHeight: CGFloat = 180
    static let maximumHeight: CGFloat = 700

    static func resolvedHeight(for measuredHeight: CGFloat) -> CGFloat {
        min(maximumHeight, max(minimumHeight, ceil(measuredHeight)))
    }
}

enum StatusItemClickIntent: Equatable {
    case togglePopup
    case showContextMenu

    static func resolve(eventType: NSEvent.EventType?) -> Self {
        eventType == .rightMouseUp ? .showContextMenu : .togglePopup
    }
}

@MainActor
final class StatusBarService: NSObject {
    private weak var appState: CompanionAppState?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popupPanel: StatusPopupPanel?
    private var hostingController: NSHostingController<PopoverRootView>?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var lastRenderedTitle = ""
    private var lastRenderedDisplayMode: MenuBarDisplayMode?
    private var pendingUpdate = false
    private var animationGeneration = 0
    private lazy var contextMenu = makeContextMenu()

    func configure(appState: CompanionAppState) {
        self.appState = appState
    }

    func installIfNeeded() {
        guard let button = statusItem.button, let appState else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        makePopupPanel(appState: appState)
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

    func refreshPopupLayout() {
        guard let panel = popupPanel, panel.isVisible else { return }
        resizePanelToFit(panel, animated: true)
    }

    func dismissPopup(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let panel = popupPanel, panel.isVisible else {
            completion?()
            return
        }

        animationGeneration &+= 1
        let generation = animationGeneration
        stopDismissalMonitoring()
        panel.makeFirstResponder(nil)

        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            completion?()
            return
        }

        let restingFrame = panel.frame
        var dismissedFrame = restingFrame
        dismissedFrame.origin.y += 8

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(dismissedFrame, display: true)
        }

        Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self, let panel, generation == self.animationGeneration else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.setFrame(restingFrame, display: false)
            completion?()
        }
    }

    func showPopupFromNotification() {
        guard popupPanel?.isVisible != true else { return }
        showPopup()
    }

    private func applyStatusItemUpdate() {
        guard let button = statusItem.button, let appState else { return }
        let model = appState.popoverModel
        let nextTitle = MenuBarTextFormatter.statusItemTitle(
            preferences: appState.preferences.preferences,
            connectionState: model.connectionState,
            timerSnapshot: model.timerSnapshot,
            todayWorkedSeconds: appState.popoverStatsService.todayWorkedSeconds
        )
        let displayMode = appState.preferences.preferences.menuBarDisplayMode

        if lastRenderedDisplayMode != displayMode {
            button.image = displayMode.showsIcon ? Self.statusItemIcon() : nil
            switch displayMode {
            case .iconOnly:
                button.imagePosition = .imageOnly
            case .textOnly:
                button.imagePosition = .noImage
            case .iconAndText:
                button.imagePosition = .imageLeading
            }
            lastRenderedDisplayMode = displayMode
        }

        if lastRenderedTitle != nextTitle {
            button.title = nextTitle
            lastRenderedTitle = nextTitle
        }
    }

    private static func statusItemIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size, flipped: false) { rect in
            CronaAppIcon.image.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        icon.isTemplate = false
        icon.accessibilityDescription = "Crona"
        return icon
    }

    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        switch StatusItemClickIntent.resolve(eventType: NSApp.currentEvent?.type) {
        case .togglePopup:
            togglePopup()
        case .showContextMenu:
            showContextMenuFromStatusItem()
        }
    }

    private func togglePopup() {
        guard let panel = popupPanel else { return }
        if panel.isVisible {
            dismissPopup()
        } else {
            showPopup()
        }
    }

    private func showContextMenuFromStatusItem() {
        guard let button = statusItem.button else { return }
        dismissPopup(animated: false)
        let location = NSPoint(x: button.bounds.midX, y: button.bounds.minY - 4)
        contextMenu.popUp(positioning: nil, at: location, in: button)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Crona")
        menu.autoenablesItems = false
        menu.addItem(menuItem("About Crona", action: #selector(openAbout)))
        menu.addItem(.separator())

        let settings = menuItem("Settings…", action: #selector(openSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)
        menu.addItem(.separator())

        menu.addItem(menuItem("Documentation", action: #selector(openDocumentation)))
        menu.addItem(menuItem("GitHub", action: #selector(openGitHub)))
        menu.addItem(menuItem("Support", action: #selector(openSupport)))
        menu.addItem(.separator())

        let stop = menuItem("Stop Crona…", action: #selector(stopCrona))
        stop.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
        menu.addItem(stop)

        let quit = menuItem("Quit Crona", action: #selector(quitCrona))
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        return menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func openAbout() {
        appState?.openAbout()
    }

    @objc private func openSettings() {
        appState?.openSettings()
    }

    @objc private func openDocumentation() {
        appState?.openDocumentation()
    }

    @objc private func openGitHub() {
        appState?.openGitHub()
    }

    @objc private func openSupport() {
        appState?.openSupport()
    }

    @objc private func stopCrona() {
        appState?.requestStopCrona()
    }

    @objc private func quitCrona() {
        appState?.quitCrona()
    }

    private func showPopup() {
        guard let panel = popupPanel, let button = statusItem.button else { return }
        animationGeneration &+= 1
        let generation = animationGeneration

        resizePanelToFit(panel, animated: false)
        let restingOrigin = Self.popupOrigin(
            iconRect: statusIconScreenRect(for: button),
            menuBarBottomY: button.window?.frame.minY ?? button.window?.screen?.visibleFrame.maxY ?? 0,
            panelSize: panel.frame.size,
            visibleFrame: button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        )
        var openingOrigin = restingOrigin
        openingOrigin.y += 8

        panel.alphaValue = 0
        panel.setFrameOrigin(openingOrigin)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        startDismissalMonitoring()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(restingOrigin)
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, generation == self.animationGeneration else { return }
            self.popupPanel?.alphaValue = 1
        }
    }

    private func makePopupPanel(appState: CompanionAppState) {
        guard popupPanel == nil else { return }

        let controller = NSHostingController(rootView: PopoverRootView(appState: appState))
        let panel = StatusPopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = controller
        panel.onCancel = { [weak self] in
            self?.dismissPopup()
        }

        hostingController = controller
        popupPanel = panel
        resizePanelToFit(panel, animated: false)
    }

    private func resizePanelToFit(_ panel: NSPanel, animated: Bool) {
        guard let hostingController else { return }
        let measured = hostingController.sizeThatFits(
            in: NSSize(width: 420, height: 800)
        )
        let height = StatusPopupSizing.resolvedHeight(for: measured.height)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: 420, height: height)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func statusIconScreenRect(for button: NSStatusBarButton) -> NSRect {
        guard let window = button.window else { return .zero }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds)
            ?? NSRect(x: button.bounds.minX, y: button.bounds.minY, width: 22, height: button.bounds.height)
        let windowRect = button.convert(imageRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    static func popupOrigin(
        iconRect: NSRect,
        menuBarBottomY: CGFloat,
        panelSize: NSSize,
        visibleFrame: NSRect,
        gap: CGFloat = 12,
        edgeInset: CGFloat = 8
    ) -> NSPoint {
        let unclampedX = iconRect.midX - panelSize.width / 2
        let minimumX = visibleFrame.minX + edgeInset
        let maximumX = visibleFrame.maxX - panelSize.width - edgeInset
        let x = min(maximumX, max(minimumX, unclampedX))
        let y = menuBarBottomY - panelSize.height - gap
        return NSPoint(x: x, y: max(visibleFrame.minY + edgeInset, y))
    }

    private func startDismissalMonitoring() {
        stopDismissalMonitoring()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissPopup()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.popupPanel else { return event }
            let statusWindow = self.statusItem.button?.window
            if event.window !== panel, event.window !== statusWindow {
                self.dismissPopup()
            }
            return event
        }

        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissPopup()
            }
        }
    }

    private func stopDismissalMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
    }
}

private final class StatusPopupPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
