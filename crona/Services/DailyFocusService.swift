import Combine
import Foundation
import OSLog

struct DailyFocusIssue: Equatable, Identifiable {
    let id: Int64
    let streamID: Int64
    let title: String
    let status: String
    let estimateMinutes: Int?
    let workedSeconds: Int
    let todoForDate: String?
}

struct DailyFocusSnapshot: Equatable {
    var date = ""
    var issues: [DailyFocusIssue] = []
    var isConnected = false
}

@MainActor
final class DailyFocusService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.crona.macos", category: "dailyFocus")

    @Published var snapshot = DailyFocusSnapshot()

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
            let today = Self.todayString()
            async let summary = daemonConnection.withClient { try await $0.issueTodaySummary() }
            async let plan = daemonConnection.withClient { try await $0.dailyPlanGet(date: today) }
            let (issueSummary, dailyPlan) = try await (summary, plan)
            let orderedIssues = Self.buildIssues(summary: issueSummary, plan: dailyPlan)
            snapshot = DailyFocusSnapshot(date: today, issues: orderedIssues, isConnected: true)
            logger.debug("Applied daily focus issues: \(orderedIssues.count, privacy: .public)")
        } catch {
            logger.error("Daily focus refresh failed: \(error.localizedDescription, privacy: .public)")
            snapshot = DailyFocusSnapshot()
        }
    }

    private func handle(event: CronaProtocolEvent) {
        switch event.type {
        case "session.started", "session.stopped", "session.ended", "timer.extended", "context.issue.changed", "issue.updated", "issue.created", "issue.deleted":
            Task { await refresh() }
        default:
            break
        }
    }

    static func buildIssues(summary: CronaDailyIssueSummary, plan: CronaDailyPlan) -> [DailyFocusIssue] {
        let validStatuses = Set(["planned", "active", "in_progress", "todo", "backlog"])
        var issuesByID = Dictionary(uniqueKeysWithValues: summary.issues.map { ($0.id, $0) })
        var ordered: [DailyFocusIssue] = []
        var seen = Set<Int64>()

        for entry in plan.entries where entry.status == "planned" {
            guard let issue = issuesByID.removeValue(forKey: entry.issueID) else { continue }
            guard Self.isEligible(issue, anchorDate: summary.date, validStatuses: validStatuses) else { continue }
            ordered.append(Self.project(issue))
            seen.insert(issue.id)
        }

        for issue in summary.issues where !seen.contains(issue.id) {
            guard Self.isEligible(issue, anchorDate: summary.date, validStatuses: validStatuses) else { continue }
            ordered.append(Self.project(issue))
        }

        return ordered
    }

    private static func isEligible(_ issue: CronaIssue, anchorDate: String, validStatuses: Set<String>) -> Bool {
        if issue.status == "done" || issue.status == "abandoned" {
            return false
        }
        if let due = issue.todoForDate, due == anchorDate {
            return true
        }
        return validStatuses.contains(issue.status)
    }

    private static func project(_ issue: CronaIssue) -> DailyFocusIssue {
        DailyFocusIssue(
            id: issue.id,
            streamID: issue.streamID,
            title: issue.title,
            status: issue.status,
            estimateMinutes: issue.estimateMinutes,
            workedSeconds: issue.workedSeconds,
            todoForDate: issue.todoForDate
        )
    }

    static func todayString(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
}
