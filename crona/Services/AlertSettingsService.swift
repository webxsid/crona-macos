import AppKit
import Combine
import Foundation
import OSLog

@MainActor
final class AlertSettingsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let logger = Logger(subsystem: "com.crona.macos", category: "alert-settings")
    private var authoritativeSettings: CronaAlertSettings?
    private var pendingValues: [String: JSONValue] = [:]
    private var saveTask: Task<Void, Never>?

    @Published private(set) var settings: CronaAlertSettings?
    @Published private(set) var isSaving = false
    @Published private(set) var lastErrorDescription: String?

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
    }

    func refresh() async {
        guard daemonConnection.connectionState == .connected else {
            authoritativeSettings = nil
            pendingValues.removeAll()
            settings = nil
            return
        }
        do {
            authoritativeSettings = try await daemonConnection.withClient { client in
                try await client.alertSettingsGet()
            }
            publishProjectedSettings()
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
            logger.error("Failed to load alert settings: \(error.localizedDescription, privacy: .private)")
        }
    }

    func update(_ values: [String: JSONValue]) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            for (key, value) in values {
                self.enqueueUpdate(key: key, value: value)
            }
        }
    }

    private func enqueueUpdate(key: String, value: JSONValue) {
        guard authoritativeSettings != nil else { return }
        logger.debug(
            "Selected alert setting \(key, privacy: .public)=\(value.logDescription, privacy: .public)"
        )
        pendingValues[key] = value
        publishProjectedSettings()
        isSaving = true

        let precedingTask = saveTask
        saveTask = Task { [weak self] in
            await precedingTask?.value
            guard !Task.isCancelled, let self else { return }
            await self.persist(key: key, value: value)
        }
    }

    private func persist(key: String, value: JSONValue) async {
        do {
            let refreshed = try await daemonConnection.withClient { client in
                try await client.alertSettingPatch(key: key, value: value)
                return try await client.alertSettingsGet()
            }
            authoritativeSettings = refreshed
            if pendingValues[key] == value {
                pendingValues.removeValue(forKey: key)
            }
            logger.debug(
                "Persisted alert setting \(key, privacy: .public)=\(value.logDescription, privacy: .public)"
            )
            logger.debug(
                "Daemon alert settings reconciled sound=\(refreshed.alertSoundPreset.rawValue, privacy: .public) prominence=\(refreshed.alertUrgency.rawValue, privacy: .public)"
            )
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
            logger.error("Failed to save alert settings: \(error.localizedDescription, privacy: .private)")
            if pendingValues[key] == value {
                pendingValues.removeValue(forKey: key)
            }
        }
        publishProjectedSettings()
        isSaving = !pendingValues.isEmpty
        logger.debug(
            "Reconciled alert setting \(key, privacy: .public); pending=\(self.pendingValues.count, privacy: .public)"
        )
    }

    private func publishProjectedSettings() {
        settings = pendingValues.reduce(authoritativeSettings) { projected, entry in
            projected?.applying(key: entry.key, value: entry.value)
        }
    }

    func setBoolean(_ key: String, value: Bool) {
        update([key: .bool(value)])
    }

    func setString(_ key: String, value: String) {
        update([key: .string(value)])
    }

    func setInteger(_ key: String, value: Int) {
        update([key: .number(Double(value))])
    }

    func setSoundPreset(_ value: CronaAlertSoundPreset) {
        setString("alertSoundPreset", value: value.rawValue)
    }

    func setProminence(_ value: CronaAlertProminence) {
        setString("alertUrgency", value: value.rawValue)
    }
}

@MainActor
final class DayBoundarySettingsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let logger = Logger(subsystem: "com.crona.macos", category: "day-boundary-settings")

    @Published private(set) var settings = CronaDayBoundarySettings()
    @Published private(set) var isSaving = false
    @Published private(set) var lastErrorDescription: String?

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
    }

    func refresh() async {
        guard daemonConnection.connectionState == .connected else { return }
        do {
            settings = try await daemonConnection.withClient { client in
                try await client.dayBoundarySettingsGet()
            }
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
            logger.error("Failed to load day-boundary settings: \(error.localizedDescription, privacy: .private)")
        }
    }

    func setSchedule(_ key: String, schedule: CronaDayBoundarySchedule) {
        guard schedule.isValid else {
            lastErrorDescription = "Enter times using HH:mm format."
            return
        }

        var projected = settings
        if key == "startOfDay" {
            projected.startOfDay = schedule
        } else if key == "endOfDay" {
            projected.endOfDay = schedule
        } else {
            lastErrorDescription = "Unsupported day-boundary setting."
            return
        }
        settings = projected
        isSaving = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await daemonConnection.withClient { client in
                    try await client.dayBoundarySettingPatch(key: key, schedule: schedule)
                }
                await refresh()
                lastErrorDescription = nil
            } catch {
                lastErrorDescription = error.localizedDescription
                logger.error("Failed to save day-boundary setting: \(error.localizedDescription, privacy: .private)")
                await refresh()
            }
            isSaving = false
        }
    }
}

@MainActor
final class CoreSettingsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let logger = Logger(subsystem: "com.crona.macos", category: "core-settings")
    private var eventObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var refreshToken: UUID?

    @Published private(set) var settings = CronaCoreSettings()
    @Published private(set) var lastErrorDescription: String?
    @Published private(set) var isSaving = false

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
        eventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent,
                  event.type == "settings.changed"
            else { return }
            Task { await self?.refresh() }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    isolated deinit {
        if let eventObserver { NotificationCenter.default.removeObserver(eventObserver) }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    func refresh() async {
        guard daemonConnection.connectionState == .connected else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        let token = UUID()
        refreshTask = task
        refreshToken = token
        await task.value
        if refreshToken == token {
            refreshTask = nil
            refreshToken = nil
        }
    }

    private func performRefresh() async {
        do {
            settings = try await daemonConnection.withClient { try await $0.coreSettingsGet() }
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
            logger.error("Failed to load core settings: \(error.localizedDescription, privacy: .private)")
        }
    }

    func setAwayMode(_ enabled: Bool) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            await refresh()
            _ = try await daemonConnection.withClient { try await $0.setAwayMode(enabled: enabled) }
            await refresh()
        } catch {
            lastErrorDescription = error.localizedDescription
            logger.error("Failed to set away mode: \(error.localizedDescription, privacy: .private)")
        }
    }

    var todayIsAway: Bool {
        let date = daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString()
            : daemonConnection.currentDate
        return settings.awayModeEnabled || settings.isConfiguredRestDate(date)
    }

    func isHistoricalAwayDate(_ date: String) -> Bool {
        settings.isHistoricalAwayDate(date)
    }
}

private extension JSONValue {
    var logDescription: String {
        switch self {
        case let .string(value): return value
        case let .number(value): return String(value)
        case let .bool(value): return String(value)
        case .object: return "<object>"
        case .array: return "<array>"
        case .null: return "null"
        }
    }
}
