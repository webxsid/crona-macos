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
    @Published private(set) var todayMetrics: CronaDailyMetricsDay?
    @Published private(set) var todayFocusScore: CronaFocusScoreSummary?

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

    isolated deinit {
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
                todayMetrics = metric
                todayFocusScore = focusScore
            }
        } catch {
            guard generation == refreshGeneration, date == selectedDate else { return }
            logger.error("Popover stats refresh failed: \(error.localizedDescription, privacy: .private)")
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

    func selectDate(_ date: String, isHistoricalAway: Bool = false) {
        guard !date.isEmpty, date != selectedDate else { return }
        selectedDate = date
        presentSelectedDate()
        if isHistoricalAway {
            refreshGeneration += 1
            snapshot = cache[date] ?? PopoverStatsSnapshot(
                date: date,
                isConnected: daemonConnection.connectionState == .connected
            )
            return
        }
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

        for batchStart in stride(from: 0, to: datesToLoad.count, by: 4) {
            let batchEnd = min(batchStart + 4, datesToLoad.count)
            let tasks = datesToLoad[batchStart..<batchEnd].map { date in
                Task { @MainActor [daemonConnection] in
                    let score = try? await daemonConnection.withClient {
                        try await $0.dashboardFocusScore(start: date, end: date)
                    }
                    return (date, score)
                }
            }
            for task in tasks {
                let (date, score) = await task.value
                guard let score else {
                    logger.debug("Calendar prefetch failed for \(date, privacy: .private)")
                    continue
                }
                cache[date] = Self.mergingCalendarScore(
                    score,
                    into: cache[date],
                    date: date
                )
            }
        }
    }

    func refreshTodayMetrics() async {
        let today = todayDate
        async let metricResult = Self.capture {
            try await self.daemonConnection.withClient {
                try await $0.metricsRange(start: today, end: today)
            }
        }
        async let focusScoreResult = Self.capture {
            try await self.daemonConnection.withClient {
                try await $0.dashboardFocusScore(start: today, end: today)
            }
        }
        let (loadedMetricsResult, loadedFocusScoreResult) = await (metricResult, focusScoreResult)
        var refreshed = cache[today] ?? PopoverStatsSnapshot(date: today)
        var loadedAnyValue = false

        switch loadedMetricsResult {
        case let .success(loadedMetrics):
            let metric = loadedMetrics.first(where: { $0.date == today }) ?? loadedMetrics.first
            todayWorkedSeconds = metric?.workedSeconds
            todayMetrics = metric
            refreshed = Self.mergingTodayMetrics(metric, into: refreshed)
            loadedAnyValue = true
        case let .failure(error):
            logger.error("Today metrics endpoint failed: \(error.localizedDescription, privacy: .private)")
        }

        switch loadedFocusScoreResult {
        case let .success(loadedFocusScore):
            todayFocusScore = loadedFocusScore
            refreshed = Self.mergingTodayFocusScore(loadedFocusScore, into: refreshed)
            loadedAnyValue = true
        case let .failure(error):
            logger.error("Today focus-score endpoint failed: \(error.localizedDescription, privacy: .private)")
        }

        if loadedAnyValue {
            refreshed.isConnected = true
            refreshed.lastErrorDescription = nil
            cache[today] = refreshed
        }
    }

    static func mergingCalendarScore(
        _ score: CronaFocusScoreSummary,
        into existing: PopoverStatsSnapshot?,
        date: String
    ) -> PopoverStatsSnapshot {
        var snapshot = existing ?? PopoverStatsSnapshot(date: date)
        snapshot.focusScore = score
        snapshot.scoreMessage = message(for: score.level)
        snapshot.isConnected = true
        snapshot.isLoading = false
        snapshot.lastErrorDescription = nil
        return snapshot
    }

    static func mergingTodayMetrics(
        _ metrics: CronaDailyMetricsDay?,
        into existing: PopoverStatsSnapshot
    ) -> PopoverStatsSnapshot {
        var snapshot = existing
        snapshot.todayMetrics = metrics
        return snapshot
    }

    static func mergingTodayFocusScore(
        _ score: CronaFocusScoreSummary,
        into existing: PopoverStatsSnapshot
    ) -> PopoverStatsSnapshot {
        var snapshot = existing
        snapshot.focusScore = score
        snapshot.scoreMessage = message(for: score.level)
        return snapshot
    }

    private static func capture<T>(
        _ operation: @escaping () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func handle(event: CronaProtocolEvent) {
        switch event.type {
        case "timer.state", "timer.break_deferral_warning", "timer.break_deferred",
             "session.started", "session.stopped", "session.ended", "timer.extended", "timer.boundary",
             "context.issue.changed", "issue.created", "issue.updated", "issue.deleted",
             "habit.created", "habit.updated", "habit.deleted", "habit.completed", "habit.uncompleted":
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
