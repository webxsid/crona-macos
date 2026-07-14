import SwiftUI
import UserNotifications

struct SettingsRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            settingsDetail
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Crona Settings")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Desktop preferences and diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsSidebarSection(
                        title: "Settings",
                        items: [.general, .menuBar, .notifications, .stats],
                        selected: appState.selectedSettingsDestination,
                        onSelect: appState.setSelectedSettingsDestination
                    )

                    SettingsSidebarSection(
                        title: "System",
                        items: [.runtime, .diagnostics],
                        selected: appState.selectedSettingsDestination,
                        onSelect: appState.setSelectedSettingsDestination
                    )

                    SettingsSidebarSection(
                        title: "Crona",
                        items: [.about],
                        selected: appState.selectedSettingsDestination,
                        onSelect: appState.setSelectedSettingsDestination
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 230, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor(calibratedWhite: 0.17, alpha: 1)),
                    Color(nsColor: NSColor(calibratedWhite: 0.15, alpha: 1))
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch appState.selectedSettingsDestination {
                case .general:
                    SettingsPane(
                        title: "General",
                        subtitle: "Core desktop behavior and launch preferences."
                    ) {
                        GeneralSettingsView(appState: appState)
                    }
                case .menuBar:
                    SettingsPane(
                        title: "Menu Bar",
                        subtitle: "Control how Crona appears in the menu bar and popover."
                    ) {
                        MenuBarSettingsView(appState: appState)
                    }
                case .notifications:
                    SettingsPane(
                        title: "Notifications",
                        subtitle: "Desktop notification access and test delivery."
                    ) {
                        NotificationSettingsView(appState: appState)
                    }
                case .stats:
                    SettingsPane(
                        title: "Stats",
                        subtitle: "Read-only focus score and session summary from the daemon."
                    ) {
                        StatsSettingsView(appState: appState)
                    }
                case .runtime:
                    SettingsPane(
                        title: "Runtime",
                        subtitle: "Daemon runtime discovery and connection controls."
                    ) {
                        RuntimeSettingsView(appState: appState)
                    }
                case .diagnostics:
                    SettingsPane(
                        title: "Diagnostics",
                        subtitle: "Connection health, protocol details, and troubleshooting."
                    ) {
                        DiagnosticsSettingsView(appState: appState)
                    }
                case .about:
                    SettingsPane(
                        title: "About",
                        subtitle: "Version and protocol details for this macOS companion."
                    ) {
                        AboutSettingsView(appState: appState)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .background(Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1)))
    }
}

private struct SettingsSidebarSection: View {
    let title: String
    let items: [SettingsDestination]
    let selected: SettingsDestination
    let onSelect: (SettingsDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            VStack(spacing: 4) {
                ForEach(items) { item in
                    SettingsSidebarRow(
                        item: item,
                        isSelected: selected == item,
                        action: { onSelect(item) }
                    )
                }
            }
        }
    }
}

private struct SettingsSidebarRow: View {
    let item: SettingsDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
            }

            content
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Startup") {
                SettingsToggleRow(
                    title: "Launch at Login",
                    subtitle: "Open Crona automatically when you sign in.",
                    isOn: Binding(
                        get: { appState.launchAtLoginService.isEnabled },
                        set: { appState.launchAtLoginService.setEnabled($0) }
                    )
                )

                if let error = appState.launchAtLoginService.lastError, !error.isEmpty {
                    settingsFootnote(error)
                }
            }

            SettingsCard("Popover") {
                SettingsToggleRow(
                    title: "Pin Popover",
                    subtitle: "Keep the Crona popover open until you dismiss it manually.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.pinPopover },
                        set: { appState.preferences.preferences.pinPopover = $0 }
                    )
                )
            }
        }
    }
}

private struct MenuBarSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Preview") {
                HStack(alignment: .center) {
                    Label("Crona", systemImage: "menubar.rectangle")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(previewStatus.isEmpty ? "Icon Only" : previewStatus)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.vertical, 2)
            }

            SettingsCard("Display") {
                SettingsPickerRow(
                    title: "Menu Bar",
                    subtitle: "Choose whether the menu bar shows only the icon or the icon with text.",
                    selection: Binding(
                        get: { appState.preferences.preferences.menuBarDisplayMode },
                        set: { appState.preferences.preferences.menuBarDisplayMode = $0 }
                    )
                ) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                SettingsPickerRow(
                    title: "Time Format",
                    subtitle: "Pick the timer style shown in the menu bar and popover.",
                    selection: Binding(
                        get: { appState.preferences.preferences.menuBarTimeFormat },
                        set: { appState.preferences.preferences.menuBarTimeFormat = $0 }
                    )
                ) {
                    ForEach(MenuBarTimeFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }

                SettingsToggleRow(
                    title: "Show Seconds",
                    subtitle: "Include seconds in timer displays when supported by the selected format.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.menuBarShowsSeconds },
                        set: { appState.preferences.preferences.menuBarShowsSeconds = $0 }
                    )
                )
            }
        }
    }

    private var previewStatus: String {
        MenuBarTextFormatter.statusItemTitle(
            preferences: appState.preferences.preferences,
            connectionState: appState.daemonConnection.connectionState,
            timerSnapshot: appState.timerService.snapshot
        )
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        SettingsCard("Permissions") {
            SettingsValueRow(
                title: "Authorization",
                subtitle: "Current macOS notification permission status for Crona.",
                value: notificationStatusText(appState.notificationService.authorizationStatus)
            )

            HStack(spacing: 12) {
                Button("Request Permission") {
                    appState.requestNotificationAuthorization()
                }
                .buttonStyle(.borderedProminent)

                Button("Test Notification") {
                    appState.sendTestNotification()
                }
                .buttonStyle(.bordered)
                .disabled(appState.daemonConnection.connectionState != .connected)
            }
        }
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .ephemeral: return "Ephemeral"
        case .notDetermined: return "Not Determined"
        case .provisional: return "Provisional"
        @unknown default: return "Unknown"
        }
    }
}

private struct StatsSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        let snapshot = appState.popoverStatsService.snapshot

        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Focus Score") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.date.isEmpty ? "Unavailable" : snapshot.date)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                        Text(snapshot.focusScore.map { "\($0.score)" } ?? "—")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(snapshot.focusScore?.level.capitalized ?? "Unavailable")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                }

                Text(snapshot.scoreMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
            }

            if let metrics = snapshot.todayMetrics, let score = snapshot.focusScore {
                SettingsCard("Session Summary") {
                    SettingsValueRow(
                        title: "Focus Time",
                        subtitle: "Total focused time captured for this day.",
                        value: MenuBarTextFormatter.formatElapsed(seconds: metrics.workedSeconds, format: .expanded, showsSeconds: false)
                    )
                    SettingsValueRow(
                        title: "Break Time",
                        subtitle: "Total break time recorded by the daemon.",
                        value: MenuBarTextFormatter.formatElapsed(seconds: metrics.restSeconds, format: .expanded, showsSeconds: false)
                    )
                    SettingsValueRow(
                        title: "Sessions",
                        subtitle: "Number of sessions recorded for the selected day.",
                        value: "\(metrics.sessionCount)"
                    )
                    SettingsValueRow(
                        title: "Target",
                        subtitle: "Expected focused time used for the focus score.",
                        value: MenuBarTextFormatter.formatElapsed(seconds: score.targetWorkedSeconds, format: .expanded, showsSeconds: false)
                    )
                }
            }
        }
        .onAppear {
            Task { await appState.popoverStatsService.refresh() }
        }
    }
}

private struct RuntimeSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        SettingsCard("Discovery") {
            SettingsValueRow(
                title: "Runtime Directory",
                subtitle: "Base directory used for kernel discovery and runtime files.",
                value: appState.kernelDiscovery.loadedRuntime.config.runtimeDirectoryPath
            )
            SettingsValueRow(
                title: "Discovery File",
                subtitle: "Resolved `kernel.json` used for daemon discovery.",
                value: appState.kernelDiscovery.loadedRuntime.config.discoveryFilePath
            )
            SettingsValueRow(
                title: "Endpoint",
                subtitle: "Current daemon endpoint resolved from runtime discovery.",
                value: appState.daemonConnection.kernelInfo?.endpoint ?? appState.kernelDiscovery.loadedRuntime.resolvedDiscovery?.endpoint ?? "Unavailable"
            )

            Button("Manual Reconnect") {
                appState.manualReconnect()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct DiagnosticsSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Snapshot") {
                SettingsValueRow(
                    title: "Connection State",
                    subtitle: "Current daemon connection state for this companion.",
                    value: appState.diagnosticsService.snapshot.connectionState
                )
                SettingsValueRow(
                    title: "Protocol Version",
                    subtitle: "Protocol version negotiated with the daemon.",
                    value: appState.diagnosticsService.snapshot.protocolVersion
                )
                SettingsValueRow(
                    title: "Kernel Version",
                    subtitle: "Reported Crona daemon channel/version identifier.",
                    value: appState.diagnosticsService.snapshot.kernelVersion
                )
                SettingsValueRow(
                    title: "Runtime Directory",
                    subtitle: "Resolved runtime home directory.",
                    value: appState.diagnosticsService.snapshot.runtimeDirectory
                )
                SettingsValueRow(
                    title: "Health",
                    subtitle: "Current health summary returned by the daemon.",
                    value: appState.diagnosticsService.snapshot.healthSummary
                )
                SettingsValueRow(
                    title: "Last Reconnect",
                    subtitle: "Time of the last successful daemon reconnect.",
                    value: appState.diagnosticsService.snapshot.lastReconnect
                )
            }

            SettingsCard("Actions") {
                HStack(spacing: 12) {
                    Button("Copy Diagnostics") {
                        appState.diagnosticsService.copyToPasteboard()
                    }
                    .buttonStyle(.bordered)

                    Button("Manual Reconnect") {
                        appState.manualReconnect()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            Task { await appState.diagnosticsService.refresh() }
        }
    }
}

private struct AboutSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        SettingsCard("Versions") {
            SettingsValueRow(
                title: "App",
                subtitle: "Native macOS companion application name.",
                value: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Crona"
            )
            SettingsValueRow(
                title: "Protocol",
                subtitle: "Expected daemon protocol version supported by this build.",
                value: CronaProtocolVersion.current.rawValue
            )
            SettingsValueRow(
                title: "Daemon Channel",
                subtitle: "Reported running daemon channel.",
                value: appState.daemonConnection.kernelInfo?.runningChannel ?? "Unknown"
            )
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                SettingsValueRow(
                    title: "Version",
                    subtitle: "Application bundle short version string.",
                    value: version
                )
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.white)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.white.opacity(0.62))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let subtitle: String
    let selection: Binding<SelectionValue>
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.white)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.white.opacity(0.62))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Picker("", selection: selection) {
                content
            }
            .labelsHidden()
            .frame(width: 170)
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.white)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.white.opacity(0.62))
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.white.opacity(0.82))
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }
}

@ViewBuilder
private func settingsFootnote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.58))
        .padding(.top, 8)
}

private extension SettingsDestination {
    var title: String {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .notifications: return "Notifications"
        case .stats: return "Stats"
        case .runtime: return "Runtime"
        case .diagnostics: return "Diagnostics"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .menuBar: return "menubar.rectangle"
        case .notifications: return "bell.fill"
        case .stats: return "chart.line.uptrend.xyaxis"
        case .runtime: return "bolt.horizontal.circle.fill"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle.fill"
        }
    }
}
