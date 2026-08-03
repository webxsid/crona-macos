import Combine
import Foundation
import OSLog

enum BreakScreenPhase: Equatable {
    case hidden
    case starting
    case active
    case resuming
    case recovery
}

enum BreakScreenTransition: Equatable {
    case none
    case startBreak
    case resumeWork
}

struct BreakScreenProjection: Equatable {
    let shouldPresent: Bool
    let transition: BreakScreenTransition
    let segment: TimerSegmentKind?

    static func resolve(
        snapshot: TimerSnapshot,
        enabled: Bool,
        managedSessionID: String?
    ) -> BreakScreenProjection {
        guard
            snapshot.isConnected,
            snapshot.hardLimitActive,
            snapshot.hardLimitKind == .pomodoro,
            !snapshot.hardLimitExpired,
            let sessionID = snapshot.sessionID
        else {
            return BreakScreenProjection(shouldPresent: false, transition: .none, segment: nil)
        }

        if snapshot.state == "ready" {
            let ready = TimerSegmentKind(rawValue: snapshot.readySegmentType ?? snapshot.nextSegmentType)
            if ready?.isBreak == true, enabled {
                return BreakScreenProjection(shouldPresent: true, transition: .startBreak, segment: ready)
            }
            if ready == .work, managedSessionID == sessionID {
                return BreakScreenProjection(shouldPresent: enabled, transition: .resumeWork, segment: ready)
            }
        }

        let active = TimerSegmentKind(rawValue: snapshot.segmentType)
        if active?.isBreak == true, enabled {
            return BreakScreenProjection(shouldPresent: true, transition: .none, segment: active)
        }
        return BreakScreenProjection(shouldPresent: false, transition: .none, segment: active)
    }
}

@MainActor
final class BreakScreenService: ObservableObject {
    private let preferences: PreferencesService
    private let timerService: TimerService
    private let windowService: WindowService
    private var cancellables: Set<AnyCancellable> = []
    private var advanceTask: Task<Void, Never>?
    private var managedSessionID: String?
    private var inFlightTransition: BreakScreenTransition?
    private var lastAdvanceKey: String?
    private let logger = Logger(subsystem: "com.crona.macos", category: "break-screen")

    @Published private(set) var phase: BreakScreenPhase = .hidden
    @Published private(set) var segment: TimerSegmentKind?
    @Published private(set) var recoveryMessage: String?

    init(
        preferences: PreferencesService,
        timerService: TimerService,
        windowService: WindowService
    ) {
        self.preferences = preferences
        self.timerService = timerService
        self.windowService = windowService
    }

    var snapshot: TimerSnapshot { timerService.snapshot }
    var currentPreferences: CompanionPreferences { preferences.preferences }

    var canSkip: Bool {
        canSkip(at: Date())
    }

    func canSkip(at now: Date) -> Bool {
        switch currentPreferences.breakScreenMode {
        case .easy:
            return phase == .active
        case .strict:
            return phase == .active && strictDelayRemaining(at: now) == 0
        case .hard:
            return false
        }
    }

    var strictDelayRemaining: Int {
        strictDelayRemaining(at: Date())
    }

    func strictDelayRemaining(at now: Date) -> Int {
        guard currentPreferences.breakScreenMode == .strict else { return 0 }
        return Self.strictDelayRemaining(
            snapshot: snapshot,
            segment: segment,
            delaySeconds: currentPreferences.breakScreenStrictDelaySeconds,
            now: now
        )
    }

    static func strictDelayRemaining(
        snapshot: TimerSnapshot,
        segment: TimerSegmentKind?,
        delaySeconds: Int,
        now: Date = Date()
    ) -> Int {
        let duration = segment.map {
            TimerPresentation.segmentDuration(for: $0, snapshot: snapshot)
        } ?? 0
        let remaining = TimerPresentation.projectedDisplaySeconds(
            for: snapshot,
            at: now
        )
        let elapsed = max(0, duration - remaining)
        return max(0, delaySeconds - elapsed)
    }

    func start() {
        guard cancellables.isEmpty else { return }

        timerService.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)

        preferences.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }
            .store(in: &cancellables)

        reconcile()
    }

    func stop() {
        advanceTask?.cancel()
        advanceTask = nil
        cancellables.removeAll()
        managedSessionID = nil
        inFlightTransition = nil
        lastAdvanceKey = nil
        hide()
    }

    func skipBreak() {
        guard canSkip else { return }
        performAdvance(.resumeWork, force: true)
    }

    func retryTransition() {
        guard phase == .recovery, let inFlightTransition else { return }
        recoveryMessage = nil
        performAdvance(inFlightTransition, force: true)
    }

    func dismissRecovery() {
        guard phase == .recovery else { return }
        managedSessionID = nil
        inFlightTransition = nil
        lastAdvanceKey = nil
        hide()
    }

    private func reconcile() {
        let snapshot = timerService.snapshot

        if phase == .recovery {
            guard
                snapshot.isConnected,
                snapshot.sessionID == managedSessionID,
                snapshot.hardLimitKind == .pomodoro,
                !snapshot.hardLimitExpired
            else {
                managedSessionID = nil
                inFlightTransition = nil
                hide()
                return
            }
            windowService.showBreakScreens()
            return
        }

        let projection = BreakScreenProjection.resolve(
            snapshot: snapshot,
            enabled: preferences.preferences.breakScreenEnabled,
            managedSessionID: managedSessionID
        )

        guard snapshot.sessionID != nil else {
            managedSessionID = nil
            lastAdvanceKey = nil
            hide()
            return
        }

        segment = projection.segment
        if projection.shouldPresent {
            managedSessionID = snapshot.sessionID
            if phase != .recovery {
                phase = projection.transition == .startBreak ? .starting : .active
                windowService.showBreakScreens()
            }
        } else if projection.transition != .resumeWork {
            hide()
        }

        switch projection.transition {
        case .none:
            if TimerSegmentKind(rawValue: snapshot.segmentType) == .work {
                managedSessionID = nil
                lastAdvanceKey = nil
            }
        case .startBreak:
            performAdvance(.startBreak)
        case .resumeWork:
            phase = .resuming
            performAdvance(.resumeWork)
        }
    }

    private func performAdvance(_ transition: BreakScreenTransition, force: Bool = false) {
        guard let sessionID = snapshot.sessionID else { return }
        let segmentKey = snapshot.readySegmentType ?? snapshot.segmentType ?? "unknown"
        let key = "\(sessionID):\(transition):\(segmentKey)"
        guard force || (lastAdvanceKey != key && advanceTask == nil) else { return }

        lastAdvanceKey = key
        inFlightTransition = transition
        advanceTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await timerService.advanceTimer()
                advanceTask = nil
                inFlightTransition = nil
                recoveryMessage = nil
                reconcile()
            } catch {
                logger.error("Break transition failed: \(error.localizedDescription, privacy: .private)")
                advanceTask = nil
                lastAdvanceKey = nil
                recoveryMessage = error.localizedDescription
                if transition == .startBreak {
                    managedSessionID = nil
                    hide()
                } else {
                    phase = .recovery
                    windowService.showBreakScreens()
                }
            }
        }
    }

    private func hide() {
        guard phase != .hidden || windowService.breakScreensVisible else { return }
        phase = .hidden
        segment = nil
        recoveryMessage = nil
        windowService.closeBreakScreens()
    }
}
