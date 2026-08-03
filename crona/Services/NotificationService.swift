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

enum CompanionAlertRouting {
    static let timerCompletionKinds: Set<String> = [
        "timer.work_complete",
        "timer.break_complete"
    ]

    static let reminderKinds: Set<String> = [
        "checkin.reminder",
        "daily_plan.reminder"
    ]

    static let checkInReminderCategory = "crona.reminder.check-in"
    static let dailyPlanReminderCategory = "crona.reminder.daily-plan"
    static let exportCompletedCategory = "crona.export.completed"

    static func isTimerCompletion(kind: String) -> Bool {
        timerCompletionKinds.contains(kind)
    }

    static func isReminder(kind: String) -> Bool {
        reminderKinds.contains(kind)
    }

    static func isExportCompleted(kind: String) -> Bool {
        kind == "export.completed"
    }

    static func shouldOpenTUI(kind: String) -> Bool {
        isReminder(kind: kind)
    }

    static func reminderCategoryIdentifier(for kind: String) -> String {
        switch kind {
        case "daily_plan.reminder":
            return dailyPlanReminderCategory
        default:
            return checkInReminderCategory
        }
    }
}

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private enum Category {
        static let open = "crona.open"
        static let startBreak = "crona.timer.start-break"
        static let resumeFocus = "crona.timer.resume-focus"
        static let checkInReminder = CompanionAlertRouting.checkInReminderCategory
        static let dailyPlanReminder = CompanionAlertRouting.dailyPlanReminderCategory
        static let exportCompleted = CompanionAlertRouting.exportCompletedCategory
    }

    private enum Action {
        static let open = "crona.action.open"
        static let startBreak = "crona.action.start-break"
        static let resumeFocus = "crona.action.resume-focus"
        static let openCheckIn = "crona.action.open-check-in"
        static let openDailyPlan = "crona.action.open-daily-plan"
        static let openExport = "crona.action.export.open"
        static let revealExport = "crona.action.export.reveal"
        static let dismiss = "crona.action.dismiss"
    }

    private let center: UNUserNotificationCenter
    private let clientID = UUID().uuidString
    private let logger = Logger(subsystem: "com.crona.macos", category: "notifications")
    private weak var daemonConnection: DaemonConnectionService?
    private var deliveryTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var deliveryTaskGeneration: UInt64 = 0
    private var daemonStateCancellables: Set<AnyCancellable> = []
    private var appActivationObserver: NSObjectProtocol?
    private var activeSound: NSSound?
    private var onOpenCrona: (() -> Void)?
    private var onOpenTUI: (() -> Void)?
    private var onAdvanceTimer: ((String) -> Void)?
    private var onFocusInactivity: ((CronaAlertDelivery) async -> Bool)?
    private var shouldSilenceAlert: ((String) -> Bool)?

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
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
        onOpenTUI: @escaping () -> Void,
        onAdvanceTimer: @escaping (String) -> Void,
        onFocusInactivity: @escaping (CronaAlertDelivery) async -> Bool,
        shouldSilenceAlert: @escaping (String) -> Bool
    ) {
        self.daemonConnection = daemonConnection
        self.onOpenCrona = onOpenCrona
        self.onOpenTUI = onOpenTUI
        self.onAdvanceTimer = onAdvanceTimer
        self.onFocusInactivity = onFocusInactivity
        self.shouldSilenceAlert = shouldSilenceAlert

        daemonStateCancellables.removeAll()
        Publishers.CombineLatest(
            daemonConnection.$connectionState.removeDuplicates(),
            daemonConnection.$alertStatus
                .map { $0?.companionDeliverySupported }
                .removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.reconcileDelivery()
        }
        .store(in: &daemonStateCancellables)
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
        cancelDeliveryTask()
        retryTask?.cancel()
        retryTask = nil
        setDeliveryState(.unavailable)
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    func refreshAuthorizationStatus() {
        Task {
            let settings = await center.notificationSettings()
            setAuthorizationStatus(settings.authorizationStatus)
            setSoundSetting(settings.soundSetting)
            reconcileDelivery()
        }
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            setLastErrorDescription(error.localizedDescription)
        }
        refreshAuthorizationStatus()
    }

    func reconcileDelivery() {
        guard canClaimDelivery else {
            guard deliveryTask != nil || retryTask != nil || deliveryState != .unavailable else {
                return
            }
            cancelDeliveryTask()
            retryTask?.cancel()
            retryTask = nil
            setDeliveryState(.unavailable)
            return
        }
        guard deliveryTask == nil else { return }
        guard let client = daemonConnection?.client else { return }

        retryTask?.cancel()
        retryTask = nil
        setDeliveryState(.connecting)
        deliveryTaskGeneration &+= 1
        let generation = deliveryTaskGeneration
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
                setDeliveryState(.active)
                setLastErrorDescription(nil)
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
                setLastErrorDescription(error.localizedDescription)
                setDeliveryState(.failed)
                logger.error("Native alert stream failed: \(error.localizedDescription, privacy: .private)")
            }
            guard deliveryTaskGeneration == generation else { return }
            deliveryTask = nil
            daemonConnection?.alertStatus = try? await client.alertsStatusGet()
            scheduleRetry()
        }
    }

    @discardableResult
    func setDeliveryState(_ state: NativeAlertDeliveryState) -> Bool {
        guard deliveryState != state else { return false }
        deliveryState = state
        return true
    }

    private func setAuthorizationStatus(_ status: UNAuthorizationStatus) {
        guard authorizationStatus != status else { return }
        authorizationStatus = status
    }

    private func setSoundSetting(_ setting: UNNotificationSetting) {
        guard soundSetting != setting else { return }
        soundSetting = setting
    }

    private func setLastErrorDescription(_ description: String?) {
        guard lastErrorDescription != description else { return }
        lastErrorDescription = description
    }

    private func cancelDeliveryTask() {
        guard let deliveryTask else { return }
        deliveryTaskGeneration &+= 1
        deliveryTask.cancel()
        self.deliveryTask = nil
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

        if CompanionAlertRouting.isTimerCompletion(kind: delivery.alert.kind) {
            if delivery.deliverNotification {
                onOpenCrona?()
            }
            if delivery.playSound && !silence {
                soundAccepted = playSound(for: delivery.alert.soundPreset)
            } else if delivery.playSound && silence {
                soundAccepted = true
            }
            notificationAccepted = true
            await acknowledge(
                delivery: delivery,
                client: client,
                notificationAccepted: notificationAccepted,
                soundAccepted: soundAccepted
            )
            return
        }

        if delivery.alert.kind == "focus.inactivity",
            await onFocusInactivity?(delivery) == true
        {
            notificationAccepted = true
            if delivery.playSound {
                soundAccepted = playSound(for: delivery.alert.soundPreset)
            }
            await acknowledge(delivery: delivery, client: client, notificationAccepted: notificationAccepted, soundAccepted: soundAccepted)
            return
        }

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
                logger.error("Failed to schedule native notification: \(error.localizedDescription, privacy: .private)")
            }
        } else if delivery.playSound {
            soundAccepted = playSound(for: delivery.alert.soundPreset)
        }

        await acknowledge(delivery: delivery, client: client, notificationAccepted: notificationAccepted, soundAccepted: soundAccepted)
    }

    private func acknowledge(
        delivery: CronaAlertDelivery,
        client: CronaDaemonClient,
        notificationAccepted: Bool,
        soundAccepted: Bool
    ) async {
        do {
            _ = try await client.acknowledgeAlertDelivery(
                CronaAlertDeliveryAck(
                    deliveryID: delivery.id,
                    notificationAccepted: notificationAccepted,
                    soundAccepted: soundAccepted
                )
            )
        } catch {
            logger.error("Failed to acknowledge native notification: \(error.localizedDescription, privacy: .private)")
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
            "actionPath": delivery.actions?.first?.path ?? "",
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
        if CompanionAlertRouting.isReminder(kind: delivery.alert.kind) {
            return CompanionAlertRouting.reminderCategoryIdentifier(for: delivery.alert.kind)
        }
        if CompanionAlertRouting.isExportCompleted(kind: delivery.alert.kind) {
            let hasFileAction = delivery.actions?.contains(where: { action in
                let path = (action.path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !path.isEmpty
            }) == true
            if hasFileAction {
                return Category.exportCompleted
            }
        }
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
        let openCheckIn = UNNotificationAction(
            identifier: Action.openCheckIn,
            title: "Open Check-In"
        )
        let openDailyPlan = UNNotificationAction(
            identifier: Action.openDailyPlan,
            title: "Open Daily Plan"
        )
        let openExport = UNNotificationAction(
            identifier: Action.openExport,
            title: "Open File"
        )
        let revealExport = UNNotificationAction(
            identifier: Action.revealExport,
            title: "Reveal in Finder"
        )
        let dismiss = UNNotificationAction(
            identifier: Action.dismiss,
            title: "Dismiss",
            options: [.destructive]
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
            ),
            UNNotificationCategory(
                identifier: Category.checkInReminder,
                actions: [openCheckIn, dismiss],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.dailyPlanReminder,
                actions: [openDailyPlan, dismiss],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.exportCompleted,
                actions: [openExport, revealExport, dismiss],
                intentIdentifiers: []
            )
        ])
    }

    private func threadIdentifier(for kind: String) -> String {
        if kind.hasPrefix("timer.") || kind.hasPrefix("focus.") {
            return "focus"
        }
        if kind.hasPrefix("export.") {
            return "exports"
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
        let actionPath = response.notification.request.content.userInfo["actionPath"] as? String
        let kind = response.notification.request.content.userInfo["kind"] as? String ?? ""
        let actionIdentifier = response.actionIdentifier
        await MainActor.run { [weak self] in
            guard let self else { return }
            if CompanionAlertRouting.isExportCompleted(kind: kind) {
                switch actionIdentifier {
                case Action.openExport, UNNotificationDefaultActionIdentifier:
                    if let url = exportActionURL(for: actionPath) {
                        openExportFile(url)
                    } else {
                        onOpenCrona?()
                    }
                case Action.revealExport:
                    if let url = exportActionURL(for: actionPath) {
                        revealExportFile(url)
                    } else {
                        onOpenCrona?()
                    }
                case Action.dismiss, UNNotificationDismissActionIdentifier:
                    break
                default:
                    if let url = exportActionURL(for: actionPath) {
                        openExportFile(url)
                    } else {
                        onOpenCrona?()
                    }
                }
                return
            }
            switch actionIdentifier {
            case Action.startBreak, Action.resumeFocus:
                if let expected, !expected.isEmpty {
                    onAdvanceTimer?(expected)
                }
            case Action.openDailyPlan:
                onOpenTUI?()
            case Action.openCheckIn, Action.open, UNNotificationDefaultActionIdentifier:
                if CompanionAlertRouting.shouldOpenTUI(kind: kind) {
                    onOpenTUI?()
                } else {
                    onOpenCrona?()
                }
            case Action.dismiss, UNNotificationDismissActionIdentifier:
                break
            default:
                if CompanionAlertRouting.shouldOpenTUI(kind: kind) {
                    onOpenTUI?()
                } else {
                    onOpenCrona?()
                }
            }
        }
    }

    private func exportActionURL(for rawPath: String?) -> URL? {
        guard let rawPath else { return nil }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func openExportFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func revealExportFile(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
