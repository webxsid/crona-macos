import Combine
import Foundation
import OSLog

struct PopoverStatsSnapshot: Equatable {
    var date = ""
    var focusScore: CronaFocusScoreSummary?
    var todayMetrics: CronaDailyMetricsDay?
    var scoreMessage = ""
    var isConnected = false
}

@MainActor
final class PopoverStatsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.crona.macos", category: "stats")
    private var selectedDate = DailyFocusService.todayString()

    @Published var snapshot = PopoverStatsSnapshot()

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
            Task { await self?.refresh() }
        }

        Task { await refresh() }
    }

    deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
    }

    func refresh() async {
        do {
            let date = selectedDate
            async let score = daemonConnection.withClient { try await $0.dashboardFocusScore(start: date, end: date) }
            async let metrics = daemonConnection.withClient { try await $0.metricsRange(start: date, end: date) }
            let (focusScore, metricDays) = try await (score, metrics)
            let metric = metricDays.first(where: { $0.date == date }) ?? metricDays.first
            snapshot = PopoverStatsSnapshot(
                date: date,
                focusScore: focusScore,
                todayMetrics: metric,
                scoreMessage: Self.message(for: focusScore.level),
                isConnected: true
            )
        } catch {
            logger.error("Popover stats refresh failed: \(error.localizedDescription, privacy: .public)")
            snapshot = PopoverStatsSnapshot()
        }
    }

    func showPreviousDay() {
        selectedDate = Self.shift(date: selectedDate, byDays: -1)
        Task { await refresh() }
    }

    func showNextDay() {
        let today = DailyFocusService.todayString()
        let candidate = Self.shift(date: selectedDate, byDays: 1)
        guard candidate <= today else { return }
        selectedDate = candidate
        Task { await refresh() }
    }

    func canShowNextDay() -> Bool {
        selectedDate < DailyFocusService.todayString()
    }

    private func handle(event: CronaProtocolEvent) {
        switch event.type {
        case "timer.state", "session.started", "session.stopped", "session.ended", "timer.extended", "timer.boundary", "context.issue.changed":
            Task { await refresh() }
        default:
            break
        }
    }

    static func message(for level: String) -> String {
        switch level {
        case "strong":
            return "You’re keeping a strong focus rhythm with healthy breaks."
        case "steady":
            return "Your pace is steady. Keep stacking consistent sessions."
        case "overextended":
            return "You’ve pushed hard today. Give recovery more room."
        default:
            return "A lighter day so far. Start a session to build momentum."
        }
    }

    private static func shift(date: String, byDays days: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        guard
            let current = formatter.date(from: date),
            let shifted = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: current)
        else {
            return date
        }

        return formatter.string(from: shifted)
    }
}
