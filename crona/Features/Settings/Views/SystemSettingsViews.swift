import AppKit
import SwiftUI
import UserNotifications

struct RuntimeSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        SettingsCard("Discovery") {
            SettingsValueRow(
                title: "Runtime Directory",
                subtitle: "See where Crona looks for the running kernel.",
                value: appState.kernelDiscovery.loadedRuntime.config.runtimeDirectoryPath
            )
            SettingsValueRow(
                title: "Discovery File",
                subtitle: "kernel.json used for discovery.",
                value: appState.kernelDiscovery.loadedRuntime.config.discoveryFilePath
            )
            SettingsValueRow(
                title: "Endpoint",
                subtitle: "Socket used by the current connection.",
                value: appState.daemonConnection.kernelInfo?.endpoint ?? appState.kernelDiscovery
                    .loadedRuntime.resolvedDiscovery?.endpoint ?? "Unavailable"
            )

            SettingsActionGroup {
                SettingsActionButton("Reconnect", systemImage: "arrow.clockwise") {
                    appState.manualReconnect()
                }
            }
        }
    }
}

struct DiagnosticsSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Snapshot") {
                SettingsValueRow(
                    title: "Connection State",
                    subtitle: "Whether this app can reach the engine.",
                    value: appState.diagnosticsService.snapshot.connectionState
                )
                SettingsValueRow(
                    title: "Protocol Version",
                    subtitle: "Protocol shared by the app and engine.",
                    value: appState.diagnosticsService.snapshot.protocolVersion
                )
                SettingsValueRow(
                    title: "Kernel Version",
                    subtitle: "Engine build currently running.",
                    value: appState.diagnosticsService.snapshot.kernelVersion
                )
                SettingsValueRow(
                    title: "Runtime Directory",
                    subtitle: "Active Crona runtime location.",
                    value: appState.diagnosticsService.snapshot.runtimeDirectory
                )
                SettingsValueRow(
                    title: "Health",
                    subtitle: "Latest engine health report.",
                    value: appState.diagnosticsService.snapshot.healthSummary
                )
                SettingsValueRow(
                    title: "Last Reconnect",
                    subtitle: "When the app last found the kernel again.",
                    value: appState.diagnosticsService.snapshot.lastReconnect
                )
            }

            SettingsCard("Actions") {
                SettingsActionGroup {
                    SettingsActionButton(
                        "Copy Diagnostics", systemImage: "doc.on.doc", prominent: false
                    ) {
                        appState.diagnosticsService.copyToPasteboard()
                    }

                    SettingsActionButton("Reconnect", systemImage: "arrow.clockwise") {
                        appState.manualReconnect()
                    }
                }
            }
        }
        .onAppear {
            Task { await appState.diagnosticsService.refresh() }
        }
    }
}

struct UpdatesSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    private var service: AppUpdateService { appState.appUpdateService }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Installed") {
                SettingsValueRow(
                    title: "Crona",
                    subtitle: "Installed version and build.",
                    value: "\(service.snapshot.currentVersion) (\(service.snapshot.currentBuild))"
                )

                SettingsValueRow(
                    title: "Status",
                    subtitle: statusSubtitle,
                    value: statusValue
                )

                if let lastCheckedAt = service.snapshot.lastCheckedAt {
                    SettingsValueRow(
                        title: "Last Checked",
                        subtitle: "Most recent completed update check.",
                        value: lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            SettingsCard("Release Channel") {
                SettingsPickerRow(
                    title: "Channel",
                    subtitle:
                        "Choose Stable for dependable releases or Beta for early access plus every stable update.",
                    selection: Binding(
                        get: { service.selectedChannel },
                        set: { service.setChannel($0) }
                    )
                ) {
                    ForEach(AppReleaseChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }

                if service.selectedChannel == .stable,
                    service.snapshot.installedChannel == .beta
                {
                    settingsFootnote(
                        "You’ll stay on this build until a newer stable release is available."
                    )
                }
            }

            SettingsCard("Automatic Updates") {
                SettingsToggleRow(
                    title: "Check Automatically",
                    subtitle: "Look for releases in the background.",
                    isOn: Binding(
                        get: { service.automaticallyChecksForUpdates },
                        set: { service.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                SettingsToggleRow(
                    title: "Download Automatically",
                    subtitle: "Prepare verified updates before Crona quits.",
                    isOn: Binding(
                        get: { service.automaticallyDownloadsUpdates },
                        set: { service.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .disabled(!service.automaticallyChecksForUpdates)
                .opacity(service.automaticallyChecksForUpdates ? 1 : 0.5)
            }

            SettingsCard("Check Now") {
                SettingsActionGroup {
                    SettingsActionButton(
                        service.hasAvailableUpdate ? "View Update" : "Check for Updates",
                        systemImage: service.hasAvailableUpdate
                            ? "arrow.down.circle.fill"
                            : "arrow.clockwise"
                    ) {
                        service.checkForUpdates()
                    }
                    .disabled(!service.canCheckForUpdates)

                    if let releaseNotesURL = service.snapshot.releaseNotesURL {
                        SettingsActionLink(
                            title: "Release Notes", systemImage: "doc.text",
                            destination: releaseNotesURL)
                    }
                }

                if let error = service.snapshot.errorMessage, !error.isEmpty {
                    settingsFootnote(error)
                }
            }
        }
    }

    private var statusValue: String {
        if service.snapshot.isChecking { return "Checking…" }
        if service.hasAvailableUpdate {
            return "\(service.snapshot.latestVersion ?? "Update") available"
        }
        return service.canCheckForUpdates ? "Up to date" : "Updater unavailable"
    }

    private var statusSubtitle: String {
        service.hasAvailableUpdate
            ? "A signed update is ready to review."
            : "Crona will let you know when a newer build is available."
    }
}

struct AboutSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            HStack(spacing: 16) {
                Image(nsImage: CronaAppIcon.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Crona")
                        .font(.title2.weight(.semibold))
                    Text("Focus, naturally integrated with macOS.")
                        .font(.subheadline)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                }
            }
            .padding(.vertical, 6)

            SettingsCard("Build") {
                SettingsValueRow(
                    title: "Version",
                    subtitle: "Installed on this Mac.",
                    value: appState.appUpdateService.snapshot.currentVersion
                )
                SettingsValueRow(
                    title: "Protocol",
                    subtitle: "Expected engine protocol.",
                    value: CronaProtocolVersion.current.rawValue
                )
                SettingsValueRow(
                    title: "App Channel",
                    subtitle: "Release track for this app.",
                    value: appState.appUpdateService.selectedChannel.title
                )
                SettingsValueRow(
                    title: "Engine Channel",
                    subtitle: "Release track reported by the engine.",
                    value: appState.daemonConnection.kernelInfo?.runningChannel ?? "Unknown"
                )
            }

            SettingsCard("Feedback & Roadmap") {
                SettingsActionGroup {
                    SettingsActionButton("Share Feedback", systemImage: "bubble.left.and.bubble.right") {
                        appState.openFeedbackAndRoadmap()
                    }
                }
            }

        }
    }
}
