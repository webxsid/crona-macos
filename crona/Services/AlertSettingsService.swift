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
            logger.error("Failed to load alert settings: \(error.localizedDescription, privacy: .public)")
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
            logger.error("Failed to save alert settings: \(error.localizedDescription, privacy: .public)")
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
