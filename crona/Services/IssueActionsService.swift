import Combine
import Foundation
import OSLog

@MainActor
final class IssueActionsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let dailyFocusService: DailyFocusService
    private let logger = Logger(subsystem: "com.crona.macos", category: "issueActions")
    private var synchronizationTask: Task<Void, Never>?

    @Published private(set) var transitionsByIssueID: [Int64: CronaIssueStatusTransitions] = [:]
    @Published private(set) var actionInFlightIssueID: Int64?
    @Published private(set) var lastErrorMessage: String?

    init(
        daemonConnection: DaemonConnectionService,
        dailyFocusService: DailyFocusService
    ) {
        self.daemonConnection = daemonConnection
        self.dailyFocusService = dailyFocusService
    }

    deinit {
        synchronizationTask?.cancel()
    }

    func synchronize(issues: [DailyFocusIssue], force: Bool = false) {
        let issueIDs = Set(issues.map(\.id))
        transitionsByIssueID = transitionsByIssueID.filter { issueIDs.contains($0.key) }

        let staleIssues = issues.filter { issue in
            guard !force, let cached = transitionsByIssueID[issue.id] else { return true }
            return Self.normalizedStatus(issue.status) != cached.currentStatus
        }
        guard !staleIssues.isEmpty else { return }

        synchronizationTask?.cancel()
        synchronizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for issue in staleIssues {
                guard !Task.isCancelled else { return }
                do {
                    let transitions = try await daemonConnection.withClient {
                        try await $0.issueStatusTransitions(issueID: issue.id)
                    }
                    transitionsByIssueID[issue.id] = transitions
                } catch {
                    logger.error(
                        "Loading status transitions failed for issue \(issue.id, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .private)"
                    )
                    lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func changeStatus(
        issue: DailyFocusIssue,
        status: CronaIssueStatus,
        note: String?
    ) async -> Bool {
        await perform(issueID: issue.id) {
            _ = try await self.daemonConnection.withClient {
                try await $0.changeIssueStatus(
                    issueID: issue.id,
                    status: status,
                    note: note
                )
            }
        }
    }

    func setDueDate(issue: DailyFocusIssue, date: String) async -> Bool {
        await perform(issueID: issue.id) {
            _ = try await self.daemonConnection.withClient {
                try await $0.setIssueTodo(issueID: issue.id, date: date)
            }
        }
    }

    func clearDueDate(issue: DailyFocusIssue) async -> Bool {
        await perform(issueID: issue.id) {
            _ = try await self.daemonConnection.withClient {
                try await $0.clearIssueTodo(issueID: issue.id)
            }
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func perform(
        issueID: Int64,
        operation: @escaping () async throws -> Void
    ) async -> Bool {
        guard actionInFlightIssueID == nil else { return false }
        actionInFlightIssueID = issueID
        lastErrorMessage = nil
        defer { actionInFlightIssueID = nil }

        do {
            try await operation()
            await dailyFocusService.refresh()
            transitionsByIssueID[issueID] = nil
            synchronize(issues: dailyFocusService.snapshot.issues, force: true)
            return true
        } catch {
            logger.error(
                "Issue action failed for issue \(issueID, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .private)"
            )
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private static func normalizedStatus(_ status: String) -> String {
        switch status {
        case "todo": return CronaIssueStatus.backlog.rawValue
        case "active": return CronaIssueStatus.inProgress.rawValue
        default: return status
        }
    }
}

enum CronaCalendarDate {
    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func date(from value: String) -> Date? {
        let components = value.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))
    }

    static func string(from date: Date) -> String {
        formatter().string(from: date)
    }

    static func adding(days: Int, to value: String) -> String? {
        guard let date = date(from: value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        guard let result = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return string(from: result)
    }
}
