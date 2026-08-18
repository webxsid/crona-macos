import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI

enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
    case general
    case away
    case menuBar
    case daySchedule
    case smartPause
    case breakScreen
    case notifications
    case advanced
    case about
#if DEBUG
    case developer
#endif

    var id: String { rawValue }
}

enum EndSessionPresentationSource: Equatable {
    case menuPopover
    case timerHUD
    case hardLimitPopup
    case inactivityPopup
}

enum IssueActionEditor: Equatable {
    case status(issue: DailyFocusIssue, status: CronaIssueStatus)
    case dueDate(issue: DailyFocusIssue)
    case manualSession(issue: DailyFocusIssue)
    case delete(issue: DailyFocusIssue)
}

struct SmartPauseResumeNotice: Equatable {
    let sessionID: String
    let resumedAt: Date
}

struct IssueCreationSuccess: Equatable {
    let issue: DailyFocusIssue
    let plannedForToday: Bool
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
    let coreSettingsService: CoreSettingsService
    let launchAtLoginService: LaunchAtLoginService
    let daemonConnection: DaemonConnectionService
    let diagnosticsService: DiagnosticsService
    let timerService: TimerService
    let contextService: ContextService
    let dailyFocusService: DailyFocusService
    let issueActionsService: IssueActionsService
    let issueCreationService: IssueCreationService
    let habitsService: HabitsService
    let wellbeingService: WellbeingService
    let popoverStatsService: PopoverStatsService
    let hardLimitCountdownService: HardLimitCountdownService
    let inactivityPopupCountdownService: HardLimitCountdownService
    let windowService: WindowService
    let statusBarService: StatusBarService
    let settingsShortcutService: SettingsShortcutService
    let smartPauseService: SmartPauseService
    let breakScreenService: BreakScreenService
    let userActivityMonitor: UserActivityMonitor
    let appUpdateService: AppUpdateService
    private var cancellables: Set<AnyCancellable> = []
    private var daemonEventObserver: NSObjectProtocol?
    private var daemonConnectObserver: NSObjectProtocol?
    private var endSessionFallbackTask: Task<Void, Never>?
    private var hardLimitPopupDismissTask: Task<Void, Never>?
    private var smartPauseResumeNoticeDismissTask: Task<Void, Never>?
    private var issueCreationSuccessDismissTask: Task<Void, Never>?
    private var presentationTimer: Timer?
    private var lastWarningIndicatorKey: String?
    private var settingsSceneAction: (() -> Void)?
    @Published var selectedFocusIssue: DailyFocusIssue?
    @Published var issueActionEditor: IssueActionEditor?
    @Published var issueActionNote = ""
    @Published var issueActionDate = Date()
    @Published var manualSessionSummary = ""
    @Published var manualSessionDate = ""
    @Published var manualSessionWorkHours = 1
    @Published var manualSessionWorkMinutes = 0
    @Published var manualSessionBreakHours = 0
    @Published var manualSessionBreakMinutes = 0
    @Published var manualSessionTimesEnabled = false
    @Published var manualSessionStartHour = 9
    @Published var manualSessionStartMinute = 0
    @Published var manualSessionStartPeriod = "AM"
    @Published var manualSessionEndHour = 10
    @Published var manualSessionEndMinute = 45
    @Published var manualSessionEndPeriod = "AM"
    @Published var manualSessionNotes = ""
    @Published var manualSessionError: String?
    @Published var isIssueCreatorPresented = false
    @Published var isIssueCreatorContentVisible = false
    @Published var issueCreateTitle = ""
    @Published var issueCreateDescription = ""
    @Published var issueCreateEstimate = ""
    @Published var issueCreateForToday = true
    @Published var issueCreateDestinationID: Int64?
    @Published var issueCreateShowsMoreOptions = false
    @Published private(set) var issueBeingEdited: DailyFocusIssue?
    private var issueCreatorPresentationGeneration: UInt = 0
    @Published var issueCreationSuccess: IssueCreationSuccess?
    @Published var selectedPopoverTab: PopoverTab = .now
    @Published var isStatsCalendarPresented = false
    @Published private(set) var selectedSettingsDestination: SettingsDestination = .general
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
        let issueCreationService = IssueCreationService(daemonConnection: daemonConnection)
        let habitsService = HabitsService(daemonConnection: daemonConnection)
        let wellbeingService = WellbeingService(daemonConnection: daemonConnection)
        let popoverStatsService = PopoverStatsService(daemonConnection: daemonConnection)
        let diagnosticsService = DiagnosticsService(
            daemonConnection: daemonConnection,
            kernelDiscovery: kernelDiscovery
        )
        let alertSettingsService = AlertSettingsService(daemonConnection: daemonConnection)
        let dayBoundarySettingsService = DayBoundarySettingsService(daemonConnection: daemonConnection)
        let coreSettingsService = CoreSettingsService(daemonConnection: daemonConnection)
        let appUpdateService = AppUpdateService(preferences: preferences)
        let userActivityMonitor = UserActivityMonitor()

        self.preferences = preferences
        self.kernelDiscovery = kernelDiscovery
        self.notificationService = notificationService
        self.alertSettingsService = alertSettingsService
        self.dayBoundarySettingsService = dayBoundarySettingsService
        self.coreSettingsService = coreSettingsService
        self.userActivityMonitor = userActivityMonitor
        self.launchAtLoginService = launchAtLoginService
        self.daemonConnection = daemonConnection
        self.contextService = contextService
        self.timerService = timerService
        self.dailyFocusService = dailyFocusService
        self.issueActionsService = issueActionsService
        self.issueCreationService = issueCreationService
        self.habitsService = habitsService
        self.wellbeingService = wellbeingService
        self.popoverStatsService = popoverStatsService
        self.hardLimitCountdownService = HardLimitCountdownService()
        self.inactivityPopupCountdownService = HardLimitCountdownService()
        self.diagnosticsService = diagnosticsService
        let windowService = WindowService()
        let statusBarService = StatusBarService()
        let settingsShortcutService = SettingsShortcutService()
        self.windowService = windowService
        self.statusBarService = statusBarService
        self.settingsShortcutService = settingsShortcutService
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
            },
            breakDeferralSeconds: { [weak preferences, weak userActivityMonitor] in
                guard let preferences, let userActivityMonitor else { return nil }
                return BreakDeferralPolicy.seconds(
                    preferences: preferences.preferences,
                    recentlyActive: userActivityMonitor.isRecentlyActive
                        || userActivityMonitor.fallbackRecentlyActive()
                )
            }
        )

        self.windowService.configure(appState: self)
        self.statusBarService.configure(appState: self)
        self.settingsShortcutService.configure(appState: self)
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
                await self.coreSettingsService.refresh()
                await self.wellbeingService.refresh()
                await self.timerService.refresh()
                await self.contextService.refresh()
                await self.dailyFocusService.refresh(date: self.daemonConnection.currentDate)
                await self.habitsService.refresh(date: self.daemonConnection.currentDate)
                await self.popoverStatsService.refresh()
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

    var todayIsAway: Bool { coreSettingsService.todayIsAway }

    func setAwayMode(_ enabled: Bool) {
        Task { await coreSettingsService.setAwayMode(enabled) }
    }

    var hasActiveFocusSession: Bool {
        timerService.snapshot.sessionID != nil
            && timerService.snapshot.state != "idle"
            && timerService.snapshot.state != "disconnected"
    }

    var isUpdatePresentationBlocked: Bool {
        hasActiveFocusSession
            || windowService.breakScreensVisible
            || windowService.hardLimitPopupVisible
            || isEndSessionSheetPresented
            || issueActionEditor != nil
            || isIssueCreatorPresented
    }

    func start() {
        notificationService.start()
        userActivityMonitor.start()
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
        userActivityMonitor.stop()
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

        if tab == .wellbeing {
            Task { await wellbeingService.refresh() }
        }

    }

    func resetPopoverPresentation() {
        selectedPopoverTab = .now
        if isStatsCalendarPresented {
            isStatsCalendarPresented = false
            popoverStatsService.endCalendar()
        }
    }

    func setSelectedSettingsDestination(_ destination: SettingsDestination) {
        selectedSettingsDestination = destination
    }

    func openSettings() {
        statusBarService.dismissPopup { [weak self] in
            guard let self, let settingsSceneAction = self.settingsSceneAction else {
                return
            }
            self.windowService.showSettings(openScene: settingsSceneAction)
        }
    }

    func presentPrimarySurfaceWhenNoWindowIsActive() {
        guard hardLimitPopupPhase == nil, !windowService.hardLimitPopupVisible else { return }
        if preferences.preferences.showMenuBarItem {
            statusBarService.showPopupFromApplicationLaunch()
        } else {
            openSettings()
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
        setSelectedSettingsDestination(.about)
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

    func openFeedbackAndRoadmap() {
        openExternalURL("https://crona.userjot.com/?cursor=1&order=top&limit=10")
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

    func openTUI() {
        windowService.openTUI(using: preferences.preferences.tuiCommand)
    }

    func pauseTimer() {
        Task { _ = try? await timerService.pauseTimer() }
    }

    func resumeTimer() {
        Task { _ = try? await timerService.resumeTimer() }
    }

    func advanceTimer() {
        Task { _ = try? await timerService.advanceTimer() }
    }

    func endTimer() {
        beginEndSession(source: .menuPopover)
    }

    func endTimerFromHUD() {
        beginEndSession(source: .timerHUD)
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.endSessionPresentationSource == .timerHUD else { return }
            self.windowService.setTimerHUDCommitPresented(true)
        }
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

    func presentIssueCreator() {
        guard daemonConnection.connectionState == .connected,
              !isEndSessionSheetPresented,
              issueActionEditor == nil
        else { return }
        issueCreationService.clearError()
        issueBeingEdited = nil
        issueCreateTitle = ""
        issueCreateDescription = ""
        issueCreateEstimate = ""
        issueCreateForToday = true
        issueCreateDestinationID = contextService.snapshot.streamID
        issueCreateShowsMoreOptions = false
        isIssueCreatorContentVisible = false
        isIssueCreatorPresented = true
        issueCreatorPresentationGeneration &+= 1
        let presentationGeneration = issueCreatorPresentationGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  self.isIssueCreatorPresented,
                  presentationGeneration == self.issueCreatorPresentationGeneration
            else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.isIssueCreatorContentVisible = true
            }
        }
        Task {
            await issueCreationService.loadDestinations()
            if !issueCreationService.destinations.contains(where: { $0.streamID == issueCreateDestinationID }) {
                issueCreateDestinationID = nil
            }
        }
    }

    func presentIssueEditor(for issue: DailyFocusIssue) {
        guard daemonConnection.connectionState == .connected,
              !isEndSessionSheetPresented,
              issueActionEditor == nil,
              !isIssueCreatorPresented
        else { return }
        issueCreationService.clearError()
        issueBeingEdited = issue
        issueCreateTitle = issue.title
        issueCreateDescription = ""
        issueCreateEstimate = issue.estimateMinutes.map(String.init) ?? ""
        issueCreateForToday = issue.todoForDate == dailyFocusService.snapshot.date
        issueCreateDestinationID = issue.streamID
        issueCreateShowsMoreOptions = false
        isIssueCreatorContentVisible = false
        isIssueCreatorPresented = true
        issueCreatorPresentationGeneration &+= 1
        let generation = issueCreatorPresentationGeneration
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.isIssueCreatorPresented,
                  generation == self.issueCreatorPresentationGeneration else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.isIssueCreatorContentVisible = true
            }
        }
    }

    func cancelIssueCreator() {
        guard !issueCreationService.isCreating else { return }
        issueCreationService.clearError()
        issueBeingEdited = nil
        dismissIssueCreatorPresentation()
    }

    func submitIssueCreator() {
        let title = issueCreateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = issueCreateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let estimateText = issueCreateEstimate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120,
              description.count <= 2_000,
              let streamID = issueCreateDestinationID
        else { return }
        guard case let .success(estimate) = FlexibleDurationParser.optionalMinutes(estimateText) else { return }
        let logicalDate = daemonConnection.currentDate.isEmpty
            ? (dailyFocusService.snapshot.date.isEmpty ? DailyFocusService.todayString() : dailyFocusService.snapshot.date)
            : daemonConnection.currentDate
        if let issueBeingEdited {
            let issue = issueBeingEdited
            Task {
                let succeeded = await issueActionsService.updateIssue(
                    issue: issue,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    estimateMinutes: estimate,
                    todoForDate: issueCreateForToday ? logicalDate : nil
                )
                if succeeded {
                    self.issueBeingEdited = nil
                    await dismissIssueCreatorPresentationAndWait()
                }
            }
            return
        }

        let request = CronaCreateIssueRequest(
            streamID: streamID,
            title: title,
            description: description.isEmpty ? nil : description,
            estimateMinutes: estimate,
            todoForDate: issueCreateForToday ? logicalDate : nil
        )
        Task {
            guard let created = await issueCreationService.create(request) else { return }
            let issue = DailyFocusIssue(
                id: created.id,
                streamID: created.streamID,
                title: created.title,
                status: created.status,
                estimateMinutes: created.estimateMinutes,
                workedSeconds: created.workedSeconds,
                todoForDate: created.todoForDate
            )
            issueCreationSuccess = IssueCreationSuccess(issue: issue, plannedForToday: issueCreateForToday)
            await dismissIssueCreatorPresentationAndWait()
            await dailyFocusService.refresh()
            scheduleIssueCreationSuccessDismissal()
        }
    }

    func startFocusFromCreatedIssue() {
        guard let success = issueCreationSuccess,
              success.plannedForToday,
              !hasActiveFocusSession
        else { return }
        issueCreationSuccessDismissTask?.cancel()
        issueCreationSuccess = nil
        selectedPopoverTab = .now
        selectedFocusIssue = success.issue
    }

    func dismissIssueCreationSuccess() {
        issueCreationSuccessDismissTask?.cancel()
        issueCreationSuccess = nil
    }

    private func scheduleIssueCreationSuccessDismissal() {
        issueCreationSuccessDismissTask?.cancel()
        issueCreationSuccessDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.issueCreationSuccess = nil
        }
    }

    private func dismissIssueCreatorPresentation() {
        guard isIssueCreatorPresented else { return }
        issueCreatorPresentationGeneration &+= 1
        let presentationGeneration = issueCreatorPresentationGeneration
        withAnimation(.easeInOut(duration: 0.18)) {
            isIssueCreatorContentVisible = false
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self,
                  !self.isIssueCreatorContentVisible,
                  presentationGeneration == self.issueCreatorPresentationGeneration
            else { return }
            self.isIssueCreatorPresented = false
            await Task.yield()
        }
    }

    private func dismissIssueCreatorPresentationAndWait() async {
        issueCreatorPresentationGeneration &+= 1
        let presentationGeneration = issueCreatorPresentationGeneration
        withAnimation(.easeInOut(duration: 0.18)) {
            isIssueCreatorContentVisible = false
        }
        try? await Task.sleep(for: .milliseconds(180))
        guard !isIssueCreatorContentVisible,
              presentationGeneration == issueCreatorPresentationGeneration
        else { return }
        isIssueCreatorPresented = false
        await Task.yield()
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
    }

    func presentManualSession(for issue: DailyFocusIssue) {
        issueActionsService.clearError()
        manualSessionSummary = ""
        manualSessionDate = dailyFocusService.snapshot.date.isEmpty
            ? (daemonConnection.currentDate.isEmpty ? DailyFocusService.todayString() : daemonConnection.currentDate)
            : dailyFocusService.snapshot.date
        manualSessionWorkHours = 1
        manualSessionWorkMinutes = 0
        manualSessionBreakHours = 0
        manualSessionBreakMinutes = 0
        manualSessionTimesEnabled = false
        manualSessionStartHour = 9
        manualSessionStartMinute = 0
        manualSessionStartPeriod = "AM"
        manualSessionEndHour = 10
        manualSessionEndMinute = 45
        manualSessionEndPeriod = "AM"
        manualSessionNotes = ""
        manualSessionError = nil
        issueActionEditor = .manualSession(issue: issue)
    }

    func cancelIssueActionEditor() {
        guard issueActionsService.actionInFlightIssueID == nil else { return }
        issueActionEditor = nil
        issueActionNote = ""
        manualSessionError = nil
    }

    func presentDeleteIssue(for issue: DailyFocusIssue) {
        issueActionsService.clearError()
        issueActionEditor = .delete(issue: issue)
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
                }
            }
        case let .dueDate(issue):
            let date = CronaCalendarDate.string(from: issueActionDate)
            Task {
                let succeeded = await issueActionsService.setDueDate(issue: issue, date: date)
                if succeeded {
                    issueActionEditor = nil
                }
            }
        case let .manualSession(issue):
            manualSessionError = nil
            let workMinutes = manualSessionWorkHours * 60 + manualSessionWorkMinutes
            let breakMinutes = manualSessionBreakHours * 60 + manualSessionBreakMinutes
            guard workMinutes > 0 else {
                manualSessionError = "Work duration must be a positive duration."
                return
            }
            guard isValidManualDate(manualSessionDate) else {
                manualSessionError = "Choose a valid session date."
                return
            }
            let startTime = manualSessionTimesEnabled
                ? formattedManualClock(hour: manualSessionStartHour, minute: manualSessionStartMinute, period: manualSessionStartPeriod)
                : nil
            let endTime = manualSessionTimesEnabled
                ? formattedManualClock(hour: manualSessionEndHour, minute: manualSessionEndMinute, period: manualSessionEndPeriod)
                : nil
            Task {
                let request = CronaManualSessionLogRequest(
                    issueID: issue.id,
                    date: manualSessionDate.trimmingCharacters(in: .whitespacesAndNewlines),
                    workDurationSeconds: workMinutes * 60,
                    breakDurationSeconds: breakMinutes * 60,
                    startTime: startTime,
                    endTime: endTime,
                    commitMessage: optionalTrimmed(manualSessionSummary),
                    notes: optionalTrimmed(manualSessionNotes)
                )
                let succeeded = await issueActionsService.logManualSession(request)
                if succeeded {
                    issueActionEditor = nil
                    manualSessionError = nil
                }
            }
        case let .delete(issue):
            Task {
                let succeeded = await issueActionsService.deleteIssue(issue)
                if succeeded {
                    if selectedFocusIssue?.id == issue.id { selectedFocusIssue = nil }
                    issueActionEditor = nil
                }
            }
        }
    }

    private func formattedManualClock(hour: Int, minute: Int, period: String) -> String {
        var hour24 = hour % 12
        if period == "PM" { hour24 += 12 }
        return String(format: "%02d:%02d", hour24, minute)
    }

    private func isValidManualDate(_ value: String) -> Bool {
        CronaCalendarDate.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    }

    func cancelEndSession() {
        guard !isSubmittingEndSession else { return }
        let wasPresentedInHUD = endSessionPresentationSource == .timerHUD
        endSessionFallbackTask?.cancel()
        endSessionFallbackTask = nil
        isEndSessionSheetPresented = false
        clearEndSessionState()
        if wasPresentedInHUD {
            windowService.setTimerHUDCommitPresented(false)
        }
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

        preferences.$preferences
            .map(\.settingsShortcut)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.settingsShortcutService.update(shortcut: shortcut)
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
                self.windowService.reconcileTimerHUD()
            }
            .store(in: &cancellables)

        [
            preferences.objectWillChange.eraseToAnyPublisher(),
            kernelDiscovery.objectWillChange.eraseToAnyPublisher(),
            notificationService.objectWillChange.eraseToAnyPublisher(),
            coreSettingsService.objectWillChange.eraseToAnyPublisher(),
            launchAtLoginService.objectWillChange.eraseToAnyPublisher(),
            daemonConnection.objectWillChange.eraseToAnyPublisher(),
            diagnosticsService.objectWillChange.eraseToAnyPublisher(),
            timerService.objectWillChange.eraseToAnyPublisher(),
            contextService.objectWillChange.eraseToAnyPublisher(),
            dailyFocusService.objectWillChange.eraseToAnyPublisher(),
            issueActionsService.objectWillChange.eraseToAnyPublisher(),
            issueCreationService.objectWillChange.eraseToAnyPublisher(),
            habitsService.objectWillChange.eraseToAnyPublisher(),
            wellbeingService.objectWillChange.eraseToAnyPublisher(),
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
                    self?.windowService.reconcileTimerHUD()
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
            await wellbeingService.refresh()
            await coreSettingsService.refresh()
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
        let wasPresentedInHUD = endSessionPresentationSource == .timerHUD
        clearEndSessionState()
        if wasPresentedInHUD {
            windowService.setTimerHUDCommitPresented(false)
        }
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
            self.windowService.reconcileTimerHUD()
        }
    }

    private func finalizeInactivityPopup() {
        inactivityPopupCountdownService.cancel()
        windowService.closeInactivityPopup { [weak self] in
            guard let self else { return }
            self.inactivityPopupPhase = nil
            self.inactivityPopupDelivery = nil
            self.inactivityPopupSessionID = nil
            if self.endSessionPresentationSource == .inactivityPopup {
                self.clearEndSessionState()
            }
        }
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
        windowService.closeSmartPauseResumeNotice { [weak self] in
            self?.smartPauseResumeNotice = nil
        }
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
        case .minutes1: return "1 min — Quick wrap-up"
        case .minutes5: return "5 min — Finish the current task"
        case .minutes15: return "15 min — Continue the focus block"
        case .session1: return "1 session — Continue the current cadence"
        case .session2: return "2 sessions — Make a deeper pass"
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
