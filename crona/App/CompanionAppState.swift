import AppKit
import Combine
import Foundation
import OSLog

enum SettingsDestination: String, CaseIterable, Equatable, Identifiable {
    case general
    case menuBar
    case notifications
    case stats
    case runtime
    case diagnostics
    case about

    var id: String { rawValue }
}

@MainActor
final class CompanionAppState: ObservableObject {
    let logger = Logger(subsystem: "com.crona.macos", category: "app")

    let preferences: PreferencesService
    let kernelDiscovery: KernelDiscoveryService
    let notificationService: NotificationService
    let launchAtLoginService: LaunchAtLoginService
    let daemonConnection: DaemonConnectionService
    let diagnosticsService: DiagnosticsService
    let timerService: TimerService
    let contextService: ContextService
    let dailyFocusService: DailyFocusService
    let habitsService: HabitsService
    let popoverStatsService: PopoverStatsService
    let windowService: WindowService
    let statusBarService: StatusBarService
    private var cancellables: Set<AnyCancellable> = []
    private var daemonEventObserver: NSObjectProtocol?
    private var endSessionFallbackTask: Task<Void, Never>?
    @Published var selectedFocusIssue: DailyFocusIssue?
    @Published var selectedPopoverTab: PopoverTab = .now
    @Published var selectedSettingsDestination: SettingsDestination = .general
    @Published var isEndSessionSheetPresented = false
    @Published var endSessionCommitMessage = ""
    @Published var isSubmittingEndSession = false
    @Published var endSessionErrorMessage: String?
    @Published private(set) var pendingEndSessionID: String?

    init() {
        let preferences = PreferencesService()
        let kernelDiscovery = KernelDiscoveryService(configLoader: CronaConfigLoader())
        let notificationService = NotificationService()
        let launchAtLoginService = LaunchAtLoginService()
        let daemonConnection = DaemonConnectionService(kernelDiscovery: kernelDiscovery)
        let contextService = ContextService(daemonConnection: daemonConnection)
        let timerService = TimerService(daemonConnection: daemonConnection)
        let dailyFocusService = DailyFocusService(daemonConnection: daemonConnection)
        let habitsService = HabitsService(daemonConnection: daemonConnection)
        let popoverStatsService = PopoverStatsService(daemonConnection: daemonConnection)
        let diagnosticsService = DiagnosticsService(
            daemonConnection: daemonConnection,
            kernelDiscovery: kernelDiscovery
        )

        self.preferences = preferences
        self.kernelDiscovery = kernelDiscovery
        self.notificationService = notificationService
        self.launchAtLoginService = launchAtLoginService
        self.daemonConnection = daemonConnection
        self.contextService = contextService
        self.timerService = timerService
        self.dailyFocusService = dailyFocusService
        self.habitsService = habitsService
        self.popoverStatsService = popoverStatsService
        self.diagnosticsService = diagnosticsService
        self.windowService = WindowService()
        self.statusBarService = StatusBarService()

        self.windowService.configure(appState: self)
        self.statusBarService.configure(appState: self)
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
        bindChildChanges()
    }

    deinit {
        if let daemonEventObserver {
            NotificationCenter.default.removeObserver(daemonEventObserver)
        }
        endSessionFallbackTask?.cancel()
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
        if selectedPopoverTab == .stats {
            return .idle(IdleFocusPopoverModel(issues: [], date: ""))
        }
        if daemonConnection.connectionState == .error || daemonConnection.connectionState == .incompatible {
            return .error(message: daemonConnection.lastErrorDescription ?? "Unable to reach Crona.")
        }
        if daemonConnection.connectionState != .connected {
            return .disconnected
        }
        if timerService.snapshot.sessionID != nil, timerService.snapshot.state != "idle", timerService.snapshot.state != "disconnected" {
            return .active(
                ActiveTimerPopoverModel(
                    presentation: TimerPresentation.from(timerService.snapshot),
                    timerSnapshot: timerService.snapshot,
                    contextSnapshot: contextService.snapshot
                )
            )
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

    func start() {
        statusBarService.installIfNeeded()
        notificationService.refreshAuthorizationStatus()
        launchAtLoginService.refresh()
        daemonConnection.start()
    }

    func stop() {
        daemonConnection.stop()
    }

    func manualReconnect() {
        daemonConnection.manualReconnect()
    }

    func setSelectedPopoverTab(_ tab: PopoverTab) {
        selectedPopoverTab = tab
    }

    func setSelectedSettingsDestination(_ destination: SettingsDestination) {
        selectedSettingsDestination = destination
    }

    func openSettings() {
        windowService.showSettings()
    }

    func openTUI() {
        windowService.openTUI(using: preferences.preferences.tuiCommand)
    }

    func pauseTimer() {
        Task { await timerService.pauseTimer() }
    }

    func resumeTimer() {
        Task { await timerService.resumeTimer() }
    }

    func endTimer() {
        beginEndSession()
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
                logger.error("Failed to extend timer: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func selectFocusIssue(_ issue: DailyFocusIssue) {
        selectedFocusIssue = issue
    }

    func dismissStartConfig() {
        selectedFocusIssue = nil
    }

    func beginEndSession() {
        guard let sessionID = timerService.snapshot.sessionID else { return }
        pendingEndSessionID = sessionID
        endSessionCommitMessage = ""
        endSessionErrorMessage = nil
        isEndSessionSheetPresented = true
    }

    func cancelEndSession() {
        guard !isSubmittingEndSession else { return }
        endSessionFallbackTask?.cancel()
        endSessionFallbackTask = nil
        isEndSessionSheetPresented = false
        pendingEndSessionID = nil
        endSessionCommitMessage = ""
        endSessionErrorMessage = nil
    }

    func confirmEndSession() {
        let trimmedMessage = endSessionCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            endSessionErrorMessage = "A commit message is required."
            return
        }
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
                logger.error("Failed to end timer: \(error.localizedDescription, privacy: .public)")
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
                logger.error("Failed to start focus session: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func completeHabit(_ habit: HabitRowModel) {
        Task { await habitsService.complete(habit) }
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

    private func bindChildChanges() {
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
            habitsService.objectWillChange.eraseToAnyPublisher(),
            popoverStatsService.objectWillChange.eraseToAnyPublisher()
        ]
        .forEach { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                    self?.statusBarService.updateStatusItem()
                    self?.reconcileEndSessionPresentation()
                }
                .store(in: &cancellables)
        }
    }

    private func handleDaemonEvent(_ event: CronaProtocolEvent) {
        switch event.type {
        case "session.ended":
            guard let sessionID = event.sessionID else { return }
            finalizeEndSessionIfNeeded(for: sessionID)
        default:
            break
        }
    }

    private func buildExtendRequest(additionalSeconds: Int?) -> CronaTimerExtendRequest? {
        Self.buildQuickExtendRequest(snapshot: timerService.snapshot, additionalSeconds: additionalSeconds)
    }

    static func buildQuickExtendRequest(snapshot: TimerSnapshot, additionalSeconds: Int?) -> CronaTimerExtendRequest? {
        let hasConfiguredHardLimit = snapshot.hardLimitTotalSeconds > 0

        guard let additionalSeconds, additionalSeconds > 0 else {
            return nil
        }

        return CronaTimerExtendRequest(
            additionalSeconds: additionalSeconds,
            additionalSessions: 0,
            hardLimitTotalSeconds: hasConfiguredHardLimit ? snapshot.hardLimitTotalSeconds : nil,
            hardLimitWorkSeconds: hasConfiguredHardLimit ? max(1, snapshot.hardLimitWorkSeconds) : nil,
            hardLimitBreakSeconds: hasConfiguredHardLimit ? max(0, snapshot.hardLimitBreakSeconds) : nil,
            hardLimitLongBreakSeconds: hasConfiguredHardLimit ? max(0, snapshot.hardLimitLongBreakSeconds) : nil,
            hardLimitCyclesBeforeLongBreak: hasConfiguredHardLimit ? max(0, snapshot.hardLimitCyclesBeforeLongBreak) : nil
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
        guard let pendingEndSessionID, pendingEndSessionID == sessionID else { return }
        finalizeEndSessionUI()
    }

    private func finalizeEndSessionUI() {
        endSessionFallbackTask?.cancel()
        endSessionFallbackTask = nil
        isSubmittingEndSession = false
        isEndSessionSheetPresented = false
        pendingEndSessionID = nil
        endSessionCommitMessage = ""
        endSessionErrorMessage = nil
        selectedFocusIssue = nil
    }

    private func reconcileEndSessionPresentation() {
        guard isEndSessionSheetPresented else { return }

        if let pendingEndSessionID, timerService.snapshot.sessionID != pendingEndSessionID {
            finalizeEndSessionUI()
        }
    }
}
