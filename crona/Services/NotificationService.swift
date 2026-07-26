import AppKit
import Combine
import Foundation
import OSLog
import UserNotifications

enum NativeAlertDeliveryState: String {
    case unavailable
    case connecting
    case active
    case failed
}

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private enum Category {
        static let open = "crona.open"
        static let startBreak = "crona.timer.start-break"
        static let resumeFocus = "crona.timer.resume-focus"
    }

    private enum Action {
        static let open = "crona.action.open"
        static let startBreak = "crona.action.start-break"
        static let resumeFocus = "crona.action.resume-focus"
    }

    private let center: UNUserNotificationCenter
    private let clientID = UUID().uuidString
    private let logger = Logger(subsystem: "com.crona.macos", category: "notifications")
    private weak var daemonConnection: DaemonConnectionService?
    private var deliveryTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var appActivationObserver: NSObjectProtocol?
    private var activeSound: NSSound?
    private var onOpenCrona: (() -> Void)?
    private var onAdvanceTimer: ((String) -> Void)?
    private var shouldSilenceAlert: ((String) -> Bool)?

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var soundSetting: UNNotificationSetting = .notSupported
    @Published private(set) var deliveryState: NativeAlertDeliveryState = .unavailable
    @Published private(set) var lastErrorDescription: String?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        registerCategories()
    }

    func configure(
        daemonConnection: DaemonConnectionService,
        onOpenCrona: @escaping () -> Void,
        onAdvanceTimer: @escaping (String) -> Void,
        shouldSilenceAlert: @escaping (String) -> Bool
    ) {
        self.daemonConnection = daemonConnection
        self.onOpenCrona = onOpenCrona
        self.onAdvanceTimer = onAdvanceTimer
        self.shouldSilenceAlert = shouldSilenceAlert
    }

    func start() {
        guard appActivationObserver == nil else { return }
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAuthorizationStatus()
            }
        }
        refreshAuthorizationStatus()
    }

    func stop() {
        deliveryTask?.cancel()
        retryTask?.cancel()
        deliveryTask = nil
        retryTask = nil
        deliveryState = .unavailable
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    func refreshAuthorizationStatus() {
        Task {
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            soundSetting = settings.soundSetting
            reconcileDelivery()
        }
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            lastErrorDescription = error.localizedDescription
        }
        refreshAuthorizationStatus()
    }

    func reconcileDelivery() {
        guard canClaimDelivery, deliveryTask == nil else {
            if !canClaimDelivery {
                deliveryTask?.cancel()
                deliveryTask = nil
                retryTask?.cancel()
                retryTask = nil
                deliveryState = .unavailable
            }
            return
        }
        guard let client = daemonConnection?.client else { return }

        retryTask?.cancel()
        retryTask = nil
        deliveryState = .connecting
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await client.subscribeToAlertDeliveries(
                    capabilities: CronaAlertDeliveryCapability(
                        clientID: clientID,
                        notifications: true,
                        sounds: true
                    )
                )
                deliveryState = .active
                lastErrorDescription = nil
                daemonConnection?.alertStatus = try? await client.alertsStatusGet()
                for try await event in stream {
                    if Task.isCancelled { break }
                    guard event.type == "alert.delivery" else { continue }
                    let delivery = try event.decodePayload(CronaAlertDelivery.self)
                    await handle(delivery, client: client)
                }
            } catch is CancellationError {
                // Expected when authorization, connection, or app lifetime changes.
            } catch {
                lastErrorDescription = error.localizedDescription
                deliveryState = .failed
                logger.error("Native alert stream failed: \(error.localizedDescription, privacy: .public)")
            }
            deliveryTask = nil
            daemonConnection?.alertStatus = try? await client.alertsStatusGet()
            scheduleRetry()
        }
    }

    func playPresetPreview(_ preset: String) {
        guard let url = soundURL(for: preset) else {
            NSSound.beep()
            return
        }
        activeSound?.stop()
        activeSound = NSSound(contentsOf: url, byReference: true)
        activeSound?.play()
    }

    func openSystemNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var canClaimDelivery: Bool {
        guard daemonConnection?.connectionState == .connected else { return false }
        guard daemonConnection?.alertStatus?.companionDeliverySupported == true else { return false }
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func scheduleRetry() {
        guard canClaimDelivery, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            retryTask = nil
            reconcileDelivery()
        }
    }

    private func handle(_ delivery: CronaAlertDelivery, client: CronaDaemonClient) async {
        var notificationAccepted = !delivery.deliverNotification
        var soundAccepted = !delivery.playSound
        let silence = shouldSilenceAlert?(delivery.alert.kind) == true
        let notificationCenterCanPlaySound = soundSetting == .enabled

        if delivery.deliverNotification {
            do {
                let content = notificationContent(
                    for: delivery,
                    silencePresentation: silence,
                    attachSound: !silence && notificationCenterCanPlaySound
                )
                let request = UNNotificationRequest(
                    identifier: delivery.id,
                    content: content,
                    trigger: nil
                )
                try await center.add(request)
                notificationAccepted = true
                if delivery.playSound {
                    if silence {
                        soundAccepted = true
                    } else if notificationCenterCanPlaySound {
                        soundAccepted = true
                    } else {
                        soundAccepted = playSound(for: delivery.alert.soundPreset)
                    }
                }
            } catch {
                logger.error("Failed to schedule native notification: \(error.localizedDescription, privacy: .public)")
            }
        } else if delivery.playSound {
            soundAccepted = playSound(for: delivery.alert.soundPreset)
        }

        do {
            _ = try await client.acknowledgeAlertDelivery(
                CronaAlertDeliveryAck(
                    deliveryID: delivery.id,
                    notificationAccepted: notificationAccepted,
                    soundAccepted: soundAccepted
                )
            )
        } catch {
            logger.error("Failed to acknowledge native notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func notificationContent(
        for delivery: CronaAlertDelivery,
        silencePresentation: Bool,
        attachSound: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = delivery.alert.title
        content.subtitle = delivery.alert.subtitle ?? ""
        content.body = delivery.alert.body
        content.threadIdentifier = threadIdentifier(for: delivery.alert.kind)
        content.interruptionLevel = interruptionLevel(for: delivery.alert.urgency)
        content.categoryIdentifier = categoryIdentifier(for: delivery)
        content.userInfo = [
            "kind": delivery.alert.kind,
            "expectedReadySegmentType":
                delivery.actions?.first?.expectedReadySegmentType ?? "",
            "silenceForeground": silencePresentation
        ]
        if delivery.playSound && attachSound {
            if let filename = soundFilename(for: delivery.alert.soundPreset) {
                content.sound = UNNotificationSound(
                    named: UNNotificationSoundName(rawValue: filename)
                )
            } else {
                content.sound = .default
            }
        }
        return content
    }

    private func categoryIdentifier(for delivery: CronaAlertDelivery) -> String {
        guard let action = delivery.actions?.first else { return Category.open }
        switch action.expectedReadySegmentType {
        case "short_break", "long_break":
            return Category.startBreak
        case "work":
            return Category.resumeFocus
        default:
            return Category.open
        }
    }

    private func registerCategories() {
        let open = UNNotificationAction(identifier: Action.open, title: "Open Crona")
        let startBreak = UNNotificationAction(
            identifier: Action.startBreak,
            title: "Start Break"
        )
        let resumeFocus = UNNotificationAction(
            identifier: Action.resumeFocus,
            title: "Resume Focus"
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.open,
                actions: [open],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.startBreak,
                actions: [startBreak, open],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.resumeFocus,
                actions: [resumeFocus, open],
                intentIdentifiers: []
            )
        ])
    }

    private func threadIdentifier(for kind: String) -> String {
        if kind.hasPrefix("timer.") || kind.hasPrefix("focus.") {
            return "focus"
        }
        if kind.hasPrefix("update.") { return "updates" }
        if kind.contains("reminder") { return "reminders" }
        return "crona"
    }

    private func interruptionLevel(for urgency: String) -> UNNotificationInterruptionLevel {
        switch urgency {
        case "low": return .passive
        case "high": return .timeSensitive
        default: return .active
        }
    }

    private func playSound(for preset: String?) -> Bool {
        guard let url = soundURL(for: preset) else { return false }
        activeSound?.stop()
        activeSound = NSSound(contentsOf: url, byReference: true)
        return activeSound?.play() == true
    }

    private func soundURL(for preset: String?) -> URL? {
        guard let filename = soundFilename(for: preset) else { return nil }
        return Bundle.main.url(
            forResource: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
            withExtension: "caf"
        )
    }

    private func soundFilename(for preset: String?) -> String? {
        switch preset {
        case "soft_bell": return "soft-bell.caf"
        case "notification_ping": return "notification-ping.caf"
        case "focus_gong": return "focus-gong.caf"
        case "minimal_click": return "minimal-click.caf"
        case "chime", nil: return "chime.caf"
        default: return nil
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.userInfo["silenceForeground"] as? Bool == true {
            return [.list]
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let expected =
            response.notification.request.content.userInfo["expectedReadySegmentType"]
            as? String
        await MainActor.run { [weak self] in
            guard let self else { return }
            switch response.actionIdentifier {
            case Action.startBreak, Action.resumeFocus:
                if let expected, !expected.isEmpty {
                    onAdvanceTimer?(expected)
                }
            default:
                onOpenCrona?()
            }
        }
    }
}
