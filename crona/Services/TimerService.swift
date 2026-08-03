import Combine
import Foundation
import OSLog

struct TimerSnapshot: Equatable {
    var state = "disconnected"
    var sessionID: String?
    var issueID: Int64?
    var segmentType: String?
    var nextSegmentType: String?
    var readySegmentType: String?
    var elapsedSeconds = 0
    var sessionStartTime: Date?
    var segmentStartTime: Date?
    var segmentElapsedOffsetSeconds = 0
    var hardLimitActive = false
    var hardLimitKind: CronaTimerHardLimitKind?
    var hardLimitExpired = false
    var hardLimitTotalSeconds = 0
    var hardLimitRemainingSeconds = 0
    var hardLimitWorkSeconds = 0
    var hardLimitBreakSeconds = 0
    var hardLimitLongBreakSeconds = 0
    var hardLimitCyclesBeforeLongBreak = 0
    var snapshotAppliedAt = Date()
    var isConnected = false

    static func from(_ state: CronaTimerState) -> TimerSnapshot {
        TimerSnapshot(
            state: state.state,
            sessionID: state.sessionID,
            issueID: state.issueID,
            segmentType: state.segmentType,
            nextSegmentType: state.nextSegmentType,
            readySegmentType: state.readySegmentType,
            elapsedSeconds: state.elapsedSeconds ?? 0,
            sessionStartTime: state.sessionStartTime.flatMap(TimerService.parseDate),
            segmentStartTime: state.segmentStartTime.flatMap(TimerService.parseDate),
            segmentElapsedOffsetSeconds: state.segmentElapsedOffsetSeconds ?? 0,
            hardLimitActive: state.hardLimitActive ?? false,
            hardLimitKind: state.hardLimitActive == true
                ? CronaTimerHardLimitKind.normalized(state.hardLimitKind)
                : nil,
            hardLimitExpired: state.hardLimitExpired ?? false,
            hardLimitTotalSeconds: state.hardLimitTotalSeconds ?? 0,
            hardLimitRemainingSeconds: state.hardLimitRemainingSeconds ?? 0,
            hardLimitWorkSeconds: state.hardLimitWorkSeconds ?? 0,
            hardLimitBreakSeconds: state.hardLimitBreakSeconds ?? 0,
            hardLimitLongBreakSeconds: state.hardLimitLongBreakSeconds ?? 0,
            hardLimitCyclesBeforeLongBreak: state.hardLimitCyclesBeforeLongBreak ?? 0,
            snapshotAppliedAt: Date(),
            isConnected: true
        )
    }
}

enum FocusTimerMode: String, Equatable {
    case stopwatch
    case pomodoro
    case timer
}

enum TimerSegmentKind: Equatable {
    case work
    case shortBreak
    case longBreak

    init?(rawValue: String?) {
        switch rawValue {
        case "work":
            self = .work
        case "short_break", "rest":
            self = .shortBreak
        case "long_break":
            self = .longBreak
        default:
            return nil
        }
    }

    var isBreak: Bool {
        self != .work
    }
}

struct TimerUpcomingSegment: Equatable {
    let kind: TimerSegmentKind
    let durationSeconds: Int

    var title: String {
        switch kind {
        case .work:
            return "Upcoming focus"
        case .shortBreak:
            return "Upcoming short break"
        case .longBreak:
            return "Upcoming long break"
        }
    }
}

struct TimerPresentation: Equatable {
    let mode: FocusTimerMode
    let countsDown: Bool
    let displaySeconds: Int
    let progressFraction: Double?
    let phaseTitle: String
    let phaseSymbolName: String
    let canPause: Bool
    let canResume: Bool
    let canEnd: Bool
    let currentFocusSeconds: Int
    let upcomingSegment: TimerUpcomingSegment?

    static func from(_ snapshot: TimerSnapshot, at now: Date = Date()) -> TimerPresentation {
        let mode: FocusTimerMode
        if !snapshot.hardLimitActive {
            mode = .stopwatch
        } else if snapshot.hardLimitKind == .countdown {
            mode = .timer
        } else {
            mode = .pomodoro
        }

        let countsDown = snapshot.hardLimitActive
        let segment = activeSegment(for: snapshot)
        let displaySeconds = projectedDisplaySeconds(for: snapshot, at: now)
        let displayDuration: Int
        if mode == .timer {
            displayDuration = snapshot.hardLimitTotalSeconds
        } else if let segment {
            displayDuration = segmentDuration(for: segment, snapshot: snapshot)
        } else {
            displayDuration = 0
        }
        let progressFraction: Double?
        if countsDown, displayDuration > 0 {
            progressFraction = max(0, min(1, Double(displaySeconds) / Double(displayDuration)))
        } else {
            progressFraction = nil
        }

        let phaseTitle: String
        let phaseSymbolName: String
        if snapshot.hardLimitActive {
            if snapshot.hardLimitExpired {
                phaseTitle = "Session complete"
                phaseSymbolName = "checkmark.circle"
            } else if snapshot.state == "ready" {
                phaseTitle = segment?.isBreak == true ? "Break ready" : "Focus ready"
                phaseSymbolName = segment?.isBreak == true ? "cup.and.saucer" : "bolt.fill"
            } else if segment?.isBreak == true {
                phaseTitle = "Break ends in"
                phaseSymbolName = "cup.and.saucer"
            } else if mode == .pomodoro {
                let next = TimerSegmentKind(rawValue: snapshot.nextSegmentType)
                phaseTitle = next?.isBreak == true ? "Break starts in" : "Focus ends in"
                phaseSymbolName = "hourglass"
            } else {
                phaseTitle = "Timer ends in"
                phaseSymbolName = "hourglass"
            }
        } else {
            phaseTitle = snapshot.state == "paused" ? "Focus paused" : "Elapsed focus time"
            phaseSymbolName = snapshot.state == "paused" ? "pause.circle" : "bolt.fill"
        }

        return TimerPresentation(
            mode: mode,
            countsDown: countsDown,
            displaySeconds: displaySeconds,
            progressFraction: progressFraction,
            phaseTitle: phaseTitle,
            phaseSymbolName: phaseSymbolName,
            canPause: mode == .stopwatch && snapshot.sessionID != nil && snapshot.state == "running",
            canResume: mode == .stopwatch && snapshot.sessionID != nil && snapshot.state == "paused",
            canEnd: snapshot.sessionID != nil,
            currentFocusSeconds: currentFocusSeconds(
                for: snapshot,
                displaySeconds: displaySeconds
            ),
            upcomingSegment: upcomingSegment(for: snapshot, mode: mode)
        )
    }

    static func activeSegment(for snapshot: TimerSnapshot) -> TimerSegmentKind? {
        if snapshot.state == "ready" {
            return TimerSegmentKind(
                rawValue: snapshot.readySegmentType ?? snapshot.nextSegmentType
            )
        }
        return TimerSegmentKind(rawValue: snapshot.segmentType)
    }

    static func segmentDuration(
        for segment: TimerSegmentKind,
        snapshot: TimerSnapshot
    ) -> Int {
        switch segment {
        case .work:
            return snapshot.hardLimitWorkSeconds
        case .shortBreak:
            return snapshot.hardLimitBreakSeconds
        case .longBreak:
            return snapshot.hardLimitLongBreakSeconds > 0
                ? snapshot.hardLimitLongBreakSeconds
                : snapshot.hardLimitBreakSeconds
        }
    }

    static func hardLimitDisplaySeconds(
        for snapshot: TimerSnapshot,
        at now: Date
    ) -> Int {
        guard !snapshot.hardLimitExpired else { return 0 }

        if snapshot.hardLimitKind == .countdown {
            let elapsedSinceApply = max(0, Int(now.timeIntervalSince(snapshot.snapshotAppliedAt)))
            return max(0, snapshot.hardLimitRemainingSeconds - elapsedSinceApply)
        }

        guard let segment = activeSegment(for: snapshot) else {
            return max(0, snapshot.hardLimitRemainingSeconds)
        }
        let duration = segmentDuration(for: segment, snapshot: snapshot)
        guard duration > 0 else { return 0 }
        guard snapshot.state != "ready" else { return duration }

        let elapsed: Int
        if let segmentStartTime = snapshot.segmentStartTime {
            elapsed = max(0, Int(now.timeIntervalSince(segmentStartTime)))
                + snapshot.segmentElapsedOffsetSeconds
        } else {
            let elapsedSinceApply = max(0, Int(now.timeIntervalSince(snapshot.snapshotAppliedAt)))
            return min(
                duration,
                max(0, snapshot.hardLimitRemainingSeconds - elapsedSinceApply)
            )
        }
        return max(0, duration - min(duration, elapsed))
    }

    static func projectedDisplaySeconds(
        for snapshot: TimerSnapshot,
        at now: Date
    ) -> Int {
        if snapshot.hardLimitActive {
            return hardLimitDisplaySeconds(for: snapshot, at: now)
        }

        guard snapshot.state == "running" else {
            return max(0, snapshot.elapsedSeconds)
        }
        let elapsedSinceApply = max(0, Int(now.timeIntervalSince(snapshot.snapshotAppliedAt)))
        return max(0, snapshot.elapsedSeconds + elapsedSinceApply)
    }

    private static func upcomingSegment(
        for snapshot: TimerSnapshot,
        mode: FocusTimerMode
    ) -> TimerUpcomingSegment? {
        guard mode == .pomodoro, snapshot.state != "ready" else { return nil }
        guard
            let current = TimerSegmentKind(rawValue: snapshot.segmentType),
            let next = TimerSegmentKind(rawValue: snapshot.nextSegmentType),
            current != next
        else {
            return nil
        }
        let duration = segmentDuration(for: next, snapshot: snapshot)
        guard duration > 0 else { return nil }
        return TimerUpcomingSegment(kind: next, durationSeconds: duration)
    }

    private static func currentFocusSeconds(
        for snapshot: TimerSnapshot,
        displaySeconds: Int
    ) -> Int {
        if !snapshot.hardLimitActive {
            return max(0, snapshot.elapsedSeconds)
        }

        if TimerSegmentKind(rawValue: snapshot.segmentType)?.isBreak == true {
            return max(0, snapshot.hardLimitWorkSeconds)
        }

        let worked = snapshot.hardLimitWorkSeconds - displaySeconds
        return max(0, min(snapshot.hardLimitWorkSeconds, worked))
    }
}

@MainActor
final class TimerService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private let logger = Logger(subsystem: "com.crona.macos", category: "timer")

    @Published var snapshot = TimerSnapshot()

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
        eventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent else { return }
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
        connectObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.debug("Timer refresh triggered by daemon connect")
            Task { @MainActor [weak self] in
                self?.requestRefresh()
            }
        }

        requestRefresh()
    }

    isolated deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
        refreshTask?.cancel()
    }

    func refresh() async {
        do {
            logger.debug("Refreshing timer state")
            let state = try await daemonConnection.withClient { try await $0.timerGetState() }
            apply(state)
        } catch {
            logger.error("Timer refresh failed: \(error.localizedDescription, privacy: .private)")
            snapshot = TimerSnapshot(state: "disconnected", isConnected: false)
        }
    }

    @discardableResult
    func pauseTimer() async throws -> TimerSnapshot {
        let state = try await daemonConnection.withClient { try await $0.timerPause() }
        apply(state)
        return snapshot
    }

    @discardableResult
    func resumeTimer() async throws -> TimerSnapshot {
        let state = try await daemonConnection.withClient { try await $0.timerResume() }
        apply(state)
        return snapshot
    }

    @discardableResult
    func advanceTimer() async throws -> TimerSnapshot {
        let state = try await daemonConnection.withClient { try await $0.timerAdvance() }
        apply(state)
        return snapshot
    }

    func endTimer(commitMessage: String) async {
        do {
            _ = try await daemonConnection.withClient { try await $0.timerEnd(commitMessage: commitMessage) }
            await refresh()
        } catch {}
    }

    static func shouldRefresh(for eventType: String) -> Bool {
        switch eventType {
        case "timer.state", "timer.boundary", "timer.hard_limit_reached", "session.started", "session.stopped", "session.ended", "timer.extended":
            return true
        default:
            return false
        }
    }

    private func handle(event: CronaProtocolEvent) {
        switch event.type {
        case _ where Self.shouldRefresh(for: event.type):
            logger.debug("Timer refresh triggered by event: \(event.type, privacy: .public)")
            requestRefresh()
        default:
            break
        }
    }

    private func apply(_ state: CronaTimerState) {
        logger.debug("Applying timer state: state=\(state.state, privacy: .public) sessionId=\(state.sessionID ?? "nil", privacy: .private(mask: .hash)) issueId=\(String(state.issueID ?? -1), privacy: .private(mask: .hash)) elapsed=\(state.elapsedSeconds ?? 0, privacy: .public)")
        snapshot = .from(state)
    }

    private func requestRefresh() {
        guard refreshTask == nil else {
            refreshPending = true
            return
        }

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                refreshPending = false
                await refresh()
            } while refreshPending && !Task.isCancelled
            refreshTask = nil
        }
    }

    static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
