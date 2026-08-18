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
    @Published private(set) var calendarCacheRevision = 0
    @Published private(set) var calendarAnchorDate: String?
    @Published private(set) var calendarMonthDate: String?

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
                scoreMessage: Self.message(for: focusScore.reason),
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

    var functionalDate: String { selectedDate }

    func reconcileToDate(_ date: String) async {
        guard !date.isEmpty else { return }
        selectedDate = date
        presentSelectedDate()
        await refresh()
    }

    func canShowNextDay() -> Bool {
        selectedDate < todayDate
    }

    func beginCalendar() {
        calendarAnchorDate = snapshot.date.isEmpty ? selectedDate : snapshot.date
        calendarMonthDate = Self.monthStart(for: calendarAnchorDate ?? selectedDate)
    }

    func endCalendar() {
        calendarAnchorDate = nil
        calendarMonthDate = nil
    }

    func showPreviousCalendarMonth() {
        guard let month = calendarMonthDate,
            let previous = Self.adding(months: -1, to: month)
        else { return }
        calendarMonthDate = previous
    }

    func showNextCalendarMonth() {
        guard canShowNextCalendarMonth(),
            let month = calendarMonthDate,
            let next = Self.adding(months: 1, to: month)
        else { return }
        calendarMonthDate = next
    }

    func canShowNextCalendarMonth() -> Bool {
        guard let month = calendarMonthDate else { return false }
        return month < (Self.monthStart(for: todayDate) ?? todayDate)
    }

    static func monthRange(for monthDate: String, through date: String) -> [String] {
        guard let monthStart = monthStart(for: monthDate),
            let monthEnd = monthEnd(for: monthStart)
        else { return [] }
        let end = min(monthEnd, date)
        guard monthStart <= end else { return [] }

        var result: [String] = []
        var current = monthStart
        while current <= end {
            result.append(current)
            guard let next = adding(days: 1, to: current) else { break }
            current = next
        }
        return result
    }

    func cachedSnapshot(for date: String) -> PopoverStatsSnapshot? {
        cache[date]
    }

    func prefetchCalendarDates(_ dates: [String]) async {
        guard let start = dates.first, let end = dates.last else { return }

        do {
            let range = try await daemonConnection.withClient {
                try await $0.dashboardFocusScoreRange(start: start, end: end)
            }
            for day in range where dates.contains(day.date) {
                var snapshot = cache[day.date] ?? PopoverStatsSnapshot(date: day.date)
                if day.hasData {
                    snapshot.focusScore = CronaFocusScoreSummary(
                        startDate: day.date,
                        endDate: day.date,
                        score: day.score,
                        level: day.level,
                        reason: day.reason,
                        workedSeconds: 0,
                        restSeconds: 0,
                        sessionCount: 0,
                        focusDays: 0,
                        days: 1,
                        targetWorkedSeconds: 0
                    )
                    snapshot.scoreMessage = Self.message(for: day.reason)
                } else {
                    snapshot.focusScore = nil
                    snapshot.scoreMessage = ""
                }
                snapshot.isConnected = true
                snapshot.isLoading = false
                snapshot.lastErrorDescription = nil
                cache[day.date] = snapshot
            }
            calendarCacheRevision += 1
        } catch {
            logger.debug("Calendar range prefetch failed: \(error.localizedDescription, privacy: .private)")
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
        snapshot.scoreMessage = message(for: score.reason)
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
        snapshot.scoreMessage = message(for: score.reason)
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

    private func isCachedCalendarDateLoaded(for date: String) -> Bool {
        guard let cached = cache[date] else { return false }
        return !cached.isLoading
    }

    static func title(for reason: String) -> String {
        switch reason {
        case "no_activity": return "Ready to begin"
        case "under_target": return "Build momentum"
        case "needs_breaks": return "Take a break"
        case "overextended": return "Overextended"
        default: return "Steady rhythm"
        }
    }

    static func message(for reason: String) -> String {
        switch reason {
        case "no_activity":
            return "Start a focused session to build today’s score."
        case "under_target":
            return "You’re below today’s planned focus time."
        case "needs_breaks":
            return "Your focus time is outpacing your recovery time."
        case "overextended":
            return "You’ve pushed beyond your target without enough recovery."
        default:
            return "Your work and recovery are in a healthy balance."
        }
    }

    private static func shift(date: String, byDays days: Int) -> String {
        CronaCalendarDate.adding(days: days, to: date) ?? date
    }

    static func monthStart(for date: String) -> String? {
        guard let parsed = CronaCalendarDate.date(from: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return CronaCalendarDate.string(from: calendar.dateInterval(of: .month, for: parsed)?.start ?? parsed)
    }

    private static func monthEnd(for date: String) -> String? {
        guard let parsed = CronaCalendarDate.date(from: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let interval = calendar.dateInterval(of: .month, for: parsed),
            let end = calendar.date(byAdding: .day, value: -1, to: interval.end)
        else { return nil }
        return CronaCalendarDate.string(from: end)
    }

    private static func adding(months: Int, to date: String) -> String? {
        guard let parsed = CronaCalendarDate.date(from: date) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let shifted = calendar.date(byAdding: .month, value: months, to: parsed) else {
            return nil
        }
        return monthStart(for: CronaCalendarDate.string(from: shifted))
    }

    private static func adding(days: Int, to date: String) -> String? {
        CronaCalendarDate.adding(days: days, to: date)
    }
}
