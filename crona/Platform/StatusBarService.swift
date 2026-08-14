import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class PopupDisplayClock: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?
    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

enum StatusPopupSizing {
    static let width: CGFloat = 420
    static let minimumHeight: CGFloat = 180
    static let viewportHeight: CGFloat = 700
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
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.webxsid.crona.dev",
        category: "MenuBarPopup"
    )
    private weak var appState: CompanionAppState?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popupPanel: StatusPopupPanel?
    private let popupDisplayClock = PopupDisplayClock()
    private var statusDisplayTimer: Timer?
    private var statusDisplayInterval: TimeInterval?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var lastRenderedTitle = ""
    private var lastRenderedDisplayMode: MenuBarDisplayMode?
    private var lastRenderedIconState: MenuBarIconState?
    private var iconAnimationTimer: Timer?
    private var iconAnimationPhase = 0.0
    private var completionTask: Task<Void, Never>?
    private var completionSessionID: String?
    private var completionDeadline: Date?
    private var completedSessionID: String?
    private var pendingUpdate = false
    private var animationGeneration = 0
    private lazy var contextMenu = makeContextMenu()
    private weak var appUpdateMenuItem: NSMenuItem?
    private weak var awayMenuItem: NSMenuItem?

    isolated deinit {
        iconAnimationTimer?.invalidate()
        statusDisplayTimer?.invalidate()
        completionTask?.cancel()
    }

    func configure(appState: CompanionAppState) {
        self.appState = appState
        logger.info("Configured with app state")
    }

    func installIfNeeded() {
        guard let button = statusItem.button else {
            logger.error("Install skipped: status item has no button")
            return
        }
        guard let appState else {
            logger.error("Install skipped: app state is nil")
            return
        }
        logger.info("Installing status item action")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        makePopupPanel(appState: appState)
        logger.info("Status item installed; popup panel exists: \(self.popupPanel != nil, privacy: .public)")
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

    func dismissPopup(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let panel = popupPanel, panel.isVisible else {
            logger.debug("Dismiss requested while panel is not visible")
            appState?.windowService.setMenuBarPopoverPresented(false)
            completion?()
            return
        }

        animationGeneration &+= 1
        logger.info("Dismissing popup; animated=\(animated, privacy: .public)")
        let generation = animationGeneration
        stopDismissalMonitoring()
        popupDisplayClock.stop()
        panel.makeFirstResponder(nil)

        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            appState?.windowService.setMenuBarPopoverPresented(false)
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
            self.appState?.windowService.setMenuBarPopoverPresented(false)
            completion?()
        }
    }

    func showPopupFromNotification() {
        guard popupPanel?.isVisible != true else { return }
        showPopup()
    }

    private func applyStatusItemUpdate(now: Date = Date()) {
        guard let button = statusItem.button, let appState else { return }
        let model = appState.popoverModel
        let nextTitle = MenuBarTextFormatter.statusItemTitle(
            preferences: appState.preferences.preferences,
            connectionState: model.connectionState,
            timerSnapshot: model.timerSnapshot,
            todayWorkedSeconds: appState.popoverStatsService.todayWorkedSeconds,
            todayMetrics: appState.popoverStatsService.todayMetrics,
            todayFocusScore: appState.popoverStatsService.todayFocusScore,
            now: now
        )
        let displayMode = appState.preferences.preferences.menuBarDisplayMode
        let iconState = resolvedIconState(for: model, now: now)

        if lastRenderedDisplayMode != displayMode {
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

        if displayMode.showsIcon {
            if lastRenderedIconState != iconState || button.image == nil || iconState == .connecting {
                button.image = MenuBarIconProvider.image(
                    for: iconState,
                    connectingPhase: iconAnimationPhase
                )
                lastRenderedIconState = iconState
            }
        } else {
            button.image = nil
            lastRenderedIconState = nil
        }
        let accessibilityDescription = iconState.accessibilityDescription(
            for: model.timerSnapshot,
            at: now
        )
        button.setAccessibilityLabel(accessibilityDescription)
        button.toolTip = accessibilityDescription

        if lastRenderedTitle != nextTitle {
            button.title = nextTitle
            lastRenderedTitle = nextTitle
        }
        reconcileIconAnimation(for: displayMode.showsIcon ? iconState : .idle)
        reconcileStatusDisplayTimer()
    }

    private func resolvedIconState(
        for model: PopoverViewModel,
        now: Date
    ) -> MenuBarIconState {
        let snapshot = model.timerSnapshot
        let connectionState = model.connectionState

        if connectionState == .error || connectionState == .incompatible || connectionState == .disconnected {
            clearCompletionTransition()
        } else if let completionSessionID,
                  let snapshotSessionID = snapshot.sessionID,
                  snapshotSessionID != completionSessionID {
            completedSessionID = completionSessionID
            clearCompletionTransition()
        } else if let sessionID = snapshot.sessionID, snapshot.hardLimitExpired {
            beginCompletionTransitionIfNeeded(sessionID: sessionID, now: now)
        }

        if let completionSessionID,
           let completionDeadline,
           now < completionDeadline,
           snapshot.sessionID == nil || snapshot.sessionID == completionSessionID {
            return .completed
        }

        if let completionSessionID, now >= (completionDeadline ?? .distantPast) {
            completedSessionID = completionSessionID
            clearCompletionTransition()
        }

        if let completedSessionID,
           completedSessionID == snapshot.sessionID,
           snapshot.hardLimitExpired {
            return .idle
        }

        return MenuBarIconState.resolve(
            connectionState: connectionState,
            timerSnapshot: snapshot,
            now: now,
            includeCompletion: true
        )
    }

    private func beginCompletionTransitionIfNeeded(sessionID: String, now: Date) {
        guard completionSessionID != sessionID, completedSessionID != sessionID else { return }
        completionTask?.cancel()
        completionSessionID = sessionID
        completionDeadline = now.addingTimeInterval(2)
        let expectedSessionID = sessionID
        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  self.completionSessionID == expectedSessionID
            else { return }
            self.updateStatusItem()
        }
    }

    private func clearCompletionTransition() {
        completionTask?.cancel()
        completionTask = nil
        completionSessionID = nil
        completionDeadline = nil
    }

    private func reconcileIconAnimation(for state: MenuBarIconState) {
        guard state == .connecting else {
            iconAnimationTimer?.invalidate()
            iconAnimationTimer = nil
            iconAnimationPhase = 0
            return
        }
        guard iconAnimationTimer == nil else { return }

        let timer = Timer(timeInterval: 0.16, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.iconAnimationPhase += 0.08
                self.updateStatusItem()
            }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        iconAnimationTimer = timer
    }

    @objc
    private func handleStatusItemClick(_ sender: AnyObject?) {
        logger.info("Status item click received: event=\(String(describing: NSApp.currentEvent?.type), privacy: .public)")
        switch StatusItemClickIntent.resolve(eventType: NSApp.currentEvent?.type) {
        case .togglePopup:
            togglePopup()
        case .showContextMenu:
            showContextMenuFromStatusItem()
        }
    }

    private func togglePopup() {
        guard let panel = popupPanel else {
            logger.error("Toggle skipped: popup panel is nil")
            return
        }
        logger.info("Toggling popup; visible=\(panel.isVisible, privacy: .public)")
        if panel.isVisible {
            dismissPopup()
        } else {
            showPopup()
        }
    }

    private func showContextMenuFromStatusItem() {
        guard let button = statusItem.button else { return }
        dismissPopup(animated: false)
        refreshContextMenu()
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

        let updates = menuItem("Check for Updates…", action: #selector(checkForUpdates))
        appUpdateMenuItem = updates
        menu.addItem(updates)
        menu.addItem(.separator())

        let away = menuItem("Mark Today as Away", action: #selector(toggleAwayMode))
        away.image = NSImage(systemSymbolName: "figure.walk.circle", accessibilityDescription: nil)
        awayMenuItem = away
        menu.addItem(away)
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

    private func refreshContextMenu() {
        guard let appState else { return }
        appUpdateMenuItem?.title = appState.appUpdateService.hasAvailableUpdate
            ? "Update Available…"
            : "Check for Updates…"
        appUpdateMenuItem?.isEnabled = appState.appUpdateService.canCheckForUpdates
        let explicitAway = appState.coreSettingsService.settings.awayModeEnabled
        awayMenuItem?.title = explicitAway
            ? "Disable Away"
            : (appState.todayIsAway ? "Away Today (Rest Rule)" : "Mark Today as Away")
        awayMenuItem?.isEnabled = appState.daemonConnection.connectionState == .connected
            && !appState.coreSettingsService.isSaving
            && (explicitAway || !appState.todayIsAway)
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

    @objc private func toggleAwayMode() {
        guard let appState else { return }
        appState.setAwayMode(!appState.coreSettingsService.settings.awayModeEnabled)
    }

    @objc private func openSettings() {
        appState?.openSettings()
    }

    @objc private func checkForUpdates() {
        appState?.checkForAppUpdates()
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
        guard let panel = popupPanel else {
            logger.error("Show skipped: popup panel is nil")
            return
        }
        guard let button = statusItem.button else {
            logger.error("Show skipped: status item button is nil")
            return
        }
        let viewportSize = NSSize(
            width: StatusPopupSizing.width,
            height: StatusPopupSizing.viewportHeight
        )
        // NSPanel may normalize its frame while its hosting controller is
        // attached. Reassert the fixed viewport immediately before ordering.
        panel.setContentSize(viewportSize)
        panel.setFrame(
            NSRect(origin: panel.frame.origin, size: viewportSize),
            display: false
        )
        logger.info("Showing popup; frame=\(String(describing: panel.frame), privacy: .public)")
        appState?.windowService.setMenuBarPopoverPresented(true)
        Task { await appState?.coreSettingsService.refresh() }
        animationGeneration &+= 1
        popupDisplayClock.start()

        panel.alphaValue = 0

        let restingOrigin = Self.popupOrigin(
            iconRect: statusIconScreenRect(for: button),
            menuBarBottomY: button.window?.frame.minY ?? button.window?.screen?.visibleFrame.maxY ?? 0,
            panelSize: viewportSize,
            visibleFrame: button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        )
        var openingOrigin = restingOrigin
        openingOrigin.y += 8

        panel.setFrameOrigin(openingOrigin)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // Keep presentation visible even if ordering interrupts the animation.
        panel.alphaValue = 1
        logger.info("Popup ordered front; visible=\(panel.isVisible, privacy: .public), frame=\(String(describing: panel.frame), privacy: .public)")
        startDismissalMonitoring()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(restingOrigin)
        }
    }

    private func makePopupPanel(appState: CompanionAppState) {
        guard popupPanel == nil else {
            logger.debug("Panel creation skipped: panel already exists")
            return
        }

        let panel = StatusPopupPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: StatusPopupSizing.width,
                height: StatusPopupSizing.viewportHeight
            ),
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
        let viewportSize = NSSize(
            width: StatusPopupSizing.width,
            height: StatusPopupSizing.viewportHeight
        )
        panel.contentMinSize = viewportSize
        panel.contentMaxSize = viewportSize
        panel.setContentSize(viewportSize)
        panel.setFrame(
            NSRect(origin: .zero, size: viewportSize),
            display: false
        )

        let controller = NSHostingController(
            rootView: PopoverRootView(
                appState: appState,
                displayClock: popupDisplayClock,
                onVisibleSurfaceHeightChange: { [weak panel] height in
                    panel?.visibleSurfaceHeight = min(
                        StatusPopupSizing.viewportHeight,
                        max(StatusPopupSizing.minimumHeight, height)
                    )
                }
            )
        )
        controller.sizingOptions = []
        panel.contentViewController = controller
        // AppKit can leave the hosting view at zero bounds until the window is
        // first ordered. Give it the fixed viewport explicitly.
        controller.view.frame = NSRect(origin: .zero, size: viewportSize)
        controller.view.autoresizingMask = [.width, .height]
        panel.onCancel = { [weak self] in
            self?.dismissPopup()
        }

        popupPanel = panel
        logger.info("Created popup panel; frame=\(String(describing: panel.frame), privacy: .public), contentView=\(panel.contentView != nil, privacy: .public)")
    }

    private func reconcileStatusDisplayTimer() {
        guard let appState else { return }
        let preferences = appState.preferences.preferences
        let snapshot = appState.timerService.snapshot
        let shouldTick = (preferences.menuBarDisplayMode.showsText || preferences.menuBarDisplayMode.showsIcon)
            && snapshot.sessionID != nil
            && snapshot.state == "running"
        let displaySeconds = TimerPresentation.projectedDisplaySeconds(
            for: snapshot,
            at: Date()
        )
        let interval: TimeInterval? = shouldTick
            ? (preferences.menuBarDisplayMode.showsIcon
                ? 1
                : MenuBarTextFormatter.nextRefreshInterval(
                    seconds: displaySeconds,
                    style: preferences.menuBarTimeFormat,
                    countsDown: snapshot.hardLimitActive
                ))
            : nil

        guard interval != statusDisplayInterval else { return }
        statusDisplayTimer?.invalidate()
        statusDisplayTimer = nil
        statusDisplayInterval = interval
        guard let interval else { return }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.statusDisplayTimer = nil
                self.statusDisplayInterval = nil
                self.applyStatusItemUpdate(now: Date())
                self.reconcileStatusDisplayTimer()
            }
        }
        timer.tolerance = interval == 1 ? 0.1 : 1
        RunLoop.main.add(timer, forMode: .common)
        statusDisplayTimer = timer
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

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.popupPanel else { return event }
            let statusWindow = self.statusItem.button?.window
                if event.window === panel {
                let contentBounds = panel.contentView?.bounds ?? .zero
                let visibleSurfaceTop = contentBounds.maxY - panel.visibleSurfaceHeight
                    if event.locationInWindow.y < visibleSurfaceTop {
                        self.logger.debug("Local mouse monitor dismissed click below visible surface")
                        self.dismissPopup()
                    return nil
                }
                return event
            }
                if event.window !== panel, event.window !== statusWindow {
                self.logger.debug("Local mouse monitor dismissed click outside popup")
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
    var visibleSurfaceHeight = StatusPopupSizing.viewportHeight

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
