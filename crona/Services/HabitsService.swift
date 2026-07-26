import Combine
import Foundation
import OSLog

struct HabitRowModel: Equatable, Identifiable {
    let id: Int64
    let name: String
    let repoName: String
    let streamName: String
    let status: String
    let completed: Bool
    let durationMinutes: Int?
    let targetMinutes: Int?

    var supportsClearAction: Bool {
        completed || status == "failed"
    }
}

struct HabitsSnapshot: Equatable {
    var date = ""
    var items: [HabitRowModel] = []
    var isConnected = false
    var isLoading = false
    var lastRefreshError: String?
}

@MainActor
final class HabitsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.crona.macos", category: "habits")

    @Published var snapshot = HabitsSnapshot()
    @Published private(set) var actionInFlightHabitID: Int64?
    @Published private(set) var actionInFlightStatus: String?

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
            self?.logger.debug("Habits refresh triggered by daemon connect")
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
        let date = DailyFocusService.todayString()
        snapshot.date = date
        snapshot.isLoading = true

        do {
            logger.debug("Refreshing due habits for date: \(date, privacy: .public)")
            let items = try await daemonConnection.withClient { try await $0.listDueHabits(date: date) }
            snapshot = HabitsSnapshot(
                date: date,
                items: items.map(Self.project),
                isConnected: true,
                isLoading: false,
                lastRefreshError: nil
            )
            logger.debug("Applied due habits: \(items.count, privacy: .public)")
        } catch {
            logger.error("Habits refresh failed: \(error.localizedDescription, privacy: .public)")
            snapshot.isLoading = false
            snapshot.isConnected = false
            snapshot.lastRefreshError = error.localizedDescription
        }
    }

    func complete(_ habit: HabitRowModel, durationMinutes: Int? = nil) async {
        await setStatus(
            habit,
            status: "completed",
            durationMinutes: durationMinutes
        )
    }

    func fail(_ habit: HabitRowModel) async {
        await setStatus(habit, status: "failed", durationMinutes: nil)
    }

    private func setStatus(
        _ habit: HabitRowModel,
        status: String,
        durationMinutes: Int?
    ) async {
        guard actionInFlightHabitID == nil else { return }
        actionInFlightHabitID = habit.id
        actionInFlightStatus = status
        snapshot.lastRefreshError = nil

        do {
            let date = snapshot.date.isEmpty ? DailyFocusService.todayString() : snapshot.date
            logger.debug("Setting habit id=\(habit.id, privacy: .public) status=\(status, privacy: .public) date=\(date, privacy: .public)")
            _ = try await daemonConnection.withClient {
                try await $0.completeHabit(
                    habitID: habit.id,
                    date: date,
                    status: status,
                    durationMinutes: durationMinutes
                )
            }
            await refresh()
            actionInFlightHabitID = nil
            actionInFlightStatus = nil
        } catch {
            logger.error("Habit status failed for id=\(habit.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            actionInFlightHabitID = nil
            actionInFlightStatus = nil
            snapshot.lastRefreshError = error.localizedDescription
        }
    }

    func clearCompletion(_ habit: HabitRowModel) async {
        guard actionInFlightHabitID == nil else { return }
        actionInFlightHabitID = habit.id
        actionInFlightStatus = "clear"
        snapshot.lastRefreshError = nil

        do {
            let date = snapshot.date.isEmpty ? DailyFocusService.todayString() : snapshot.date
            logger.debug("Clearing habit completion id=\(habit.id, privacy: .public) date=\(date, privacy: .public)")
            _ = try await daemonConnection.withClient {
                try await $0.uncompleteHabit(habitID: habit.id, date: date)
            }
            await refresh()
            actionInFlightHabitID = nil
            actionInFlightStatus = nil
        } catch {
            logger.error("Habit uncomplete failed for id=\(habit.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            actionInFlightHabitID = nil
            actionInFlightStatus = nil
            snapshot.lastRefreshError = error.localizedDescription
        }
    }

    static func shouldRefresh(for eventType: String) -> Bool {
        switch eventType {
        case "habit.created", "habit.updated", "habit.deleted", "habit.completed", "habit.uncompleted", "session.ended":
            return true
        default:
            return false
        }
    }

    private func handle(event: CronaProtocolEvent) {
        guard Self.shouldRefresh(for: event.type) else { return }
        logger.debug("Habits refresh triggered by event: \(event.type, privacy: .public)")
        Task { await refresh() }
    }

    private static func project(_ item: CronaHabitDailyItem) -> HabitRowModel {
        HabitRowModel(
            id: item.id,
            name: item.name,
            repoName: item.repoName,
            streamName: item.streamName,
            status: item.status,
            completed: item.completed,
            durationMinutes: item.durationMinutes,
            targetMinutes: item.targetMinutes
        )
    }
}
