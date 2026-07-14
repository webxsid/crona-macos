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
    var displayElapsedSeconds = 0
    var sessionStartTime: Date?
    var segmentStartTime: Date?
    var hardLimitActive = false
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
            displayElapsedSeconds: state.elapsedSeconds ?? 0,
            sessionStartTime: state.sessionStartTime.flatMap(TimerService.parseDate),
            segmentStartTime: state.segmentStartTime.flatMap(TimerService.parseDate),
            hardLimitActive: state.hardLimitActive ?? false,
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
    let canExtend: Bool
    let showsQuickExtend: Bool
    let currentFocusSeconds: Int
    let upcomingBreakSeconds: Int?

    static func from(_ snapshot: TimerSnapshot) -> TimerPresentation {
        let mode: FocusTimerMode
        if !snapshot.hardLimitActive {
            mode = .stopwatch
        } else if snapshot.hardLimitBreakSeconds > 0 || snapshot.hardLimitLongBreakSeconds > 0 || snapshot.hardLimitCyclesBeforeLongBreak > 0 {
            mode = .pomodoro
        } else {
            mode = .timer
        }

        let countsDown = snapshot.hardLimitActive
        let displaySeconds = max(0, snapshot.displayElapsedSeconds)
        let progressFraction: Double?
        if countsDown, snapshot.hardLimitTotalSeconds > 0 {
            progressFraction = max(0, min(1, Double(displaySeconds) / Double(snapshot.hardLimitTotalSeconds)))
        } else {
            progressFraction = nil
        }

        let phaseTitle: String
        let phaseSymbolName: String
        if snapshot.hardLimitActive {
            if snapshot.hardLimitExpired {
                phaseTitle = "Session complete"
                phaseSymbolName = "checkmark.circle"
            } else if snapshot.segmentType == "rest" {
                phaseTitle = "Break ends in"
                phaseSymbolName = "cup.and.saucer"
            } else if mode == .pomodoro {
                phaseTitle = "Break starts in"
                phaseSymbolName = "hourglass"
            } else {
                phaseTitle = "Timer ends in"
                phaseSymbolName = "hourglass"
            }
        } else {
            phaseTitle = snapshot.state == "paused" ? "Focus paused" : "Elapsed focus time"
            phaseSymbolName = snapshot.state == "paused" ? "pause.circle" : "bolt.fill"
        }

        let upcomingBreakSeconds: Int?
        if snapshot.hardLimitActive, snapshot.hardLimitBreakSeconds > 0 {
            upcomingBreakSeconds = snapshot.segmentType == "rest" ? nil : snapshot.hardLimitBreakSeconds
        } else {
            upcomingBreakSeconds = nil
        }

        return TimerPresentation(
            mode: mode,
            countsDown: countsDown,
            displaySeconds: displaySeconds,
            progressFraction: progressFraction,
            phaseTitle: phaseTitle,
            phaseSymbolName: phaseSymbolName,
            canPause: snapshot.sessionID != nil && snapshot.state == "running",
            canResume: snapshot.sessionID != nil && snapshot.state == "paused",
            canEnd: snapshot.sessionID != nil,
            canExtend: snapshot.hardLimitActive,
            showsQuickExtend: snapshot.hardLimitActive && snapshot.state != "paused",
            currentFocusSeconds: currentFocusSeconds(for: snapshot),
            upcomingBreakSeconds: upcomingBreakSeconds
        )
    }

    private static func currentFocusSeconds(for snapshot: TimerSnapshot) -> Int {
        if !snapshot.hardLimitActive {
            return max(0, snapshot.elapsedSeconds)
        }

        if snapshot.segmentType == "rest" {
            return max(0, snapshot.hardLimitWorkSeconds)
        }

        let worked = snapshot.hardLimitWorkSeconds - snapshot.hardLimitRemainingSeconds
        return max(0, min(snapshot.hardLimitWorkSeconds, worked))
    }
}

@MainActor
final class TimerService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private var timer: Timer?
    private var eventObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
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
            Task { await self?.refresh() }
        }

        startDisplayTicker()
        Task { await refresh() }
    }

    deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
        timer?.invalidate()
    }

    func refresh() async {
        do {
            logger.debug("Refreshing timer state")
            let state = try await daemonConnection.withClient { try await $0.timerGetState() }
            apply(state)
        } catch {
            logger.error("Timer refresh failed: \(error.localizedDescription, privacy: .public)")
            snapshot = TimerSnapshot(state: "disconnected", isConnected: false)
        }
    }

    func pauseTimer() async {
        do {
            let state = try await daemonConnection.withClient { try await $0.timerPause() }
            apply(state)
        } catch {}
    }

    func resumeTimer() async {
        do {
            let state = try await daemonConnection.withClient { try await $0.timerResume() }
            apply(state)
        } catch {}
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
            Task { await refresh() }
        default:
            break
        }
    }

    private func apply(_ state: CronaTimerState) {
        logger.debug("Applying timer state: state=\(state.state, privacy: .public) sessionId=\(state.sessionID ?? "nil", privacy: .public) issueId=\(String(state.issueID ?? -1), privacy: .public) elapsed=\(state.elapsedSeconds ?? 0, privacy: .public)")
        snapshot = .from(state)
        updateDisplayElapsed()
    }

    private func startDisplayTicker() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDisplayElapsed()
            }
        }
    }

    private func updateDisplayElapsed() {
        guard snapshot.state == "running" else {
            snapshot.displayElapsedSeconds = snapshot.hardLimitActive ? snapshot.hardLimitRemainingSeconds : snapshot.elapsedSeconds
            return
        }

        if snapshot.hardLimitActive {
            let elapsedSinceApply = max(0, Int(Date().timeIntervalSince(snapshot.snapshotAppliedAt)))
            snapshot.displayElapsedSeconds = max(0, snapshot.hardLimitRemainingSeconds - elapsedSinceApply)
            return
        }

        guard let segmentStartTime = snapshot.segmentStartTime else {
            snapshot.displayElapsedSeconds = snapshot.elapsedSeconds
            return
        }

        let offset = snapshot.elapsedSeconds - max(0, Int(Date().timeIntervalSince(segmentStartTime)))
        snapshot.displayElapsedSeconds = max(0, Int(Date().timeIntervalSince(segmentStartTime)) + max(0, offset))
    }

    static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
