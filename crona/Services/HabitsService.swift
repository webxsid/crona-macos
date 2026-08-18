import Combine
import Foundation
import OSLog

struct HabitRowModel: Equatable, Identifiable {
    let id: Int64
    let name: String
    let repoName: String
    let streamName: String
    let active: Bool
    let status: String
    let completed: Bool
    let durationMinutes: Int?
    let targetMinutes: Int?
    let description: String?
    let scheduleType: String?
    let weekdays: [Int]
    let notes: String?
    let completionDate: String?
    let completionID: Int64?

    init(
        id: Int64,
        name: String,
        repoName: String,
        streamName: String,
        active: Bool = true,
        status: String,
        completed: Bool,
        durationMinutes: Int?,
        targetMinutes: Int?,
        description: String? = nil,
        scheduleType: String? = nil,
        weekdays: [Int] = [],
        notes: String? = nil,
        completionDate: String? = nil,
        completionID: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.repoName = repoName
        self.streamName = streamName
        self.active = active
        self.status = status
        self.completed = completed
        self.durationMinutes = durationMinutes
        self.targetMinutes = targetMinutes
        self.description = description
        self.scheduleType = scheduleType
        self.weekdays = weekdays
        self.notes = notes
        self.completionDate = completionDate
        self.completionID = completionID
    }

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
    @Published private(set) var isManagingHabit = false
    @Published private(set) var lastManagementError: String?

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

    isolated deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
    }

    func refresh(date requestedDate: String? = nil) async {
        let daemonDate = requestedDate ?? daemonConnection.currentDate
        let date = daemonDate.isEmpty ? DailyFocusService.todayString() : daemonDate
        snapshot.date = date
        snapshot.isLoading = true

        do {
            logger.debug("Refreshing due habits for date: \(date, privacy: .private)")
            let items = try await daemonConnection.withClient {
                try await $0.listDueHabits(date: date)
            }
            snapshot = HabitsSnapshot(
                date: date,
                items: items.map(Self.project),
                isConnected: true,
                isLoading: false,
                lastRefreshError: nil
            )
            logger.debug("Applied due habits: \(items.count, privacy: .public)")
        } catch {
            logger.error("Habits refresh failed: \(error.localizedDescription, privacy: .private)")
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
            logger.debug(
                "Setting habit id=\(habit.id, privacy: .private(mask: .hash)) status=\(status, privacy: .public) date=\(date, privacy: .private)"
            )
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
            logger.error(
                "Habit status failed for id=\(habit.id, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .private)"
            )
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
            logger.debug(
                "Clearing habit completion id=\(habit.id, privacy: .private(mask: .hash)) date=\(date, privacy: .private)"
            )
            _ = try await daemonConnection.withClient {
                try await $0.uncompleteHabit(habitID: habit.id, date: date)
            }
            await refresh()
            actionInFlightHabitID = nil
            actionInFlightStatus = nil
        } catch {
            logger.error(
                "Habit uncomplete failed for id=\(habit.id, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .private)"
            )
            actionInFlightHabitID = nil
            actionInFlightStatus = nil
            snapshot.lastRefreshError = error.localizedDescription
        }
    }

    func create(
        _ request: CronaCreateHabitRequest,
        refreshDate: String
    ) async -> Bool {
        guard !isManagingHabit else { return false }
        isManagingHabit = true
        lastManagementError = nil
        defer { isManagingHabit = false }
        do {
            _ = try await daemonConnection.withClient { try await $0.createHabit(request) }
            await refresh(date: refreshDate)
            return true
        } catch {
            logger.error("Creating habit failed: \(error.localizedDescription, privacy: .private)")
            lastManagementError = error.localizedDescription
            return false
        }
    }

    func update(_ request: CronaUpdateHabitRequest, refreshDate: String) async -> Bool {
        guard !isManagingHabit else { return false }
        isManagingHabit = true
        lastManagementError = nil
        defer { isManagingHabit = false }
        do {
            _ = try await daemonConnection.withClient { try await $0.updateHabit(request) }
            await refresh(date: refreshDate)
            return true
        } catch {
            logger.error("Updating habit failed: \(error.localizedDescription, privacy: .private)")
            lastManagementError = error.localizedDescription
            return false
        }
    }

    func delete(_ habit: HabitRowModel, refreshDate: String) async -> Bool {
        guard !isManagingHabit else { return false }
        isManagingHabit = true
        lastManagementError = nil
        defer { isManagingHabit = false }
        do {
            _ = try await daemonConnection.withClient { try await $0.deleteHabit(habitID: habit.id) }
            await refresh(date: refreshDate)
            return true
        } catch {
            logger.error("Deleting habit failed: \(error.localizedDescription, privacy: .private)")
            lastManagementError = error.localizedDescription
            return false
        }
    }

    func clearManagementError() {
        lastManagementError = nil
    }

    static func shouldRefresh(for eventType: String) -> Bool {
        switch eventType {
        case "habit.created", "habit.updated", "habit.deleted", "habit.completed",
            "habit.uncompleted", "session.ended":
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
            active: item.habit.active,
            status: item.status,
            completed: item.completed,
            durationMinutes: item.durationMinutes,
            targetMinutes: item.targetMinutes,
            description: item.habit.description,
            scheduleType: item.habit.scheduleType,
            weekdays: item.habit.weekdays,
            notes: item.notes,
            completionDate: item.completionDate,
            completionID: item.completionID
        )
    }
}
