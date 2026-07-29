import Combine
import Foundation
import OSLog

struct PopoverStatsSnapshot: Equatable {
    var date = ""
    var focusScore: CronaFocusScoreSummary?
    var todayMetrics: CronaDailyMetricsDay?
    var scoreMessage = ""
    var isConnected = false
    var isLoading = false
    var lastErrorDescription: String?
}

@MainActor
final class PopoverStatsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.crona.macos", category: "stats")
    private var selectedDate = DailyFocusService.todayString()
    private var cache: [String: PopoverStatsSnapshot] = [:]
    private var refreshGeneration = 0

    @Published var snapshot = PopoverStatsSnapshot(
        date: DailyFocusService.todayString(),
        isLoading: true
    )
    @Published private(set) var todayWorkedSeconds: Int?

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
        let date = selectedDate
        refreshGeneration += 1
        let generation = refreshGeneration

        if var cached = cache[date] {
            cached.isLoading = true
            cached.lastErrorDescription = nil
            snapshot = cached
        } else {
            snapshot = PopoverStatsSnapshot(date: date, isLoading: true)
        }

        do {
            async let score = daemonConnection.withClient { try await $0.dashboardFocusScore(start: date, end: date) }
            async let metrics = daemonConnection.withClient { try await $0.metricsRange(start: date, end: date) }
            let (focusScore, metricDays) = try await (score, metrics)
            guard generation == refreshGeneration, date == selectedDate else { return }

            let metric = metricDays.first(where: { $0.date == date }) ?? metricDays.first
            let refreshed = PopoverStatsSnapshot(
                date: date,
                focusScore: focusScore,
                todayMetrics: metric,
                scoreMessage: Self.message(for: focusScore.level),
                isConnected: true,
                isLoading: false,
                lastErrorDescription: nil
            )
            cache[date] = refreshed
            snapshot = refreshed
            if date == todayDate {
                todayWorkedSeconds = metric?.workedSeconds
            }
        } catch {
            guard generation == refreshGeneration, date == selectedDate else { return }
            logger.error("Popover stats refresh failed: \(error.localizedDescription, privacy: .public)")
            if var cached = cache[date] {
                cached.isLoading = false
                cached.lastErrorDescription = error.localizedDescription
                snapshot = cached
            } else {
                snapshot = PopoverStatsSnapshot(
                    date: date,
                    isConnected: false,
                    isLoading: false,
                    lastErrorDescription: error.localizedDescription
                )
            }
        }
    }

    func showPreviousDay() {
        selectedDate = Self.shift(date: selectedDate, byDays: -1)
        presentSelectedDate()
        Task { await refresh() }
    }

    func showNextDay() {
        let today = todayDate
        let candidate = Self.shift(date: selectedDate, byDays: 1)
        guard candidate <= today else { return }
        selectedDate = candidate
        presentSelectedDate()
        Task { await refresh() }
    }

    func selectDate(_ date: String) {
        guard !date.isEmpty, date != selectedDate else { return }
        selectedDate = date
        presentSelectedDate()
        Task { await refresh() }
    }

    func showToday() {
        selectedDate = todayDate
        presentSelectedDate()
        Task { await refresh() }
    }

    func canShowNextDay() -> Bool {
        selectedDate < todayDate
    }

    func cachedSnapshot(for date: String) -> PopoverStatsSnapshot? {
        cache[date]
    }

    func prefetchCalendarDates(_ dates: [String]) async {
        let datesToLoad = dates.filter { !isCachedFocusScoreLoaded(for: $0) }
        guard !datesToLoad.isEmpty else { return }

        for date in datesToLoad {
            do {
                let score = try await daemonConnection.withClient {
                    try await $0.dashboardFocusScore(start: date, end: date)
                }
                let refreshed = PopoverStatsSnapshot(
                    date: date,
                    focusScore: score,
                    scoreMessage: Self.message(for: score.level),
                    isConnected: true,
                    isLoading: false,
                    lastErrorDescription: nil
                )
                cache[date] = refreshed
            } catch {
                logger.debug("Calendar prefetch failed for \(date, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func refreshTodayMetrics() async {
        let today = todayDate
        do {
            let metricDays = try await daemonConnection.withClient {
                try await $0.metricsRange(start: today, end: today)
            }
            let metric = metricDays.first(where: { $0.date == today }) ?? metricDays.first
            todayWorkedSeconds = metric?.workedSeconds
            if var cached = cache[today] {
                cached.todayMetrics = metric
                cache[today] = cached
            }
        } catch {
            logger.error("Today metrics refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(event: CronaProtocolEvent) {
        switch event.type {
        case "timer.state", "session.started", "session.stopped", "session.ended", "timer.extended", "timer.boundary", "context.issue.changed":
            cache[selectedDate] = nil
            let today = todayDate
            cache[today] = nil
            Task {
                await refresh()
                if selectedDate != today {
                    await refreshTodayMetrics()
                }
            }
        default:
            break
        }
    }

    func handleDayStart(date: String, previousDate: String) async {
        guard !date.isEmpty else { return }
        if selectedDate == previousDate {
            selectedDate = date
        }
        cache[previousDate] = nil
        cache[date] = nil
        await refresh()
        await refreshTodayMetrics()
    }

    private var todayDate: String {
        let daemonDate = daemonConnection.currentDate
        return daemonDate.isEmpty ? DailyFocusService.todayString() : daemonDate
    }

    private func presentSelectedDate() {
        if var cached = cache[selectedDate] {
            cached.isLoading = true
            cached.lastErrorDescription = nil
            snapshot = cached
        } else {
            snapshot = PopoverStatsSnapshot(date: selectedDate, isLoading: true)
        }
    }

    private func isCachedFocusScoreLoaded(for date: String) -> Bool {
        cache[date]?.focusScore != nil
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
        CronaCalendarDate.adding(days: days, to: date) ?? date
    }
}
