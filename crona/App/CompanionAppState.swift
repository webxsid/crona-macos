import AppKit
import Combine
import Foundation
import OSLog

enum SettingsDestination: String, CaseIterable, Equatable, Identifiable {
    case general
    case menuBar
    case smartPause
    case breakScreen
    case notifications
    case runtime
    case diagnostics
    case updates
    case about
#if DEBUG
    case developer
#endif

    var id: String { rawValue }
}

struct SettingsNavigationHistory: Equatable {
    private(set) var current: SettingsDestination = .general
    private(set) var backStack: [SettingsDestination] = []
    private(set) var forwardStack: [SettingsDestination] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    mutating func navigate(to destination: SettingsDestination) {
        guard destination != current else { return }
        backStack.append(current)
        current = destination
        forwardStack.removeAll()
    }

    mutating func goBack() {
        guard let destination = backStack.popLast() else { return }
        forwardStack.append(current)
        current = destination
    }

    mutating func goForward() {
        guard let destination = forwardStack.popLast() else { return }
        backStack.append(current)
        current = destination
    }
}

enum EndSessionPresentationSource: Equatable {
    case menuPopover
    case hardLimitPopup
    case inactivityPopup
}

enum IssueActionEditor: Equatable {
    case status(issue: DailyFocusIssue, status: CronaIssueStatus)
    case dueDate(issue: DailyFocusIssue)
}

struct SmartPauseResumeNotice: Equatable {
    let sessionID: String
    let resumedAt: Date
}

#if DEBUG
enum DeveloperPreviewKind: Equatable {
    case hardLimit
    case inactivity
    case breakScreen
}
#endif

@MainActor
final class CompanionAppState: ObservableObject {
    let logger = Logger(subsystem: "com.crona.macos", category: "app")

    let preferences: PreferencesService
    let kernelDiscovery: KernelDiscoveryService
    let notificationService: NotificationService
    let alertSettingsService: AlertSettingsService
    let dayBoundarySettingsService: DayBoundarySettingsService
    let launchAtLoginService: LaunchAtLoginService
    let daemonConnection: DaemonConnectionService
    let diagnosticsService: DiagnosticsService
    let timerService: TimerService
    let contextService: ContextService
    let dailyFocusService: DailyFocusService
    let issueActionsService: IssueActionsService
    let habitsService: HabitsService
    let popoverStatsService: PopoverStatsService
    let hardLimitCountdownService: HardLimitCountdownService
    let inactivityPopupCountdownService: HardLimitCountdownService
    let windowService: WindowService
    let statusBarService: StatusBarService
    let smartPauseService: SmartPauseService
    let breakScreenService: BreakScreenService
    let appUpdateService: AppUpdateService
    private var cancellables: Set<AnyCancellable> = []
    private var daemonEventObserver: NSObjectProtocol?
    private var daemonConnectObserver: NSObjectProtocol?
    private var endSessionFallbackTask: Task<Void, Never>?
    private var hardLimitPopupDismissTask: Task<Void, Never>?
    private var smartPauseResumeNoticeDismissTask: Task<Void, Never>?
    private var presentationTimer: Timer?
    private var lastWarningIndicatorKey: String?
    private var settingsSceneAction: (() -> Void)?
    private var selectedPopoverTabLayoutRefreshTask: Task<Void, Never>?
    @Published var selectedFocusIssue: DailyFocusIssue?
    @Published var issueActionEditor: IssueActionEditor?
    @Published var issueActionNote = ""
    @Published var issueActionDate = Date()
    @Published var selectedPopoverTab: PopoverTab = .now
    @Published private(set) var settingsNavigation = SettingsNavigationHistory()
    @Published var isEndSessionSheetPresented = false
    @Published var endSessionCommitMessage = ""
    @Published var isSubmittingEndSession = false
    @Published var endSessionErrorMessage: String?
    @Published private(set) var pendingEndSessionID: String?
    @Published private(set) var endSessionPresentationSource: EndSessionPresentationSource?
    @Published private(set) var endSessionFocusRequest = 0
    @Published var hardLimitPopupPhase: HardLimitPopupPhase?
    @Published private(set) var hardLimitPopupSessionID: String?
    @Published var hardLimitPopupExtendChoice = HardLimitExtendChoice.defaultValue
    @Published var hardLimitPopupErrorMessage: String?
    @Published var isSubmittingHardLimitAction = false
    @Published var hardLimitPopupSuccessModel: HardLimitPopupSuccessModel?
    @Published var hardLimitWarningIndicatorModel: HardLimitWarningIndicatorModel?
    @Published var isHardLimitPopupAnimatingIn = false
    @Published var inactivityPopupPhase: InactivityPopupPhase?
    @Published var inactivityPopupDelivery: CronaAlertDelivery?
    @Published private(set) var inactivityPopupSessionID: String?
    @Published var isHardLimitWarningIndicatorAnimatingIn = false
    @Published var smartPauseResumeNotice: SmartPauseResumeNotice?
#if DEBUG
    @Published var developerPreviewKind: DeveloperPreviewKind?
#endif

    init() {
        let preferences = PreferencesService()
        let kernelDiscovery = KernelDiscoveryService(configLoader: CronaConfigLoader())
        let notificationService = NotificationService()
        let launchAtLoginService = LaunchAtLoginService()
        let daemonConnection = DaemonConnectionService(kernelDiscovery: kernelDiscovery)
        let contextService = ContextService(daemonConnection: daemonConnection)
        let timerService = TimerService(daemonConnection: daemonConnection)
        let dailyFocusService = DailyFocusService(daemonConnection: daemonConnection)
        let issueActionsService = IssueActionsService(
            daemonConnection: daemonConnection,
            dailyFocusService: dailyFocusService
        )
        let habitsService = HabitsService(daemonConnection: daemonConnection)
        let popoverStatsService = PopoverStatsService(daemonConnection: daemonConnection)
        let diagnosticsService = DiagnosticsService(
            daemonConnection: daemonConnection,
            kernelDiscovery: kernelDiscovery
        )
        let alertSettingsService = AlertSettingsService(daemonConnection: daemonConnection)
        let dayBoundarySettingsService = DayBoundarySettingsService(daemonConnection: daemonConnection)
        let appUpdateService = AppUpdateService(preferences: preferences)

        self.preferences = preferences
        self.kernelDiscovery = kernelDiscovery
        self.notificationService = notificationService
        self.alertSettingsService = alertSettingsService
        self.dayBoundarySettingsService = dayBoundarySettingsService
        self.launchAtLoginService = launchAtLoginService
        self.daemonConnection = daemonConnection
        self.contextService = contextService
        self.timerService = timerService
        self.dailyFocusService = dailyFocusService
        self.issueActionsService = issueActionsService
        self.habitsService = habitsService
        self.popoverStatsService = popoverStatsService
        self.hardLimitCountdownService = HardLimitCountdownService()
        self.inactivityPopupCountdownService = HardLimitCountdownService()
        self.diagnosticsService = diagnosticsService
        let windowService = WindowService()
        let statusBarService = StatusBarService()
        self.windowService = windowService
        self.statusBarService = statusBarService
        self.smartPauseService = SmartPauseService(
            preferences: preferences,
            timerController: timerService
        )
        self.breakScreenService = BreakScreenService(
            preferences: preferences,
            timerService: timerService,
            windowService: windowService
        )
        self.appUpdateService = appUpdateService

        self.smartPauseService.setAutomaticResumeHandler { [weak self] snapshot in
            self?.presentSmartPauseResumeNotice(for: snapshot)
        }

        notificationService.configure(
            daemonConnection: daemonConnection,
            onOpenCrona: { [weak statusBarService] in
                statusBarService?.showPopupFromNotification()
            },
            onOpenTUI: { [weak self] in
                self?.openTUI()
            },
            onAdvanceTimer: { [weak timerService, weak statusBarService] expected in
                Task { @MainActor in
                    await timerService?.refresh()
                    guard timerService?.snapshot.readySegmentType == expected else {
                        statusBarService?.showPopupFromNotification()
                        return
                    }
                    _ = try? await timerService?.advanceTimer()
                }
            },
            onFocusInactivity: { [weak self] delivery in
                guard let self else { return false }
                return await self.presentInactivityPopup(for: delivery)
            },
            shouldSilenceAlert: { [weak windowService] kind in
                guard kind.hasPrefix("timer.") else { return false }
                return windowService?.breakScreensVisible == true
                    || windowService?.hardLimitPopupVisible == true
                    || windowService?.inactivityPopupVisible == true
            }
        )

        self.windowService.configure(appState: self)
        self.statusBarService.configure(appState: self)
        appUpdateService.configurePresentation(
            shouldDefer: { [weak self] in
                self?.isUpdatePresentationBlocked ?? false
            },
            willPresent: { [weak windowService] in
                windowService?.beginExternalWindowPresentation()
            },
            didFinish: { [weak windowService] in
                windowService?.endExternalWindowPresentation()
            }
        )
        daemonEventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent else { return }
            Task { @MainActor [weak self] in
                self?.handleDaemonEvent(event)
            }
        }
        daemonConnectObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.alertSettingsService.refresh()
                await self.dayBoundarySettingsService.refresh()
            }
        }
        bindChildChanges()
    }

    isolated deinit {
        if let daemonEventObserver {
            NotificationCenter.default.removeObserver(daemonEventObserver)
        }
        if let daemonConnectObserver {
            NotificationCenter.default.removeObserver(daemonConnectObserver)
        }
        endSessionFallbackTask?.cancel()
        hardLimitPopupDismissTask?.cancel()
        presentationTimer?.invalidate()
    }

    var popoverModel: PopoverViewModel {
        PopoverViewModel(
            screen: popoverScreen,
            connectionState: daemonConnection.connectionState,
            timerSnapshot: timerService.snapshot,
            contextSnapshot: contextService.snapshot,
            lastErrorDescription: daemonConnection.lastErrorDescription
        )
    }

    var popoverScreen: PopoverScreen {
        if hasActiveFocusSession {
            return .active(
                ActiveTimerPopoverModel(
                    presentation: TimerPresentation.from(timerService.snapshot),
                    timerSnapshot: timerService.snapshot,
                    contextSnapshot: contextService.snapshot
                )
            )
        }
        if selectedPopoverTab == .stats {
            return .idle(IdleFocusPopoverModel(issues: [], date: ""))
        }
        if daemonConnection.connectionState == .error || daemonConnection.connectionState == .incompatible {
            return .error(message: daemonConnection.lastErrorDescription ?? "Unable to reach Crona.")
        }
        if daemonConnection.connectionState != .connected {
            return .disconnected
        }
        if let issue = selectedFocusIssue {
            return .startConfig(
                FocusStartConfigModel(
                    issue: issue,
                    state: FocusStartConfigState.defaultState(
                        estimateMinutes: issue.estimateMinutes,
                        workedSeconds: issue.workedSeconds
                    )
                )
            )
        }
        return .idle(
            IdleFocusPopoverModel(
                issues: dailyFocusService.snapshot.issues,
                date: dailyFocusService.snapshot.date
            )
        )
    }

    var hasActiveFocusSession: Bool {
        timerService.snapshot.sessionID != nil
            && timerService.snapshot.state != "idle"
            && timerService.snapshot.state != "disconnected"
    }

    var selectedSettingsDestination: SettingsDestination {
        settingsNavigation.current
    }

    var isUpdatePresentationBlocked: Bool {
        hasActiveFocusSession
            || windowService.breakScreensVisible
            || windowService.hardLimitPopupVisible
            || isEndSessionSheetPresented
            || issueActionEditor != nil
    }

    func start() {
        statusBarService.installIfNeeded()
        notificationService.start()
        launchAtLoginService.refresh()
        daemonConnection.start()
        smartPauseService.start()
        breakScreenService.start()
        appUpdateService.start()
        startPresentationTimer()
    }

    func stop() {
        presentationTimer?.invalidate()
        presentationTimer = nil
        notificationService.stop()
        inactivityPopupCountdownService.cancel()
        smartPauseService.stop()
        breakScreenService.stop()
        appUpdateService.stop()
        daemonConnection.stop()
    }

    private func startPresentationTimer() {
        guard presentationTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcileHardLimitWarningIndicatorPresentation()
                self?.reconcileInactivityPopupPresentation()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        presentationTimer = timer
    }

    func manualReconnect() {
        daemonConnection.manualReconnect()
    }

#if DEBUG
    var isDeveloperPreviewActive: Bool { developerPreviewKind != nil }

    func showDeveloperHardLimitPreview() {
        dismissDeveloperPreviews()
        developerPreviewKind = .hardLimit
        hardLimitPopupSessionID = "developer-preview"
        hardLimitPopupPhase = .decision
        hardLimitPopupExtendChoice = .minutes5
        hardLimitPopupErrorMessage = nil
        hardLimitPopupSuccessModel = nil
        isHardLimitPopupAnimatingIn = true
        windowService.showHardLimitPopup()
    }

    func showDeveloperInactivityPreview() {
        dismissDeveloperPreviews()
        developerPreviewKind = .inactivity
        inactivityPopupSessionID = "developer-preview"
        inactivityPopupPhase = .decision
        inactivityPopupDelivery = nil
        windowService.showInactivityPopup()
    }

    func showDeveloperWarningPreview() {
        dismissDeveloperPreviews()
        hardLimitWarningIndicatorModel = HardLimitWarningIndicatorModel(
            id: "developer-warning",
            kind: .expiry,
            title: "Session Ending",
            remainingText: "10"
        )
        isHardLimitWarningIndicatorAnimatingIn = false
        windowService.showHardLimitWarningIndicator()
        DispatchQueue.main.async {
            self.isHardLimitWarningIndicatorAnimatingIn = true
        }
    }

    func showDeveloperSmartPauseResumePreview() {
        dismissDeveloperPreviews()
        smartPauseResumeNotice = SmartPauseResumeNotice(
            sessionID: "developer-preview",
            resumedAt: Date()
        )
        windowService.showSmartPauseResumeNotice()
    }

    func showDeveloperBreakScreenPreview() {
        dismissDeveloperPreviews()
        developerPreviewKind = .breakScreen
        windowService.showDeveloperBreakScreen()
    }

    func dismissDeveloperPreviews() {
        hardLimitCountdownService.cancel()
        inactivityPopupCountdownService.cancel()
        developerPreviewKind = nil
        hardLimitPopupPhase = nil
        hardLimitPopupSessionID = nil
        hardLimitPopupSuccessModel = nil
        inactivityPopupPhase = nil
        inactivityPopupSessionID = nil
        inactivityPopupDelivery = nil
        hardLimitWarningIndicatorModel = nil
        smartPauseResumeNotice = nil
        clearEndSessionState()
        windowService.dismissDeveloperPreviews()
    }
#endif

    func setSelectedPopoverTab(_ tab: PopoverTab) {
        guard !hasActiveFocusSession else {
            selectedPopoverTab = .now
            return
        }
        selectedPopoverTab = tab

        selectedPopoverTabLayoutRefreshTask?.cancel()
        selectedPopoverTabLayoutRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.statusBarService.refreshPopupLayout(animated: false)
        }
    }

    func setSelectedSettingsDestination(_ destination: SettingsDestination) {
        settingsNavigation.navigate(to: destination)
    }

    func goBackInSettings() {
        settingsNavigation.goBack()
    }

    func goForwardInSettings() {
        settingsNavigation.goForward()
    }

    func openSettings() {
        statusBarService.dismissPopup { [weak self] in
            guard let self, let settingsSceneAction = self.settingsSceneAction else {
                return
            }
            self.windowService.showSettings(openScene: settingsSceneAction)
        }
    }

    func registerSettingsSceneAction(_ action: @escaping () -> Void) {
        settingsSceneAction = action
    }

    func openAbout() {
        setSelectedSettingsDestination(.about)
        openSettings()
    }

    func openUpdates() {
        setSelectedSettingsDestination(.updates)
        openSettings()
    }

    func checkForAppUpdates() {
        statusBarService.dismissPopup(animated: false)
        appUpdateService.checkForUpdates()
    }

    func quitCrona() {
        statusBarService.dismissPopup(animated: false)
        NSApp.terminate(nil)
    }

    func openDocumentation() {
        openExternalURL("https://github.com/webxsid/crona/tree/main/docs")
    }

    func openGitHub() {
        openExternalURL("https://github.com/webxsid/crona")
    }

    func openSupport() {
        openExternalURL("https://github.com/webxsid/crona/discussions")
    }

    private func openExternalURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    func requestStopCrona() {
        statusBarService.dismissPopup(animated: false)
        guard windowService.confirmStopCrona(hasActiveSession: hasActiveFocusSession) else {
            return
        }

        Task {
            do {
                try await daemonConnection.shutdownAndWait()
                NSApp.terminate(nil)
            } catch {
                logger.error("Failed to stop Crona: \(error.localizedDescription, privacy: .private)")
                windowService.showStopCronaError(error.localizedDescription)
            }
        }
    }

    func dismissMenuBarPopup() {
        statusBarService.dismissPopup()
    }

    private func refreshPopupLayoutAfterStateChange() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.statusBarService.refreshPopupLayout()
        }
    }

    func openTUI() {
        windowService.openTUI(using: preferences.preferences.tuiCommand)
    }

    func pauseTimer() {
        Task { _ = try? await timerService.pauseTimer() }
    }

    func resumeTimer() {
        Task { _ = try? await timerService.resumeTimer() }
    }

    func endTimer() {
        beginEndSession(source: .menuPopover)
    }

    func extendTimer() {
        extendTimer(by: nil)
    }

    func extendTimer(by additionalSeconds: Int?) {
        guard let request = buildExtendRequest(additionalSeconds: additionalSeconds) else {
            logger.error("Failed to build extend request: no positive extend value was provided")
            return
        }
        Task {
            do {
                _ = try await daemonConnection.withClient { try await $0.timerExtend(request) }
                await timerService.refresh()
            } catch {
                logger.error("Failed to extend timer: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func chooseHardLimitEnd() {
#if DEBUG
        if developerPreviewKind == .hardLimit {
            hardLimitPopupPhase = .endSession
            endSessionPresentationSource = .hardLimitPopup
            pendingEndSessionID = "developer-preview"
            endSessionCommitMessage = ""
            requestEndSessionFocus()
            windowService.updateHardLimitPopup()
            return
        }
#endif
        hardLimitCountdownService.cancel()
        beginEndSession(source: .hardLimitPopup)
        guard pendingEndSessionID != nil else { return }
        hardLimitPopupErrorMessage = nil
        hardLimitPopupPhase = .endSession
        windowService.updateHardLimitPopup()
        requestEndSessionFocus()
    }

    func chooseInactivityPopupEnd() {
#if DEBUG
        if developerPreviewKind == .inactivity {
            inactivityPopupPhase = .endSession
            endSessionPresentationSource = .inactivityPopup
            pendingEndSessionID = "developer-preview"
            endSessionCommitMessage = ""
            requestEndSessionFocus()
            windowService.updateInactivityPopup()
            return
        }
#endif
        inactivityPopupCountdownService.cancel()
        beginEndSession(source: .inactivityPopup)
        guard pendingEndSessionID != nil else { return }
        inactivityPopupPhase = .endSession
        windowService.updateInactivityPopup()
        requestEndSessionFocus()
    }

    func dismissInactivityPopup() {
#if DEBUG
        if developerPreviewKind == .inactivity {
            dismissDeveloperPreviews()
            return
        }
#endif
        finalizeInactivityPopup()
    }

    func handleHardLimitPopupClose() {
        guard !isSubmittingEndSession, !isSubmittingHardLimitAction else { return }
        chooseHardLimitEnd()
    }

    func dismissSmartPauseResumeNoticeNow() {
        dismissSmartPauseResumeNotice()
    }

    func returnToInactivityDecision() {
        guard !isSubmittingEndSession else { return }
#if DEBUG
        if developerPreviewKind == .inactivity {
            clearEndSessionState()
            inactivityPopupPhase = .decision
            windowService.updateInactivityPopup()
            return
        }
#endif
        clearEndSessionState()
        inactivityPopupPhase = .decision
        startInactivityPopupCountdown()
        windowService.updateInactivityPopup()
    }

    func chooseHardLimitExtend() {
#if DEBUG
        if developerPreviewKind == .hardLimit {
            hardLimitPopupPhase = .extend
            hardLimitPopupExtendChoice = .minutes5
            windowService.updateHardLimitPopup()
            return
        }
#endif
        hardLimitCountdownService.cancel()
        guard let sessionID = timerService.snapshot.sessionID else { return }
        hardLimitPopupSessionID = sessionID
        hardLimitPopupErrorMessage = nil
        hardLimitPopupExtendChoice = defaultExtendChoice(for: timerService.snapshot)
        hardLimitPopupPhase = .extend
        windowService.updateHardLimitPopup()
    }

    func confirmHardLimitExtend() {
#if DEBUG
        if developerPreviewKind == .hardLimit {
            hardLimitPopupPhase = .success
            hardLimitPopupSuccessModel = HardLimitPopupSuccessModel(
                remainingTimeText: "30:00",
                endTimeText: TimerEndTimeFormatter.string(from: Date().addingTimeInterval(1_800))
            )
            windowService.updateHardLimitPopup()
            return
        }
#endif
        guard let sessionID = hardLimitPopupSessionID ?? timerService.snapshot.sessionID else { return }
        guard sessionID == timerService.snapshot.sessionID else {
            hardLimitPopupErrorMessage = "The active session changed. Refresh and try again."
            return
        }

        let request: CronaTimerExtendRequest?
        switch TimerPresentation.from(timerService.snapshot).mode {
        case .pomodoro:
            request = buildPomodoroExtendRequest(choice: hardLimitPopupExtendChoice)
        case .stopwatch, .timer:
            request = Self.buildQuickExtendRequest(snapshot: timerService.snapshot, additionalSeconds: hardLimitPopupExtendChoice.secondsValue)
        }

        guard let request else {
            hardLimitPopupErrorMessage = "No extend option is available."
            return
        }

        isSubmittingHardLimitAction = true
        hardLimitPopupErrorMessage = nil

        Task {
            do {
                _ = try await daemonConnection.withClient { try await $0.timerExtend(request) }
                await timerService.refresh()
                await contextService.refresh()
                await MainActor.run {
                    self.presentExtendSuccess()
                }
            } catch {
                logger.error("Failed to extend timer from popup: \(error.localizedDescription, privacy: .private)")
                await MainActor.run {
                    self.isSubmittingHardLimitAction = false
                    self.hardLimitPopupErrorMessage = error.localizedDescription
                }
            }
        }
    }

    var hardLimitExtensionEndDate: Date? {
#if DEBUG
        if developerPreviewKind == .hardLimit {
            return Date().addingTimeInterval(1_800)
        }
#endif
        let request: CronaTimerExtendRequest?
        switch TimerPresentation.from(timerService.snapshot).mode {
        case .pomodoro:
            request = buildPomodoroExtendRequest(choice: hardLimitPopupExtendChoice)
        case .stopwatch, .timer:
            request = Self.buildQuickExtendRequest(
                snapshot: timerService.snapshot,
                additionalSeconds: hardLimitPopupExtendChoice.secondsValue
            )
        }

        guard let request else { return nil }
        return TimerEndProjection.extensionEndDate(
            snapshot: timerService.snapshot,
            request: request
        )
    }

    func returnToHardLimitDecision() {
        guard !isSubmittingEndSession, !isSubmittingHardLimitAction else { return }
#if DEBUG
        if developerPreviewKind == .hardLimit {
            clearEndSessionState()
            hardLimitPopupErrorMessage = nil
            hardLimitPopupPhase = .decision
            windowService.updateHardLimitPopup()
            return
        }
#endif
        clearEndSessionState()
        hardLimitPopupErrorMessage = nil
        hardLimitPopupPhase = .decision
        startHardLimitDecisionCountdown()
        windowService.updateHardLimitPopup()
    }

    func selectFocusIssue(_ issue: DailyFocusIssue) {
        selectedFocusIssue = issue
    }

    func dismissStartConfig() {
        selectedFocusIssue = nil
    }

    func requestIssueStatusChange(
        issue: DailyFocusIssue,
        status: CronaIssueStatus
    ) {
        issueActionsService.clearError()
        guard status.notePrompt != nil else {
            Task {
                _ = await issueActionsService.changeStatus(
                    issue: issue,
                    status: status,
                    note: nil
                )
            }
            return
        }
        issueActionNote = ""
        issueActionEditor = .status(issue: issue, status: status)
        refreshPopupLayoutAfterStateChange()
    }

    func setIssueDueDate(_ issue: DailyFocusIssue, date: String) {
        issueActionsService.clearError()
        Task {
            _ = await issueActionsService.setDueDate(issue: issue, date: date)
        }
    }

    func clearIssueDueDate(_ issue: DailyFocusIssue) {
        issueActionsService.clearError()
        Task {
            _ = await issueActionsService.clearDueDate(issue: issue)
        }
    }

    func presentCustomDueDate(for issue: DailyFocusIssue) {
        issueActionsService.clearError()
        let initialValue = issue.todoForDate ?? dailyFocusService.snapshot.date
        issueActionDate = CronaCalendarDate.date(from: initialValue) ?? Date()
        issueActionEditor = .dueDate(issue: issue)
        refreshPopupLayoutAfterStateChange()
    }

    func cancelIssueActionEditor() {
        guard issueActionsService.actionInFlightIssueID == nil else { return }
        issueActionEditor = nil
        issueActionNote = ""
        refreshPopupLayoutAfterStateChange()
    }

    func submitIssueActionEditor() {
        guard let editor = issueActionEditor else { return }
        switch editor {
        case let .status(issue, status):
            let trimmedNote = issueActionNote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !status.requiresNote || !trimmedNote.isEmpty else {
                return
            }
            Task {
                let succeeded = await issueActionsService.changeStatus(
                    issue: issue,
                    status: status,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                )
                if succeeded {
                    issueActionEditor = nil
                    issueActionNote = ""
                    refreshPopupLayoutAfterStateChange()
                }
            }
        case let .dueDate(issue):
            let date = CronaCalendarDate.string(from: issueActionDate)
            Task {
                let succeeded = await issueActionsService.setDueDate(issue: issue, date: date)
                if succeeded {
                    issueActionEditor = nil
                    refreshPopupLayoutAfterStateChange()
                }
            }
        }
    }

    func beginEndSession(source: EndSessionPresentationSource) {
        guard let sessionID = timerService.snapshot.sessionID else {
            logger.error("Cannot present end session flow without an active session")
            return
        }
        logger.debug("Presenting end session flow from \(String(describing: source), privacy: .public)")
        pendingEndSessionID = sessionID
        endSessionPresentationSource = source
        endSessionCommitMessage = ""
        endSessionErrorMessage = nil
        isEndSessionSheetPresented = source == .menuPopover
        requestEndSessionFocus()
        refreshPopupLayoutAfterStateChange()
    }

    func cancelEndSession() {
        guard !isSubmittingEndSession else { return }
        endSessionFallbackTask?.cancel()
        endSessionFallbackTask = nil
        isEndSessionSheetPresented = false
        clearEndSessionState()
        refreshPopupLayoutAfterStateChange()
    }

    func confirmEndSession() {
        let trimmedMessage = endSessionCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            endSessionErrorMessage = "A commit message is required."
            return
        }
#if DEBUG
        if isDeveloperPreviewActive {
            dismissDeveloperPreviews()
            return
        }
#endif
        guard let sessionID = pendingEndSessionID, sessionID == timerService.snapshot.sessionID else {
            endSessionErrorMessage = "The active session changed. Refresh and try again."
            return
        }

        isSubmittingEndSession = true
        endSessionErrorMessage = nil

        Task {
            do {
                _ = try await daemonConnection.withClient { try await $0.timerEnd(commitMessage: trimmedMessage) }
                await MainActor.run {
                    self.startEndSessionFallback(for: sessionID)
                }
            } catch {
                logger.error("Failed to end timer: \(error.localizedDescription, privacy: .private)")
                await MainActor.run {
                    self.isSubmittingEndSession = false
                    self.endSessionErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func startSelectedFocusSession(using config: FocusStartConfigState) {
        guard let issue = selectedFocusIssue else { return }
        let request = config.startRequest(for: issue)
        Task {
            do {
                _ = try await daemonConnection.withClient { try await $0.timerStart(request) }
                await timerService.refresh()
                await contextService.refresh()
                await dailyFocusService.refresh()
                await habitsService.refresh()
                selectedFocusIssue = nil
            } catch {
                logger.error("Failed to start focus session: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func completeHabit(_ habit: HabitRowModel) {
        Task { await habitsService.complete(habit) }
    }

    func logHabit(_ habit: HabitRowModel, durationMinutes: Int) {
        Task {
            await habitsService.complete(
                habit,
                durationMinutes: max(1, durationMinutes)
            )
        }
    }

    func failHabit(_ habit: HabitRowModel) {
        Task { await habitsService.fail(habit) }
    }

    func clearHabitCompletion(_ habit: HabitRowModel) {
        Task { await habitsService.clearCompletion(habit) }
    }

    func requestNotificationAuthorization() {
        Task { await notificationService.requestAuthorization() }
    }

    func sendTestNotification() {
        Task { await daemonConnection.sendTestNotification() }
    }

    func sendTestSound() {
        Task {
            do {
                _ = try await daemonConnection.withClient { client in
                    try await client.alertsTestSound()
                }
            } catch {
                daemonConnection.lastErrorDescription = error.localizedDescription
            }
        }
    }

    private func bindChildChanges() {
        preferences.$preferences
            .map(\.hideDockIconWhenNoWindowsOpen)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.windowService.refreshApplicationActivationPolicy()
            }
            .store(in: &cancellables)

        dailyFocusService.$snapshot
            .map(\.issues)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] issues in
                self?.issueActionsService.synchronize(issues: issues)
            }
            .store(in: &cancellables)

        timerService.$snapshot
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                let isActive = snapshot.sessionID != nil
                    && snapshot.state != "idle"
                    && snapshot.state != "disconnected"
                if isActive, self.selectedPopoverTab != .now {
                    self.selectedPopoverTab = .now
                }
                self.statusBarService.refreshPopupLayout()
            }
            .store(in: &cancellables)

        [
            preferences.objectWillChange.eraseToAnyPublisher(),
            kernelDiscovery.objectWillChange.eraseToAnyPublisher(),
            notificationService.objectWillChange.eraseToAnyPublisher(),
            launchAtLoginService.objectWillChange.eraseToAnyPublisher(),
            daemonConnection.objectWillChange.eraseToAnyPublisher(),
            diagnosticsService.objectWillChange.eraseToAnyPublisher(),
            timerService.objectWillChange.eraseToAnyPublisher(),
            contextService.objectWillChange.eraseToAnyPublisher(),
            dailyFocusService.objectWillChange.eraseToAnyPublisher(),
            issueActionsService.objectWillChange.eraseToAnyPublisher(),
            habitsService.objectWillChange.eraseToAnyPublisher(),
            popoverStatsService.objectWillChange.eraseToAnyPublisher(),
            breakScreenService.objectWillChange.eraseToAnyPublisher(),
            appUpdateService.objectWillChange.eraseToAnyPublisher()
        ]
        .forEach { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                    self?.statusBarService.updateStatusItem()
                    self?.reconcileEndSessionPresentation()
                    self?.reconcileHardLimitPopupPresentation()
                    self?.reconcileHardLimitWarningIndicatorPresentation()
                    self?.reconcileInactivityPopupPresentation()
                }
                .store(in: &cancellables)
        }
    }

    private func handleDaemonEvent(_ event: CronaProtocolEvent) {
        switch event.type {
        case "day.start":
            handleDayStart(event)
        case "timer.hard_limit_reached":
            handleHardLimitReached(event)
        case "timer.extended":
            handleTimerExtended(event)
        case "session.ended":
            guard let sessionID = event.sessionID else { return }
            finalizeEndSessionIfNeeded(for: sessionID)
        default:
            break
        }
    }

    private func handleDayStart(_ event: CronaProtocolEvent) {
        guard let payload = try? event.decodePayload(CronaDayBoundaryEventPayload.self),
              !payload.logicalDate.isEmpty
        else {
            logger.error("Ignoring malformed day.start event")
            return
        }

        let previousDate = daemonConnection.currentDate
        guard daemonConnection.applyDayBoundary(payload) else { return }
        let date = payload.logicalDate
        Task { @MainActor [weak self] in
            guard let self else { return }
            await dailyFocusService.refresh(date: date)
            await habitsService.refresh(date: date)
            await popoverStatsService.handleDayStart(date: date, previousDate: previousDate)
            statusBarService.updateStatusItem()
        }
    }

    private func buildExtendRequest(additionalSeconds: Int?) -> CronaTimerExtendRequest? {
        Self.buildQuickExtendRequest(snapshot: timerService.snapshot, additionalSeconds: additionalSeconds)
    }

    static func buildQuickExtendRequest(snapshot: TimerSnapshot, additionalSeconds: Int?) -> CronaTimerExtendRequest? {
        guard let additionalSeconds, additionalSeconds > 0 else {
            return nil
        }

        return CronaTimerExtendRequest(
            additionalSeconds: additionalSeconds,
            additionalSessions: 0,
            hardLimitTotalSeconds: nil,
            hardLimitWorkSeconds: nil,
            hardLimitBreakSeconds: nil,
            hardLimitLongBreakSeconds: nil,
            hardLimitCyclesBeforeLongBreak: nil
        )
    }

    private func startEndSessionFallback(for sessionID: String) {
        endSessionFallbackTask?.cancel()
        endSessionFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            guard self.isSubmittingEndSession, self.pendingEndSessionID == sessionID else { return }

            await self.timerService.refresh()
            await self.contextService.refresh()
            await self.dailyFocusService.refresh()
            await self.habitsService.refresh()
            await self.popoverStatsService.refresh()

            if self.timerService.snapshot.sessionID != sessionID {
                self.finalizeEndSessionUI()
            } else {
                self.isSubmittingEndSession = false
                self.endSessionErrorMessage = "The session end was sent, but confirmation did not arrive. Refresh and try again."
            }
        }
    }

    private func finalizeEndSessionIfNeeded(for sessionID: String) {
        guard let pendingEndSessionID, pendingEndSessionID == sessionID else {
            if hardLimitPopupSessionID == sessionID {
                finalizeHardLimitPopup()
            }
            if inactivityPopupSessionID == sessionID {
                finalizeInactivityPopup()
            }
            return
        }
        finalizeEndSessionUI()
    }

    private func finalizeEndSessionUI() {
        endSessionFallbackTask?.cancel()
        endSessionFallbackTask = nil
        isSubmittingEndSession = false
        isEndSessionSheetPresented = false
        clearEndSessionState()
        refreshPopupLayoutAfterStateChange()
        selectedFocusIssue = nil
        if hardLimitPopupSessionID != nil {
            finalizeHardLimitPopup()
        }
        if inactivityPopupSessionID != nil {
            finalizeInactivityPopup()
        }
    }

    private func reconcileEndSessionPresentation() {
        guard isEndSessionSheetPresented else { return }

        if let pendingEndSessionID, timerService.snapshot.sessionID != pendingEndSessionID {
            finalizeEndSessionUI()
        }
    }

    private func handleHardLimitReached(_ event: CronaProtocolEvent) {
        logger.debug("Handling hard limit popup for session: \(event.sessionID ?? "nil", privacy: .private(mask: .hash))")
        Task { [self] in
            await timerService.refresh()
            await contextService.refresh()
            await MainActor.run {
                guard preferences.preferences.showHardLimitActionPopups else { return }
                guard timerService.snapshot.sessionID != nil else { return }
                guard timerService.snapshot.hardLimitActive, timerService.snapshot.hardLimitExpired else { return }

                finalizeHardLimitWarningIndicator()
                hardLimitPopupDismissTask?.cancel()
                hardLimitPopupDismissTask = nil
                hardLimitPopupSessionID = timerService.snapshot.sessionID
                hardLimitPopupPhase = .decision
                hardLimitPopupExtendChoice = defaultExtendChoice(for: timerService.snapshot)
                hardLimitPopupErrorMessage = nil
                hardLimitPopupSuccessModel = nil
                isSubmittingHardLimitAction = false
                isHardLimitPopupAnimatingIn = false
                startHardLimitDecisionCountdown()
                windowService.showHardLimitPopup()
                DispatchQueue.main.async {
                    self.isHardLimitPopupAnimatingIn = true
                }
            }
        }
    }

    private func handleTimerExtended(_ event: CronaProtocolEvent) {
        guard let sessionID = hardLimitPopupSessionID, sessionID == event.sessionID || event.sessionID == nil else { return }
        Task {
            await timerService.refresh()
            await contextService.refresh()
            await MainActor.run {
                presentExtendSuccess()
            }
        }
    }

    private func presentInactivityPopup(for delivery: CronaAlertDelivery) async -> Bool {
        guard preferences.preferences.showInactivityActionPopups else { return false }

        await timerService.refresh()
        await contextService.refresh()

        guard preferences.preferences.showInactivityActionPopups else { return false }
        guard timerService.snapshot.sessionID != nil else { return false }
        guard timerService.snapshot.state == "running" else { return false }
        guard !timerService.snapshot.hardLimitExpired else { return false }

        inactivityPopupCountdownService.cancel()
        inactivityPopupDelivery = delivery
        inactivityPopupSessionID = timerService.snapshot.sessionID
        inactivityPopupPhase = .decision
        startInactivityPopupCountdown()
        windowService.showInactivityPopup()

        return true
    }

    private func reconcileHardLimitPopupPresentation() {
        guard let phase = hardLimitPopupPhase else { return }

        guard daemonConnection.connectionState == .connected else {
            finalizeHardLimitPopup()
            return
        }

        guard let sessionID = hardLimitPopupSessionID ?? timerService.snapshot.sessionID else {
            finalizeHardLimitPopup()
            return
        }

        if timerService.snapshot.sessionID != sessionID, phase != .success {
            finalizeHardLimitPopup()
            return
        }

        windowService.updateHardLimitPopup()
    }

    private func reconcileInactivityPopupPresentation() {
        guard inactivityPopupPhase != nil else { return }

        if isInactivityDeveloperPreviewActive {
            windowService.updateInactivityPopup()
            return
        }

        guard preferences.preferences.showInactivityActionPopups else {
            finalizeInactivityPopup()
            return
        }

        guard daemonConnection.connectionState == .connected else {
            finalizeInactivityPopup()
            return
        }

        guard let sessionID = inactivityPopupSessionID else {
            finalizeInactivityPopup()
            return
        }

        guard timerService.snapshot.sessionID == sessionID else {
            finalizeInactivityPopup()
            return
        }

        windowService.updateInactivityPopup()
    }

    private var isInactivityDeveloperPreviewActive: Bool {
#if DEBUG
        developerPreviewKind == .inactivity
#else
        false
#endif
    }

    private func reconcileHardLimitWarningIndicatorPresentation() {
        guard preferences.preferences.showHardLimitWarningIndicator else {
            finalizeHardLimitWarningIndicator()
            return
        }

        guard daemonConnection.connectionState == .connected else {
            finalizeHardLimitWarningIndicator()
            return
        }

        let snapshot = timerService.snapshot
        guard snapshot.sessionID != nil, snapshot.state == "running", snapshot.hardLimitActive, !snapshot.hardLimitExpired else {
            finalizeHardLimitWarningIndicator()
            return
        }

        guard let model = buildHardLimitWarningIndicatorModel(snapshot: snapshot) else {
            finalizeHardLimitWarningIndicator()
            return
        }

        if lastWarningIndicatorKey != model.id {
            lastWarningIndicatorKey = model.id
        }
        if hardLimitWarningIndicatorModel != model {
            hardLimitWarningIndicatorModel = model
        }
        if !windowService.hardLimitWarningIndicatorVisible {
            isHardLimitWarningIndicatorAnimatingIn = false
            windowService.showHardLimitWarningIndicator()
            DispatchQueue.main.async {
                self.isHardLimitWarningIndicatorAnimatingIn = true
            }
        }
    }

    private func presentExtendSuccess() {
        hardLimitCountdownService.cancel()
        let presentation = TimerPresentation.from(timerService.snapshot)
        let timeFormatter = MenuBarTextFormatter.formatClock(
            seconds: presentation.displaySeconds
        )
        let endTimeText: String
        if let endDate = TimerEndProjection.activeEndDate(snapshot: timerService.snapshot) {
            endTimeText = TimerEndTimeFormatter.string(from: endDate)
        } else {
            endTimeText = "Now"
        }

        hardLimitPopupPhase = .success
        hardLimitPopupSuccessModel = HardLimitPopupSuccessModel(
            remainingTimeText: timeFormatter,
            endTimeText: endTimeText
        )
        hardLimitPopupErrorMessage = nil
        isSubmittingHardLimitAction = false
        windowService.updateHardLimitPopup()

        hardLimitPopupDismissTask?.cancel()
        hardLimitPopupDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            self?.finalizeHardLimitPopup()
        }
    }

    private func finalizeHardLimitPopup() {
        hardLimitCountdownService.cancel()
        hardLimitPopupDismissTask?.cancel()
        hardLimitPopupDismissTask = nil
        isHardLimitPopupAnimatingIn = false
        windowService.closeHardLimitPopup { [weak self] in
            guard let self else { return }
            self.hardLimitPopupPhase = nil
            self.hardLimitPopupSessionID = nil
            self.hardLimitPopupExtendChoice = .defaultValue
            self.hardLimitPopupErrorMessage = nil
            self.hardLimitPopupSuccessModel = nil
            self.isSubmittingHardLimitAction = false
        }
    }

    private func finalizeInactivityPopup() {
        inactivityPopupCountdownService.cancel()
        inactivityPopupPhase = nil
        inactivityPopupDelivery = nil
        inactivityPopupSessionID = nil
        if endSessionPresentationSource == .inactivityPopup {
            clearEndSessionState()
        }
        windowService.closeInactivityPopup()
    }

    private func presentSmartPauseResumeNotice(for snapshot: TimerSnapshot) {
        guard let sessionID = snapshot.sessionID else { return }

        smartPauseResumeNoticeDismissTask?.cancel()
        smartPauseResumeNotice = SmartPauseResumeNotice(
            sessionID: sessionID,
            resumedAt: Date()
        )
        windowService.showSmartPauseResumeNotice()

        smartPauseResumeNoticeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismissSmartPauseResumeNotice()
        }
    }

    func dismissSmartPauseResumeNotice() {
        smartPauseResumeNoticeDismissTask?.cancel()
        smartPauseResumeNoticeDismissTask = nil
        smartPauseResumeNotice = nil
        windowService.closeSmartPauseResumeNotice()
    }

    private func finalizeHardLimitWarningIndicator() {
        guard hardLimitWarningIndicatorModel != nil
            || windowService.hardLimitWarningIndicatorVisible
        else {
            return
        }
        isHardLimitWarningIndicatorAnimatingIn = false
        windowService.closeHardLimitWarningIndicator { [weak self] in
            guard let self else { return }
            self.hardLimitWarningIndicatorModel = nil
            self.lastWarningIndicatorKey = nil
        }
    }

    private func clearEndSessionState() {
        pendingEndSessionID = nil
        endSessionPresentationSource = nil
        endSessionCommitMessage = ""
        endSessionErrorMessage = nil
        isSubmittingEndSession = false
    }

    private func requestEndSessionFocus() {
        endSessionFocusRequest &+= 1
    }

    private func startHardLimitDecisionCountdown() {
        hardLimitCountdownService.start { [weak self] in
            guard let self, self.hardLimitPopupPhase == .decision else { return }
            self.chooseHardLimitEnd()
        }
    }

    private func startInactivityPopupCountdown() {
        inactivityPopupCountdownService.start(duration: InactivityPopupConfiguration.autoDismissDuration) { [weak self] in
            guard let self, self.inactivityPopupPhase == .decision else { return }
            self.finalizeInactivityPopup()
        }
    }

    private func defaultExtendChoice(for snapshot: TimerSnapshot) -> HardLimitExtendChoice {
        switch TimerPresentation.from(snapshot).mode {
        case .pomodoro:
            return .session1
        case .stopwatch, .timer:
            return .minutes5
        }
    }

    private func buildPomodoroExtendRequest(choice: HardLimitExtendChoice) -> CronaTimerExtendRequest? {
        guard let sessions = choice.sessionValue, sessions > 0 else { return nil }
        return CronaTimerExtendRequest(
            additionalSeconds: 0,
            additionalSessions: sessions,
            hardLimitTotalSeconds: max(1, timerService.snapshot.hardLimitTotalSeconds),
            hardLimitWorkSeconds: max(1, timerService.snapshot.hardLimitWorkSeconds),
            hardLimitBreakSeconds: max(0, timerService.snapshot.hardLimitBreakSeconds),
            hardLimitLongBreakSeconds: max(0, timerService.snapshot.hardLimitLongBreakSeconds),
            hardLimitCyclesBeforeLongBreak: max(0, timerService.snapshot.hardLimitCyclesBeforeLongBreak)
        )
    }

    private func buildHardLimitWarningIndicatorModel(snapshot: TimerSnapshot) -> HardLimitWarningIndicatorModel? {
        let leadSeconds = CompanionPreferences.normalizedHardLimitWarningLeadSeconds(
            preferences.preferences.hardLimitWarningLeadSeconds
        )
        let presentation = TimerPresentation.from(snapshot)
        let remainingSeconds = max(0, presentation.displaySeconds)
        guard remainingSeconds > 0, remainingSeconds <= leadSeconds else { return nil }

        let sessionID = snapshot.sessionID ?? "unknown"
        if
            presentation.mode == .pomodoro,
            let currentSegment = TimerSegmentKind(rawValue: snapshot.segmentType),
            let nextSegment = TimerSegmentKind(rawValue: snapshot.nextSegmentType),
            currentSegment != nextSegment
        {
            let kind: HardLimitWarningKind
            let title: String

            if currentSegment.isBreak, nextSegment == .work {
                kind = .resume
                title = "Focus Resumes"
            } else if currentSegment == .work, nextSegment.isBreak {
                kind = .breakStart
                title = "Break Starting"
            } else {
                return nil
            }

            let id = "\(sessionID):\(kind.rawValue):\(snapshot.segmentType ?? "unknown"):\(snapshot.nextSegmentType ?? "unknown")"
            return HardLimitWarningIndicatorModel(
                id: id,
                kind: kind,
                title: title,
                remainingText: String(format: "%02d", remainingSeconds)
            )
        }

        let id = "\(sessionID):expiry:\(snapshot.segmentType ?? "unknown")"
        return HardLimitWarningIndicatorModel(
            id: id,
            kind: .expiry,
            title: "Session Ending",
            remainingText: String(format: "%02d", remainingSeconds)
        )
    }
}

enum HardLimitPopupPhase: Equatable {
    case decision
    case endSession
    case extend
    case success
}

enum InactivityPopupPhase: Equatable {
    case decision
    case endSession
}

enum InactivityPopupConfiguration {
    static let autoDismissDuration: TimeInterval = 60
}

enum HardLimitExtendChoice: String, CaseIterable, Identifiable, Equatable {
    case minutes1
    case minutes5
    case minutes15
    case session1
    case session2

    static let defaultValue: HardLimitExtendChoice = .minutes5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes1: return "+1 min"
        case .minutes5: return "+5 min"
        case .minutes15: return "+15 min"
        case .session1: return "+1 session"
        case .session2: return "+2 sessions"
        }
    }

    var secondsValue: Int? {
        switch self {
        case .minutes1: return 60
        case .minutes5: return 300
        case .minutes15: return 900
        case .session1, .session2: return nil
        }
    }

    var sessionValue: Int? {
        switch self {
        case .session1: return 1
        case .session2: return 2
        case .minutes1, .minutes5, .minutes15: return nil
        }
    }
}

struct HardLimitPopupSuccessModel: Equatable {
    let remainingTimeText: String
    let endTimeText: String
}

enum HardLimitWarningKind: String, Equatable {
    case expiry
    case breakStart
    case resume

    var symbolName: String {
        switch self {
        case .expiry:
            return "hourglass.circle.fill"
        case .breakStart:
            return "cup.and.saucer.fill"
        case .resume:
            return "bolt.fill"
        }
    }

    var tint: NSColor {
        switch self {
        case .expiry:
            return .systemOrange
        case .breakStart:
            return .systemPink
        case .resume:
            return .systemYellow
        }
    }
}

struct HardLimitWarningIndicatorModel: Equatable {
    let id: String
    let kind: HardLimitWarningKind
    let title: String
    let remainingText: String
}
