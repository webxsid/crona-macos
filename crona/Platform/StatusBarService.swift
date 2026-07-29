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
    static let minimumHeight: CGFloat = 180
    static let maximumHeight: CGFloat = 700

    static func resolvedHeight(for measuredHeight: CGFloat) -> CGFloat {
        min(maximumHeight, max(minimumHeight, ceil(measuredHeight)))
    }
}

struct StatusPopupLayoutKey: Equatable {
    let connectionState: CompanionConnectionState
    let selectedTab: PopoverTab
    let hasActiveSession: Bool
    let hasSelectedIssue: Bool
    let hasContext: Bool
    let hasUpcomingSegment: Bool
    let dailyIssueCount: Int
    let habitsItemCount: Int
    let habitsIsLoading: Bool
    let habitsHasError: Bool
    let habitActionInFlightID: Int64?
    let statsDate: String
    let statsIsLoading: Bool
    let statsHasError: Bool
    let statsHasScore: Bool
    let modalKind: PopoverModalKind?
    let showsUpdate: Bool

    init(
        connectionState: CompanionConnectionState,
        selectedTab: PopoverTab,
        hasActiveSession: Bool,
        hasSelectedIssue: Bool,
        hasContext: Bool,
        hasUpcomingSegment: Bool,
        dailyIssueCount: Int = 0,
        habitsItemCount: Int = 0,
        habitsIsLoading: Bool = false,
        habitsHasError: Bool = false,
        habitActionInFlightID: Int64? = nil,
        statsDate: String = "",
        statsIsLoading: Bool = false,
        statsHasError: Bool = false,
        statsHasScore: Bool = false,
        modalKind: PopoverModalKind?,
        showsUpdate: Bool
    ) {
        self.connectionState = connectionState
        self.selectedTab = selectedTab
        self.hasActiveSession = hasActiveSession
        self.hasSelectedIssue = hasSelectedIssue
        self.hasContext = hasContext
        self.hasUpcomingSegment = hasUpcomingSegment
        self.dailyIssueCount = dailyIssueCount
        self.habitsItemCount = habitsItemCount
        self.habitsIsLoading = habitsIsLoading
        self.habitsHasError = habitsHasError
        self.habitActionInFlightID = habitActionInFlightID
        self.statsDate = statsDate
        self.statsIsLoading = statsIsLoading
        self.statsHasError = statsHasError
        self.statsHasScore = statsHasScore
        self.modalKind = modalKind
        self.showsUpdate = showsUpdate
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
    private let signposter = OSSignposter(
        subsystem: "com.crona.macos",
        category: "status-popup"
    )
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var popupPanel: StatusPopupPanel?
    private var hostingController: NSHostingController<PopoverRootView>?
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
    private var lastLayoutKey: StatusPopupLayoutKey?
    private lazy var contextMenu = makeContextMenu()
    private weak var appUpdateMenuItem: NSMenuItem?

    deinit {
        iconAnimationTimer?.invalidate()
        statusDisplayTimer?.invalidate()
        completionTask?.cancel()
    }

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

    func refreshPopupLayout(animated: Bool = true) {
        guard let panel = popupPanel, panel.isVisible else { return }
        resizePanelToFit(panel, animated: animated, force: false)
    }

    func dismissPopup(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let panel = popupPanel, panel.isVisible else {
            completion?()
            return
        }

        animationGeneration &+= 1
        let generation = animationGeneration
        stopDismissalMonitoring()
        popupDisplayClock.stop()
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

    private func applyStatusItemUpdate(now: Date = Date()) {
        guard let button = statusItem.button, let appState else { return }
        let model = appState.popoverModel
        let nextTitle = MenuBarTextFormatter.statusItemTitle(
            preferences: appState.preferences.preferences,
            connectionState: model.connectionState,
            timerSnapshot: model.timerSnapshot,
            todayWorkedSeconds: appState.popoverStatsService.todayWorkedSeconds,
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
        guard let appState, let item = appUpdateMenuItem else { return }
        item.title = appState.appUpdateService.hasAvailableUpdate
            ? "Update Available…"
            : "Check for Updates…"
        item.isEnabled = appState.appUpdateService.canCheckForUpdates
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
        guard let panel = popupPanel, let button = statusItem.button else { return }
        let interval = signposter.beginInterval("Open Popup")
        defer { signposter.endInterval("Open Popup", interval) }
        animationGeneration &+= 1
        let generation = animationGeneration
        popupDisplayClock.start()

        resizePanelToFit(panel, animated: false, force: true)
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

        let controller = NSHostingController(
            rootView: PopoverRootView(
                appState: appState,
                displayClock: popupDisplayClock
            )
        )
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
        resizePanelToFit(panel, animated: false, force: true)
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

    private func resizePanelToFit(
        _ panel: NSPanel,
        animated: Bool,
        force: Bool
    ) {
        guard let hostingController, let appState else { return }
        let layoutKey = Self.layoutKey(for: appState)
        guard force || layoutKey != lastLayoutKey else { return }
        let interval = signposter.beginInterval("Measure Popup")
        defer { signposter.endInterval("Measure Popup", interval) }
        let measured = hostingController.sizeThatFits(
            in: NSSize(width: 420, height: 800)
        )
        let height = StatusPopupSizing.resolvedHeight(for: measured.height)
        lastLayoutKey = layoutKey
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

    static func layoutKey(for appState: CompanionAppState) -> StatusPopupLayoutKey {
        let snapshot = appState.timerService.snapshot
        let presentation = TimerPresentation.from(snapshot)
        let modalKind: PopoverModalKind?
        if appState.isEndSessionSheetPresented {
            modalKind = .endSession
        } else {
            switch appState.issueActionEditor {
            case .status:
                modalKind = .statusNote
            case .dueDate:
                modalKind = .dueDate
            case nil:
                modalKind = nil
            }
        }

        return StatusPopupLayoutKey(
            connectionState: appState.daemonConnection.connectionState,
            selectedTab: appState.selectedPopoverTab,
            hasActiveSession: appState.hasActiveFocusSession,
            hasSelectedIssue: appState.selectedFocusIssue != nil,
            hasContext: appState.contextService.snapshot.issueTitle != nil
                || appState.contextService.snapshot.repoName != nil
                || appState.contextService.snapshot.streamName != nil,
            hasUpcomingSegment: presentation.upcomingSegment != nil,
            dailyIssueCount: appState.dailyFocusService.snapshot.issues.count,
            habitsItemCount: appState.habitsService.snapshot.items.count,
            habitsIsLoading: appState.habitsService.snapshot.isLoading,
            habitsHasError: appState.habitsService.snapshot.lastRefreshError != nil,
            habitActionInFlightID: appState.habitsService.actionInFlightHabitID,
            statsDate: appState.popoverStatsService.snapshot.date,
            statsIsLoading: appState.popoverStatsService.snapshot.isLoading,
            statsHasError: appState.popoverStatsService.snapshot.lastErrorDescription != nil,
            statsHasScore: appState.popoverStatsService.snapshot.focusScore != nil
                || appState.popoverStatsService.snapshot.todayMetrics != nil,
            modalKind: modalKind,
            showsUpdate: appState.appUpdateService.hasAvailableUpdate
                && !appState.isUpdatePresentationBlocked
        )
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
