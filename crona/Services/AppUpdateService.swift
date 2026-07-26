import AppKit
import Combine
import Foundation
import Sparkle

struct AppUpdateSnapshot: Equatable {
    var currentVersion: String
    var currentBuild: String
    var installedChannel: AppReleaseChannel
    var latestVersion: String?
    var releaseNotesURL: URL?
    var lastCheckedAt: Date?
    var isChecking = false
    var updateAvailable = false
    var downloaded = false
    var errorMessage: String?

    static func current(bundle: Bundle = .main) -> Self {
        let bundleVersion = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Unknown"
        let releaseVersion = bundle.object(
            forInfoDictionaryKey: "CRONA_RELEASE_VERSION"
        ) as? String
        let configuredChannel = bundle.object(
            forInfoDictionaryKey: "CRONA_RELEASE_CHANNEL"
        ) as? String
        let effectiveVersion = releaseVersion.flatMap { value in
            value.isEmpty ? nil : value
        } ?? bundleVersion

        return Self(
            currentVersion: effectiveVersion,
            currentBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            installedChannel: AppReleaseChannel.resolved(
                configuredValue: configuredChannel,
                version: effectiveVersion
            )
        )
    }
}

@MainActor
final class AppUpdateService: NSObject, ObservableObject {
    private static let noUpdateErrorCode = 1001
    @Published private(set) var snapshot: AppUpdateSnapshot
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false

    private let preferences: PreferencesService
    private let enabled: Bool
    private var preferenceCancellables: Set<AnyCancellable> = []
    private var updaterCancellables: Set<AnyCancellable> = []
    private var updaterController: SPUStandardUpdaterController?
    private var availableUpdate: SUAppcastItem?
    private var shouldDeferScheduledPresentation: () -> Bool = { false }
    private var willPresentUpdateUI: () -> Void = {}
    private var didFinishUpdateUI: () -> Void = {}

    var selectedChannel: AppReleaseChannel {
        preferences.preferences.appUpdateChannel
            ?? snapshot.installedChannel
    }

    var hasAvailableUpdate: Bool {
        snapshot.updateAvailable
    }

    init(
        preferences: PreferencesService,
        bundle: Bundle = .main,
        enabled: Bool? = nil
    ) {
        self.preferences = preferences
        snapshot = .current(bundle: bundle)
        self.enabled = enabled
            ?? (bundle.object(forInfoDictionaryKey: "CRONA_UPDATES_ENABLED") as? Bool ?? false)
        super.init()

        preferences.$preferences
            .map(\.appUpdateChannel)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                self.updaterController?.updater.resetUpdateCycleAfterShortDelay()
                self.clearUnavailableChannelReminder()
            }
            .store(in: &preferenceCancellables)
    }

    func configurePresentation(
        shouldDefer: @escaping () -> Bool,
        willPresent: @escaping () -> Void,
        didFinish: @escaping () -> Void
    ) {
        shouldDeferScheduledPresentation = shouldDefer
        willPresentUpdateUI = willPresent
        didFinishUpdateUI = didFinish
    }

    func start() {
        guard enabled, updaterController == nil else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        updaterController = controller
        bindUpdater(controller.updater)
        controller.startUpdater()
    }

    func stop() {
        updaterCancellables.removeAll()
        updaterController = nil
        canCheckForUpdates = false
        automaticallyChecksForUpdates = false
        automaticallyDownloadsUpdates = false
    }

    func setChannel(_ channel: AppReleaseChannel) {
        guard selectedChannel != channel else { return }
        preferences.preferences.appUpdateChannel = channel
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController?.updater.automaticallyDownloadsUpdates = enabled
    }

    func checkForUpdates() {
        guard let controller = updaterController, controller.updater.canCheckForUpdates else { return }
        snapshot.isChecking = true
        snapshot.errorMessage = nil
        controller.checkForUpdates(nil)
    }

    private func bindUpdater(_ updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &updaterCancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.automaticallyChecksForUpdates = value
            }
            .store(in: &updaterCancellables)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.automaticallyDownloadsUpdates = value
            }
            .store(in: &updaterCancellables)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.snapshot.lastCheckedAt = date
            }
            .store(in: &updaterCancellables)
    }

    private func recordAvailableUpdate(_ update: SUAppcastItem) {
        availableUpdate = update
        snapshot.latestVersion = update.displayVersionString
        snapshot.releaseNotesURL = update.releaseNotesURL
        snapshot.updateAvailable = true
        snapshot.errorMessage = nil
    }

    private func clearUnavailableChannelReminder() {
        guard selectedChannel == .stable, availableUpdate?.channel == AppReleaseChannel.beta.rawValue else {
            return
        }
        availableUpdate = nil
        snapshot.latestVersion = nil
        snapshot.releaseNotesURL = nil
        snapshot.updateAvailable = false
        snapshot.downloaded = false
    }
}

extension AppUpdateService: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        selectedChannel == .beta ? [AppReleaseChannel.beta.rawValue] : []
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        recordAvailableUpdate(item)
        snapshot.downloaded = true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordAvailableUpdate(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        snapshot.updateAvailable = false
        snapshot.downloaded = false
        snapshot.errorMessage = nil
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        snapshot.isChecking = false
        snapshot.lastCheckedAt = updater.lastUpdateCheckDate
        if let error = error as NSError?, error.code != Self.noUpdateErrorCode {
            snapshot.errorMessage = error.localizedDescription
        }
    }
}

extension AppUpdateService: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        recordAvailableUpdate(update)
        if handleShowingUpdate {
            willPresentUpdateUI()
        }
        if !state.userInitiated, shouldDeferScheduledPresentation() {
            return
        }
    }

    func standardUserDriverWillShowModalAlert() {
        willPresentUpdateUI()
    }

    func standardUserDriverWillFinishUpdateSession() {
        didFinishUpdateUI()
    }
}
