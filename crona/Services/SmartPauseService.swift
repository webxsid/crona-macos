import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

enum SmartPauseCondition: Hashable {
    case sessionInactive
    case displayAsleep
    case inactivity
}

enum SmartPauseSystemEvent {
    case sessionResigned
    case sessionBecameActive
    case screensSlept
    case screensWoke
}

protocol SmartPauseSystemMonitoring: AnyObject {
    func start(handler: @escaping @MainActor (SmartPauseSystemEvent) -> Void)
    func stop()
}

protocol SmartPauseIdleTimeProviding {
    var idleSeconds: TimeInterval { get }
}

@MainActor
protocol SmartPauseTimerControlling: AnyObject {
    var smartPauseSnapshot: TimerSnapshot { get }
    var smartPauseSnapshots: AnyPublisher<TimerSnapshot, Never> { get }
    func pauseForSmartPause() async throws -> TimerSnapshot
    func resumeFromSmartPause() async throws -> TimerSnapshot
}

final class WorkspaceSmartPauseMonitor: SmartPauseSystemMonitoring {
    private var observers: [NSObjectProtocol] = []

    func start(handler: @escaping @MainActor (SmartPauseSystemEvent) -> Void) {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.sessionDidResignActiveNotification, as: .sessionResigned, center: center, handler: handler)
        observe(NSWorkspace.sessionDidBecomeActiveNotification, as: .sessionBecameActive, center: center, handler: handler)
        observe(NSWorkspace.screensDidSleepNotification, as: .screensSlept, center: center, handler: handler)
        observe(NSWorkspace.screensDidWakeNotification, as: .screensWoke, center: center, handler: handler)
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func observe(
        _ name: Notification.Name,
        as event: SmartPauseSystemEvent,
        center: NotificationCenter,
        handler: @escaping @MainActor (SmartPauseSystemEvent) -> Void
    ) {
        observers.append(
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in handler(event) }
            }
        )
    }
}

extension TimerService: SmartPauseTimerControlling {
    var smartPauseSnapshot: TimerSnapshot { snapshot }
    var smartPauseSnapshots: AnyPublisher<TimerSnapshot, Never> {
        $snapshot.eraseToAnyPublisher()
    }

    func pauseForSmartPause() async throws -> TimerSnapshot {
        try await pauseTimer()
    }

    func resumeFromSmartPause() async throws -> TimerSnapshot {
        try await resumeTimer()
    }
}

struct CoreGraphicsIdleTimeProvider: SmartPauseIdleTimeProviding {
    var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
    }
}

@MainActor
final class SmartPauseService {
    private let preferences: PreferencesService
    private let timerController: SmartPauseTimerControlling
    private let systemMonitor: SmartPauseSystemMonitoring
    private let idleTimeProvider: SmartPauseIdleTimeProviding
    private var onAutomaticResume: @MainActor (TimerSnapshot) -> Void
    private let logger = Logger(subsystem: "com.crona.macos", category: "smart-pause")
    private var conditions: Set<SmartPauseCondition> = []
    private var cancellables: Set<AnyCancellable> = []
    private var idleTimer: Timer?
    private var actionTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var managedSessionID: String?
    private var isStarted = false

    init(
        preferences: PreferencesService,
        timerController: SmartPauseTimerControlling,
        systemMonitor: SmartPauseSystemMonitoring? = nil,
        idleTimeProvider: SmartPauseIdleTimeProviding? = nil
    ) {
        self.preferences = preferences
        self.timerController = timerController
        self.systemMonitor = systemMonitor ?? WorkspaceSmartPauseMonitor()
        self.idleTimeProvider = idleTimeProvider ?? CoreGraphicsIdleTimeProvider()
        self.onAutomaticResume = { _ in }
    }

    func setAutomaticResumeHandler(_ handler: @escaping @MainActor (TimerSnapshot) -> Void) {
        onAutomaticResume = handler
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        systemMonitor.start { [weak self] event in
            self?.handleSystemEvent(event)
        }
        timerController.smartPauseSnapshots
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)
        preferences.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileIdleTimer()
                self?.reconcile()
            }
            .store(in: &cancellables)

        reconcileIdleTimer()
        reconcile()
    }

    func stop() {
        isStarted = false
        systemMonitor.stop()
        idleTimer?.invalidate()
        idleTimer = nil
        actionTask?.cancel()
        actionTask = nil
        retryTask?.cancel()
        retryTask = nil
        cancellables.removeAll()
        conditions.removeAll()
        managedSessionID = nil
    }

    func handleSystemEvent(_ event: SmartPauseSystemEvent) {
        switch event {
        case .sessionResigned:
            conditions.insert(.sessionInactive)
        case .sessionBecameActive:
            conditions.remove(.sessionInactive)
        case .screensSlept:
            conditions.insert(.displayAsleep)
        case .screensWoke:
            conditions.remove(.displayAsleep)
        }
        logger.debug("System conditions changed: \(self.conditions.count, privacy: .public)")
        reconcile()
    }

    func evaluateIdleState() {
        let settings = preferences.preferences
        guard settings.smartPauseEnabled, settings.smartPauseOnInactivity else {
            conditions.remove(.inactivity)
            reconcile()
            return
        }

        if idleTimeProvider.idleSeconds >= TimeInterval(settings.smartPauseIdleSeconds) {
            conditions.insert(.inactivity)
        } else {
            conditions.remove(.inactivity)
        }
        reconcile()
    }

    static func isEligibleStopwatch(_ snapshot: TimerSnapshot) -> Bool {
        snapshot.isConnected
            && snapshot.sessionID != nil
            && snapshot.state == "running"
            && TimerPresentation.from(snapshot).mode == .stopwatch
    }

    private func effectiveConditions(for settings: CompanionPreferences) -> Set<SmartPauseCondition> {
        conditions.filter { condition in
            switch condition {
            case .sessionInactive: return settings.smartPauseOnLock
            case .displayAsleep: return settings.smartPauseOnDisplaySleep
            case .inactivity: return settings.smartPauseOnInactivity
            }
        }
    }

    private func reconcileIdleTimer() {
        let settings = preferences.preferences
        let shouldPoll = settings.smartPauseEnabled && settings.smartPauseOnInactivity
        guard shouldPoll != (idleTimer != nil) else { return }

        idleTimer?.invalidate()
        idleTimer = nil
        guard shouldPoll else {
            conditions.remove(.inactivity)
            return
        }

        evaluateIdleState()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateIdleState()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func reconcile() {
        guard isStarted, actionTask == nil, retryTask == nil else { return }
        let settings = preferences.preferences
        let snapshot = timerController.smartPauseSnapshot

        if managedSessionID != nil, managedSessionID != snapshot.sessionID {
            managedSessionID = nil
        }
        guard settings.smartPauseEnabled else {
            managedSessionID = nil
            return
        }

        let activeConditions = effectiveConditions(for: settings)
        if
            !activeConditions.isEmpty,
            Self.isEligibleStopwatch(snapshot),
            let sessionID = snapshot.sessionID
        {
            pause(sessionID: sessionID)
            return
        }

        guard
            activeConditions.isEmpty,
            let managedSessionID,
            snapshot.sessionID == managedSessionID,
            snapshot.state == "paused"
        else {
            if snapshot.state == "running", activeConditions.isEmpty {
                self.managedSessionID = nil
            }
            return
        }
        resume(sessionID: managedSessionID)
    }

    private func pause(sessionID: String) {
        logger.info("Automatically pausing stopwatch")
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await timerController.pauseForSmartPause()
                if snapshot.sessionID == sessionID, snapshot.state == "paused" {
                    managedSessionID = sessionID
                }
            } catch {
                logger.error("Automatic pause failed: \(error.localizedDescription, privacy: .private)")
                scheduleRetry()
            }
            actionTask = nil
            if retryTask == nil {
                reconcile()
            }
        }
    }

    private func resume(sessionID: String) {
        logger.info("Automatically resuming stopwatch")
        actionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await timerController.resumeFromSmartPause()
                if snapshot.sessionID == sessionID, snapshot.state == "running" {
                    managedSessionID = nil
                    onAutomaticResume(snapshot)
                }
            } catch {
                logger.error("Automatic resume failed: \(error.localizedDescription, privacy: .private)")
                scheduleRetry()
            }
            actionTask = nil
            if retryTask == nil {
                reconcile()
            }
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            retryTask = nil
            reconcile()
        }
    }
}
