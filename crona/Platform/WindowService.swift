import AppKit
import SwiftUI

private enum PopupCloseChromeInsets {
    static let leading: CGFloat = 16
    static let top: CGFloat = 14
}

private enum PopupAnimationStyle {
    case centeredFadeBlur
    case edgeSlide(CompanionPopupPosition)
    case mouseFollowerFadeBlur
}

private enum PopupAnimationToken {
    case hardLimit
    case inactivity
    case smartPauseResume
    case hardLimitWarning
}

private enum PopupAnimationMetrics {
    static let offscreenBuffer: CGFloat = 24
    static let centeredEntranceDuration: TimeInterval = 0.24
    static let centeredExitDuration: TimeInterval = 0.2
    static let edgeEntranceDuration: TimeInterval = 0.28
    static let edgeExitDuration: TimeInterval = 0.22
}

@MainActor
final class WindowService {
    private enum TimerHUDMetrics {
        static let commitSize = NSSize(width: 396, height: 338)
    }
    static let transientPopupCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
    ]

    private let activationPolicyApplier: @MainActor (NSApplication.ActivationPolicy) -> Void
    private var lastAppliedActivationPolicy: NSApplication.ActivationPolicy?
    private weak var appState: CompanionAppState?
    private weak var settingsWindow: NSWindow?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var hardLimitPanel: HardLimitPanel?
    private var inactivityPanel: InactivityPanel?
    private var smartPauseResumePanel: SmartPauseResumePanel?
    private var timerHUDPanel: TimerHUDPanel?
    private var timerHUDCompactFrame: NSRect?
    private var isMenuBarPopoverPresented = false
    private var timerHUDWasVisibleBeforeMenuBarPopover = false
    private var timerHUDAppliedPosition: CompanionPopupPosition?
    private var timerHUDAppliedSize: TimerHUDSize?
    #if DEBUG
        private var developerBreakScreenPanel: DeveloperBreakScreenPanel?
    #endif
    private var hardLimitWarningPanel: HardLimitWarningPanel?
    private var hardLimitWarningGlobalMonitor: Any?
    private var hardLimitWarningLocalMonitor: Any?
    private var breakScreenPanels: [CGDirectDisplayID: BreakScreenPanel] = [:]
    private var hardLimitPopupAnimationID: UInt64 = 0
    private var inactivityPopupAnimationID: UInt64 = 0
    private var smartPauseResumeAnimationID: UInt64 = 0
    private var hardLimitWarningAnimationID: UInt64 = 0
    private var breakScreenPrimaryDisplayID: CGDirectDisplayID?
    private var screenParametersObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var externalWindowPresentationCount = 0

    init(
        activationPolicyApplier: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = {
            NSApp.setActivationPolicy($0)
        }
    ) {
        self.activationPolicyApplier = activationPolicyApplier
    }

    var breakScreensVisible: Bool {
        breakScreenPanels.values.contains(where: \.isVisible)
    }

    var hardLimitPopupVisible: Bool {
        hardLimitPanel?.isVisible == true
    }

    var inactivityPopupVisible: Bool {
        inactivityPanel?.isVisible == true
    }

    var smartPauseResumeNoticeVisible: Bool {
        smartPauseResumePanel?.isVisible == true
    }

    var hardLimitWarningIndicatorVisible: Bool {
        hardLimitWarningPanel?.isVisible == true
    }

    func reconcileTimerHUD() {
        guard let appState else { return }
        let snapshot = appState.timerService.snapshot
        let active =
            snapshot.sessionID != nil && snapshot.state != "idle"
            && snapshot.state != "disconnected"
        guard
            Self.timerHUDShouldBeVisible(
                preferencesEnabled: appState.preferences.preferences.showTimerHUD,
                activeTimer: active,
                menuBarPopoverPresented: isMenuBarPopoverPresented
            )
        else {
            timerHUDPanel?.orderOut(nil)
            return
        }
        let panel = timerHUDPanel ?? makeTimerHUDPanel(appState: appState)
        timerHUDPanel = panel
        let preferences = appState.preferences.preferences
        let desiredSize = preferences.timerHUDSize
        if timerHUDAppliedSize != desiredSize {
            resizeTimerHUD(panel, to: desiredSize)
            timerHUDAppliedSize = desiredSize
        }
        if timerHUDAppliedPosition != preferences.timerHUDPosition {
            positionTimerHUD(panel, preference: preferences.timerHUDPosition)
            timerHUDAppliedPosition = preferences.timerHUDPosition
        }
        if !panel.isVisible {
            restoreOrPositionTimerHUD(panel)
            panel.orderFrontRegardless()
        }
    }

    static func timerHUDShouldBeVisible(
        preferencesEnabled: Bool,
        activeTimer: Bool,
        menuBarPopoverPresented: Bool
    ) -> Bool {
        preferencesEnabled && activeTimer && !menuBarPopoverPresented
    }

    func setMenuBarPopoverPresented(_ presented: Bool) {
        guard presented != isMenuBarPopoverPresented else { return }
        if presented {
            timerHUDWasVisibleBeforeMenuBarPopover = timerHUDPanel?.isVisible == true
            isMenuBarPopoverPresented = true
            timerHUDPanel?.orderOut(nil)
            return
        }

        let shouldRestoreExistingPanel = timerHUDWasVisibleBeforeMenuBarPopover
        timerHUDWasVisibleBeforeMenuBarPopover = false
        isMenuBarPopoverPresented = false

        guard let appState else { return }
        let snapshot = appState.timerService.snapshot
        let active =
            snapshot.sessionID != nil && snapshot.state != "idle"
            && snapshot.state != "disconnected"
        guard
            Self.timerHUDShouldBeVisible(
                preferencesEnabled: appState.preferences.preferences.showTimerHUD,
                activeTimer: active,
                menuBarPopoverPresented: false
            )
        else {
            timerHUDPanel?.orderOut(nil)
            return
        }

        if shouldRestoreExistingPanel, let timerHUDPanel {
            timerHUDPanel.orderFrontRegardless()
        } else {
            reconcileTimerHUD()
        }
    }

    func setTimerHUDCommitPresented(_ presented: Bool) {
        guard let panel = timerHUDPanel else { return }
        if presented {
            timerHUDCompactFrame = panel.frame
            var frame = panel.frame
            frame.origin.y = frame.maxY - TimerHUDMetrics.commitSize.height
            frame.size = TimerHUDMetrics.commitSize
            frame = clampedWindowFrame(frame)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
            panel.makeKeyAndOrderFront(nil)
        } else {
            let size = appState?.preferences.preferences.timerHUDSize ?? .spacious
            let compactFrame =
                timerHUDCompactFrame
                ?? NSRect(
                    origin: panel.frame.origin,
                    size: NSSize(width: size.panelSize.width, height: size.panelSize.height)
                )
            timerHUDCompactFrame = nil
            panel.makeFirstResponder(nil)
            panel.resignKey()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(compactFrame, display: true)
            }
        }
    }

    private func makeTimerHUDPanel(appState: CompanionAppState) -> TimerHUDPanel {
        let panel = TimerHUDPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: TimerHUDSize.spacious.panelSize.width,
                    height: TimerHUDSize.spacious.panelSize.height)
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("CronaTimerHUD")
        panel.contentViewController = makeTimerHUDHostingController(
            for: panel,
            size: appState.preferences.preferences.timerHUDSize
        )
        return panel
    }

    private func restoreOrPositionTimerHUD(_ panel: NSPanel) {
        let preferredSize = appState?.preferences.preferences.timerHUDSize ?? .spacious
        let preferredNSSize = NSSize(
            width: preferredSize.panelSize.width, height: preferredSize.panelSize.height)
        if panel.setFrameUsingName("CronaTimerHUD") {
            if panel.frame.size != preferredNSSize {
                var compactFrame = panel.frame
                compactFrame.origin.y = compactFrame.maxY - preferredNSSize.height
                compactFrame.size = preferredNSSize
                panel.setFrame(compactFrame, display: false)
            }
            clampTimerHUD(panel)
            return
        }
        let screen = screenContainingMouse(in: NSScreen.screens) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = InactivityPopupPositioner.origin(
            in: frame,
            panelSize: panel.frame.size,
            preference: appState?.preferences.preferences.timerHUDPosition ?? .bottomCenter,
            topMargin: 20,
            bottomMargin: 20,
            horizontalMargin: 20
        )
        panel.setFrameOrigin(origin)
    }

    private func resizeTimerHUD(_ panel: TimerHUDPanel, to size: TimerHUDSize) {
        let targetSize = NSSize(width: size.panelSize.width, height: size.panelSize.height)
        var frame = panel.frame
        frame.origin.y = frame.maxY - targetSize.height
        frame.size = targetSize
        panel.contentViewController = makeTimerHUDHostingController(for: panel, size: size)
        panel.setFrame(clampedWindowFrame(frame), display: true)
    }

    private func makeTimerHUDHostingController(
        for panel: TimerHUDPanel,
        size: TimerHUDSize
    ) -> NSHostingController<TimerHUDRootView> {
        let controller = NSHostingController(
            rootView: TimerHUDRootView(
                appState: appState!,
                size: size
            )
        )
        controller.sizingOptions = []
        return controller
    }

    private func positionTimerHUD(_ panel: NSPanel, preference: CompanionPopupPosition) {
        guard
            let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
                ?? NSScreen.main
        else { return }
        let origin = InactivityPopupPositioner.origin(
            in: screen.visibleFrame,
            panelSize: panel.frame.size,
            preference: preference,
            topMargin: 20,
            bottomMargin: 20,
            horizontalMargin: 20
        )
        panel.setFrameOrigin(origin)
    }

    private func clampTimerHUD(_ panel: NSPanel) {
        let screen =
            NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let x = min(max(frame.minX + 8, panel.frame.minX), frame.maxX - panel.frame.width - 8)
        let y = min(max(frame.minY + 8, panel.frame.minY), frame.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func clampedWindowFrame(_ proposed: NSRect) -> NSRect {
        let screen =
            NSScreen.screens.first(where: { $0.visibleFrame.intersects(proposed) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return proposed }
        var frame = proposed
        frame.origin.x = min(max(visible.minX + 8, frame.minX), visible.maxX - frame.width - 8)
        frame.origin.y = min(max(visible.minY + 8, frame.minY), visible.maxY - frame.height - 8)
        return frame
    }

    func configure(appState: CompanionAppState) {
        self.appState = appState
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.breakScreensVisible { self.showBreakScreens() }
                if let panel = self.timerHUDPanel, panel.isVisible { self.clampTimerHUD(panel) }
            }
        }
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcileTransientPopupsForActiveSpace()
            }
        }
    }

    private func reconcileTransientPopupsForActiveSpace() {
        var panels: [NSPanel] = [
            hardLimitPanel,
            inactivityPanel,
            smartPauseResumePanel,
            hardLimitWarningPanel,
        ].compactMap { $0 }
        panels.append(contentsOf: breakScreenPanels.values.map { $0 as NSPanel })
        #if DEBUG
            if let developerBreakScreenPanel {
                panels.append(developerBreakScreenPanel)
            }
        #endif

        for panel in panels where panel.isVisible {
            panel.collectionBehavior = Self.transientPopupCollectionBehavior
            panel.orderFrontRegardless()
        }
    }

    func showBreakScreens() {
        guard let appState else { return }
        let screens = NSScreen.screens
        let activeIDs = Set(screens.compactMap(Self.displayID))
        if breakScreenPrimaryDisplayID == nil
            || !activeIDs.contains(breakScreenPrimaryDisplayID!)
        {
            let activeScreen = screenContainingMouse(in: screens) ?? NSScreen.main ?? screens.first
            breakScreenPrimaryDisplayID = activeScreen.flatMap(Self.displayID)
        }

        let staleIDs = breakScreenPanels.keys.filter { !activeIDs.contains($0) }
        for id in staleIDs {
            guard let panel = breakScreenPanels.removeValue(forKey: id) else { continue }
            panel.orderOut(nil)
            panel.close()
        }

        for screen in screens {
            guard let id = Self.displayID(screen) else { continue }
            let isPrimary = id == breakScreenPrimaryDisplayID
            let rootView = BreakScreenRootView(
                appState: appState,
                screen: screen,
                isPrimary: isPrimary
            )

            let panel: BreakScreenPanel
            if let existing = breakScreenPanels[id] {
                panel = existing
                if let controller = panel.contentViewController
                    as? NSHostingController<BreakScreenRootView>
                {
                    controller.rootView = rootView
                } else {
                    panel.contentViewController = NSHostingController(rootView: rootView)
                }
            } else {
                panel = makeBreakScreenPanel(rootView: rootView)
                breakScreenPanels[id] = panel
            }

            panel.setFrame(screen.frame, display: true)
            let wasVisible = panel.isVisible
            if !wasVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.24
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                }
            }
            if isPrimary, !wasVisible {
                NSApp.activate()
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func closeBreakScreens() {
        let panels = Array(breakScreenPanels.values)
        breakScreenPanels.removeAll()
        breakScreenPrimaryDisplayID = nil
        for panel in panels {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    panel.animator().alphaValue = 0
                },
                completionHandler: {
                    MainActor.assumeIsolated {
                        panel.orderOut(nil)
                        panel.contentViewController = nil
                        panel.close()
                    }
                })
        }
    }

    #if DEBUG
        func showDeveloperBreakScreen() {
            guard let appState else { return }
            let screen = popupTargetScreen()
            let panel =
                developerBreakScreenPanel
                ?? makeDeveloperBreakScreenPanel(
                    rootView: DeveloperBreakScreenRootView(appState: appState, screen: screen)
                )
            developerBreakScreenPanel = panel
            if let controller = panel.contentViewController
                as? NSHostingController<DeveloperBreakScreenRootView>
            {
                controller.rootView = DeveloperBreakScreenRootView(
                    appState: appState, screen: screen)
            }
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }

        func dismissDeveloperPreviews() {
            closeHardLimitPopup()
            closeInactivityPopup()
            closeHardLimitWarningIndicator()
            closeSmartPauseResumeNotice()
            developerBreakScreenPanel?.orderOut(nil)
        }
    #endif

    private func makeBreakScreenPanel(
        rootView: BreakScreenRootView
    ) -> BreakScreenPanel {
        let panel = BreakScreenPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = Self.transientPopupCollectionBehavior
        panel.hidesOnDeactivate = false
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: rootView)
        return panel
    }

    #if DEBUG
        private func makeDeveloperBreakScreenPanel(
            rootView: DeveloperBreakScreenRootView
        ) -> DeveloperBreakScreenPanel {
            let panel = DeveloperBreakScreenPanel(
                contentRect: .zero,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = Self.transientPopupCollectionBehavior
            panel.hidesOnDeactivate = false
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.isMovable = false
            panel.isMovableByWindowBackground = false
            panel.isReleasedWhenClosed = false
            panel.contentViewController = NSHostingController(rootView: rootView)
            return panel
        }
    #endif

    private func screenContainingMouse(in screens: [NSScreen]) -> NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first(where: { NSMouseInRect(location, $0.frame, false) })
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }

    func showSettings(openScene: () -> Void) {
        presentAsRegularApplication()
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        openScene()
        NSApp.activate()
    }

    func beginExternalWindowPresentation() {
        externalWindowPresentationCount += 1
        presentAsRegularApplication()
    }

    func endExternalWindowPresentation() {
        externalWindowPresentationCount = max(0, externalWindowPresentationCount - 1)
        refreshApplicationActivationPolicy()
    }

    func registerSettingsWindow(_ window: NSWindow, appearance: CompanionAppearance = .system) {
        if settingsWindow === window {
            configureSettingsWindowChrome(window)
            updateSettingsWindowAppearance(appearance, on: window)
            return
        }
        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
        }

        settingsWindow = window
        configureSettingsWindowChrome(window)
        updateSettingsWindowAppearance(appearance, on: window)
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
                self.refreshApplicationActivationPolicy()
            }
        }
    }

    func refreshApplicationActivationPolicy() {
        let shouldRemainRegular =
            settingsWindow?.isVisible == true || externalWindowPresentationCount > 0
        if shouldRemainRegular {
            presentAsRegularApplication()
            return
        }

        let shouldHideDockIcon =
            appState?.preferences.preferences.hideDockIconWhenNoWindowsOpen ?? true
        if shouldHideDockIcon {
            applyActivationPolicyIfNeeded(.accessory)
        } else {
            presentAsRegularApplication()
        }
    }

    func initializeApplicationActivationPolicy() {
        applyActivationPolicyIfNeeded(.accessory)
    }

    private func presentAsRegularApplication() {
        guard applyActivationPolicyIfNeeded(.regular) else {
            NSApp.unhide(nil)
            return
        }
        NSApp.applicationIconImage = CronaAppIcon.image
        NSApp.unhide(nil)

        // AppKit rebuilds the Dock tile asynchronously when an accessory app
        // transitions to a regular app. Reapply the icon after that transition.
        Task { @MainActor in
            await Task.yield()
            NSApp.applicationIconImage = CronaAppIcon.image
            NSApp.dockTile.display()
            NSApp.activate()
        }
    }

    @discardableResult
    private func applyActivationPolicyIfNeeded(
        _ policy: NSApplication.ActivationPolicy
    ) -> Bool {
        guard lastAppliedActivationPolicy != policy else { return false }
        activationPolicyApplier(policy)
        lastAppliedActivationPolicy = policy
        return true
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
            appState?.daemonConnection.lastErrorDescription =
                "Failed to open TUI: \(error.localizedDescription)"
        }
    }

    func confirmStopCrona(hasActiveSession: Bool) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Stop Crona?"
        alert.informativeText =
            hasActiveSession
            ? "The daemon and companion will quit. Your active timer will not be committed automatically."
            : "The daemon and companion will quit. You can start Crona again whenever you need it."
        alert.addButton(withTitle: "Stop Crona")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func showStopCronaError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Crona Couldn’t Stop"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func activateAppForPopup() {
        NSApp.activate()
    }

    func showHardLimitPopup() {
        guard let appState else { return }

        let targetScreen = popupTargetScreen()
        let panel = hardLimitPanel ?? makeHardLimitPanel(appState: appState)
        hardLimitPanel = panel
        resizeHardLimitPanel(panel, animated: false)
        position(panel: panel, on: targetScreen)

        panel.makeFirstResponder(nil)
        activateAppForPopup()
        panel.makeKeyAndOrderFront(nil)
        animatePopupEntrance(panel, style: .centeredFadeBlur, token: .hardLimit)
    }

    func updateHardLimitPopup() {
        guard let panel = hardLimitPanel else { return }
        let targetScreen = panel.screen ?? popupTargetScreen()
        resizeHardLimitPanel(panel, animated: true)
        position(panel: panel, on: targetScreen)
    }

    func closeHardLimitPopup(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let panel = hardLimitPanel else {
            completion?()
            return
        }
        panel.makeFirstResponder(nil)
        panel.resignKey()
        animatePopupExit(
            panel,
            style: .centeredFadeBlur,
            token: .hardLimit,
            completion: completion
        )
    }

    func updateSettingsWindowAppearance(
        _ appearance: CompanionAppearance,
        on window: NSWindow? = nil
    ) {
        let targetWindow = window ?? settingsWindow
        guard let targetWindow else { return }

        switch appearance {
        case .system:
            targetWindow.appearance = nil
        case .light:
            targetWindow.appearance = NSAppearance(named: .aqua)
        case .dark:
            targetWindow.appearance = NSAppearance(named: .darkAqua)
        }
        targetWindow.isOpaque = false
        targetWindow.backgroundColor = .clear
    }

    private func configureSettingsWindowChrome(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.title = ""
        window.titleVisibility = .hidden
        window.toolbar = nil
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear

        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.isHidden = false
            button.alphaValue = 1
        }

        DispatchQueue.main.async { [weak window] in
            DispatchQueue.main.async {
                guard let window else { return }
                window.title = ""
                window.titleVisibility = .hidden
            }
        }
    }

    func showInactivityPopup() {
        guard let appState else { return }

        let targetScreen = popupTargetScreen()
        let panel = inactivityPanel ?? makeInactivityPanel(appState: appState)
        inactivityPanel = panel
        resizeInactivityPanel(panel, animated: false)
        position(
            panel: panel,
            on: targetScreen,
            preference: appState.preferences.preferences.inactivityPopupPosition
        )

        panel.makeFirstResponder(nil)
        activateAppForPopup()
        panel.makeKeyAndOrderFront(nil)
        animatePopupEntrance(
            panel,
            style: .edgeSlide(appState.preferences.preferences.inactivityPopupPosition),
            token: .inactivity
        )
    }

    func updateInactivityPopup() {
        guard let panel = inactivityPanel, let appState else { return }
        resizeInactivityPanel(panel, animated: true)
        position(
            panel: panel,
            on: panel.screen ?? popupTargetScreen(),
            preference: appState.preferences.preferences.inactivityPopupPosition
        )
    }

    func closeInactivityPopup(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let panel = inactivityPanel, let appState else { return }
        panel.makeFirstResponder(nil)
        panel.resignKey()
        animatePopupExit(
            panel,
            style: .edgeSlide(appState.preferences.preferences.inactivityPopupPosition),
            token: .inactivity,
            completion: completion
        )
    }

    func showSmartPauseResumeNotice() {
        guard let appState, appState.smartPauseResumeNotice != nil else { return }

        let panel = smartPauseResumePanel ?? makeSmartPauseResumePanel(appState: appState)
        smartPauseResumePanel = panel
        panel.setFrame(
            NSRect(
                x: 0,
                y: 0,
                width: 272 + PopupCloseChromeInsets.leading,
                height: 82 + PopupCloseChromeInsets.top
            ),
            display: false
        )
        position(
            panel: panel,
            on: popupTargetScreen(),
            preference: appState.preferences.preferences.inactivityPopupPosition
        )
        panel.orderFrontRegardless()
        animatePopupEntrance(
            panel,
            style: .edgeSlide(appState.preferences.preferences.inactivityPopupPosition),
            token: .smartPauseResume
        )
    }

    func closeSmartPauseResumeNotice(completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let panel = smartPauseResumePanel, let appState else { return }
        animatePopupExit(
            panel,
            style: .edgeSlide(appState.preferences.preferences.inactivityPopupPosition),
            token: .smartPauseResume,
            completion: completion
        )
    }

    func shutdown() {
        closeHardLimitPopup()
        destroyHardLimitPanel()
        closeInactivityPopup()
        destroyInactivityPanel()
        closeSmartPauseResumeNotice()
        destroySmartPauseResumePanel()
        closeHardLimitWarningIndicator()
        hardLimitWarningPanel?.close()
        hardLimitWarningPanel = nil
        closeBreakScreens()
        #if DEBUG
            developerBreakScreenPanel?.orderOut(nil)
            developerBreakScreenPanel?.close()
            developerBreakScreenPanel = nil
        #endif
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
    }

    func showHardLimitWarningIndicator() {
        guard let appState else { return }

        let panel: HardLimitWarningPanel
        if let existingPanel = hardLimitWarningPanel {
            panel = existingPanel
            if let hostingController = panel.contentViewController
                as? NSHostingController<HardLimitWarningIndicatorRootView>
            {
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
        animatePopupEntrance(panel, style: .mouseFollowerFadeBlur, token: .hardLimitWarning)
    }

    func closeHardLimitWarningIndicator(completion: (@MainActor @Sendable () -> Void)? = nil) {
        if let panel = hardLimitWarningPanel {
            animatePopupExit(panel, style: .mouseFollowerFadeBlur, token: .hardLimitWarning) {
                [weak self] in
                self?.removeHardLimitWarningMonitors()
                completion?()
            }
            return
        }
        removeHardLimitWarningMonitors()
        completion?()
    }

    private func makeHardLimitPanel(appState: CompanionAppState) -> HardLimitPanel {
        let panel = HardLimitPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HardLimitPopupSizing.panelWidth,
                height: HardLimitPopupSizing.panelHeight(for: .decision)
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = Self.transientPopupCollectionBehavior
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.worksWhenModal = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: HardLimitPopupRootView(appState: appState))
        return panel
    }

    private func makeInactivityPanel(appState: CompanionAppState) -> InactivityPanel {
        let panel = InactivityPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 380 + PopupCloseChromeInsets.leading,
                height: 128 + PopupCloseChromeInsets.top
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = Self.transientPopupCollectionBehavior
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.worksWhenModal = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: InactivityPopupRootView(appState: appState))
        return panel
    }

    private func makeSmartPauseResumePanel(appState: CompanionAppState) -> SmartPauseResumePanel {
        let panel = SmartPauseResumePanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 272 + PopupCloseChromeInsets.leading,
                height: 70 + PopupCloseChromeInsets.top
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = Self.transientPopupCollectionBehavior
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.worksWhenModal = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: SmartPauseResumeNoticeRootView(appState: appState)
        )
        panel.setContentSize(
            NSSize(
                width: 272 + PopupCloseChromeInsets.leading,
                height: 82 + PopupCloseChromeInsets.top
            )
        )
        return panel
    }

    private func resizeInactivityPanel(_ panel: NSPanel, animated: Bool) {
        guard let appState else { return }
        let height: CGFloat
        switch appState.inactivityPopupPhase {
        case .decision:
            height = 95 + PopupCloseChromeInsets.top
        case .endSession:
            height = 430 + PopupCloseChromeInsets.top
        case nil:
            height = panel.frame.height
        }
        guard abs(panel.frame.height - height) > 0.5 else { return }

        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: 380 + PopupCloseChromeInsets.leading, height: height)

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

    private func resizeHardLimitPanel(_ panel: NSPanel, animated: Bool) {
        guard let appState else { return }
        let height = HardLimitPopupSizing.panelHeight(for: appState.hardLimitPopupPhase)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        var frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size.height = height
        frame.origin = NSPoint(x: center.x - frame.width / 2, y: center.y - height / 2)

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

    private func destroyHardLimitPanel() {
        guard let panel = hardLimitPanel else { return }
        panel.makeFirstResponder(nil)
        panel.resignKey()
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.close()
        hardLimitPanel = nil
    }

    private func destroyInactivityPanel() {
        guard let panel = inactivityPanel else { return }
        panel.makeFirstResponder(nil)
        panel.resignKey()
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.close()
        inactivityPanel = nil
    }

    private func destroySmartPauseResumePanel() {
        guard let panel = smartPauseResumePanel else { return }
        panel.orderOut(nil)
        panel.contentViewController = nil
        panel.close()
        smartPauseResumePanel = nil
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
        panel.collectionBehavior = Self.transientPopupCollectionBehavior
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
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
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.screens.first!
    }

    private func cornerPopupTargetScreen() -> NSScreen {
        screenContainingMouse(in: NSScreen.screens) ?? popupTargetScreen()
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

    private func position(
        panel: NSWindow,
        on screen: NSScreen,
        preference: CompanionPopupPosition
    ) {
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = InactivityPopupPositioner.origin(
            in: frame,
            panelSize: size,
            preference: preference,
            topMargin: PopupPlacementInsets.top,
            bottomMargin: PopupPlacementInsets.bottom,
            horizontalMargin: PopupPlacementInsets.side
        )
        panel.setFrameOrigin(
            clamped(
                origin: adjusted(origin: origin, for: preference),
                size: size,
                in: frame
            )
        )
    }

    private func adjusted(
        origin: NSPoint,
        for preference: CompanionPopupPosition
    ) -> NSPoint {
        let adjustedX: CGFloat
        switch preference {
        case .topLeft, .bottomLeft:
            adjustedX = origin.x - PopupCloseChromeInsets.leading
        case .topCenter, .bottomCenter:
            adjustedX = origin.x - (PopupCloseChromeInsets.leading / 2)
        case .topRight, .bottomRight:
            adjustedX = origin.x
        }

        let adjustedY: CGFloat
        switch preference {
        case .topLeft, .topCenter, .topRight:
            adjustedY = origin.y + PopupCloseChromeInsets.top
        case .bottomLeft, .bottomCenter, .bottomRight:
            adjustedY = origin.y
        }

        return NSPoint(x: adjustedX, y: adjustedY)
    }

    private func clamped(
        origin: NSPoint,
        size: NSSize,
        in frame: NSRect
    ) -> NSPoint {
        NSPoint(
            x: min(
                max(frame.minX + PopupPlacementInsets.side, origin.x),
                frame.maxX - size.width - PopupPlacementInsets.side),
            y: min(
                max(frame.minY + PopupPlacementInsets.bottom, origin.y),
                frame.maxY - size.height - PopupPlacementInsets.top)
        )
    }

    private func positionWarning(panel: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? popupTargetScreen()
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let margin: CGFloat = 12
        let cursorClearance: CGFloat = 24
        let roomOnRight = visibleFrame.maxX - mouseLocation.x
        let preferredX =
            roomOnRight >= panelSize.width + cursorClearance + margin
            ? mouseLocation.x + cursorClearance
            : mouseLocation.x - panelSize.width - cursorClearance
        let roomBelow = mouseLocation.y - visibleFrame.minY
        let preferredY =
            roomBelow >= panelSize.height + cursorClearance + margin
            ? mouseLocation.y - panelSize.height - cursorClearance
            : mouseLocation.y + cursorClearance

        let origin = NSPoint(
            x: min(
                max(visibleFrame.minX + margin, preferredX),
                visibleFrame.maxX - panelSize.width - margin),
            y: min(
                max(visibleFrame.minY + margin, preferredY),
                visibleFrame.maxY - panelSize.height - margin)
        )
        guard hypot(panel.frame.origin.x - origin.x, panel.frame.origin.y - origin.y) > 0.75 else {
            return
        }
        panel.setFrameOrigin(origin)
    }

    private func animatePopupEntrance(
        _ panel: NSPanel,
        style: PopupAnimationStyle,
        token: PopupAnimationToken
    ) {
        advanceAnimationID(for: token)
        switch style {
        case .centeredFadeBlur, .mouseFollowerFadeBlur:
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PopupAnimationMetrics.centeredEntranceDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        case .edgeSlide(let preference):
            let finalFrame = panel.frame
            let startFrame = offscreenFrame(
                for: finalFrame,
                preference: preference,
                visibleFrame: panel.screen?.visibleFrame
            )
            panel.alphaValue = 1
            panel.setFrame(startFrame, display: false)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PopupAnimationMetrics.edgeEntranceDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
            }
        }
    }

    private func animatePopupExit(
        _ panel: NSPanel,
        style: PopupAnimationStyle,
        token: PopupAnimationToken,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let animationID = advanceAnimationID(for: token)
        switch style {
        case .centeredFadeBlur, .mouseFollowerFadeBlur:
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PopupAnimationMetrics.centeredExitDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    guard self.animationID(for: token) == animationID else { return }
                    panel.orderOut(nil)
                    panel.alphaValue = 1
                    completion?()
                }
            }
        case .edgeSlide(let preference):
            let restingFrame = panel.frame
            let dismissedFrame = offscreenFrame(
                for: restingFrame,
                preference: preference,
                visibleFrame: panel.screen?.visibleFrame
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = PopupAnimationMetrics.edgeExitDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(dismissedFrame, display: true)
            } completionHandler: {
                MainActor.assumeIsolated {
                    guard self.animationID(for: token) == animationID else { return }
                    panel.orderOut(nil)
                    panel.setFrame(restingFrame, display: false)
                    completion?()
                }
            }
        }
    }

    @discardableResult
    private func advanceAnimationID(for token: PopupAnimationToken) -> UInt64 {
        switch token {
        case .hardLimit:
            hardLimitPopupAnimationID &+= 1
            return hardLimitPopupAnimationID
        case .inactivity:
            inactivityPopupAnimationID &+= 1
            return inactivityPopupAnimationID
        case .smartPauseResume:
            smartPauseResumeAnimationID &+= 1
            return smartPauseResumeAnimationID
        case .hardLimitWarning:
            hardLimitWarningAnimationID &+= 1
            return hardLimitWarningAnimationID
        }
    }

    private func animationID(for token: PopupAnimationToken) -> UInt64 {
        switch token {
        case .hardLimit:
            hardLimitPopupAnimationID
        case .inactivity:
            inactivityPopupAnimationID
        case .smartPauseResume:
            smartPauseResumeAnimationID
        case .hardLimitWarning:
            hardLimitWarningAnimationID
        }
    }

    private func offscreenFrame(
        for frame: NSRect,
        preference: CompanionPopupPosition,
        visibleFrame: NSRect?
    ) -> NSRect {
        var offscreen = frame
        offscreen.origin = InactivityPopupPositioner.offscreenOrigin(
            for: frame,
            in: visibleFrame ?? panelScreenFrame(containing: frame),
            preference: preference,
            buffer: PopupAnimationMetrics.offscreenBuffer
        )
        return offscreen
    }

    private func panelScreenFrame(containing frame: NSRect) -> NSRect {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? frame
    }

    private func installHardLimitWarningMonitorsIfNeeded() {
        guard hardLimitWarningGlobalMonitor == nil, hardLimitWarningLocalMonitor == nil else {
            return
        }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]

        hardLimitWarningGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.hardLimitWarningPanel, panel.isVisible else {
                    return
                }
                self.positionWarning(panel: panel)
            }
        }

        hardLimitWarningLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) {
            [weak self] event in
            guard let self, let panel = self.hardLimitWarningPanel, panel.isVisible else {
                return event
            }
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

struct InactivityPopupPositioner {
    static func offscreenOrigin(
        for frame: NSRect,
        in visibleFrame: NSRect,
        preference: CompanionPopupPosition,
        buffer: CGFloat
    ) -> NSPoint {
        switch preference {
        case .topLeft, .bottomLeft:
            NSPoint(x: visibleFrame.minX - frame.width - buffer, y: frame.origin.y)
        case .topRight, .bottomRight:
            NSPoint(x: visibleFrame.maxX + buffer, y: frame.origin.y)
        case .topCenter:
            NSPoint(x: frame.origin.x, y: visibleFrame.maxY + buffer)
        case .bottomCenter:
            NSPoint(x: frame.origin.x, y: visibleFrame.minY - frame.height - buffer)
        }
    }

    static func origin(
        in frame: NSRect,
        panelSize: NSSize,
        preference: CompanionPopupPosition,
        topMargin: CGFloat,
        bottomMargin: CGFloat,
        horizontalMargin: CGFloat
    ) -> NSPoint {
        let x: CGFloat
        switch preference {
        case .topLeft, .bottomLeft:
            x = frame.minX + horizontalMargin
        case .topCenter, .bottomCenter:
            x = frame.midX - (panelSize.width / 2)
        case .topRight, .bottomRight:
            x = frame.maxX - panelSize.width - horizontalMargin
        }

        let y: CGFloat
        switch preference {
        case .topLeft, .topCenter, .topRight:
            y = frame.maxY - panelSize.height - topMargin
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = frame.minY + bottomMargin
        }

        return NSPoint(x: x, y: y)
    }

    static func origin(
        in frame: NSRect,
        panelSize: NSSize,
        preference: CompanionPopupPosition,
        margin: CGFloat
    ) -> NSPoint {
        origin(
            in: frame,
            panelSize: panelSize,
            preference: preference,
            topMargin: margin,
            bottomMargin: margin,
            horizontalMargin: margin
        )
    }
}

private enum PopupPlacementInsets {
    static let top: CGFloat = 12
    static let side: CGFloat = top - 4
    static let bottom: CGFloat = top - 4
}

private final class HardLimitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class TimerHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class InactivityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SmartPauseResumePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HardLimitWarningPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class BreakScreenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {}
}

#if DEBUG
    private final class DeveloperBreakScreenPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func cancelOperation(_ sender: Any?) {}
    }
#endif
