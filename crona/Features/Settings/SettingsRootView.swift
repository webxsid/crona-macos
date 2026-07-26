import AppKit
import SwiftUI
import UserNotifications

struct SettingsRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider().opacity(0.5)
            settingsDetail
        }
        .frame(minWidth: 860, minHeight: 620)
        .ignoresSafeArea(.container, edges: .top)
        .background(
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .behindWindow,
                emphasized: true
            )
            .ignoresSafeArea()
        )
        .background(SettingsWindowReader(windowService: appState.windowService))
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsSidebarSection(
                        title: "Settings",
                        items: [.general, .menuBar],
                        selected: appState.selectedSettingsDestination,
                        onSelect: appState.setSelectedSettingsDestination
                    )

                    SettingsSidebarSection(
                        title: "Focus",
                        items: [.breakScreen, .notifications, .stats],
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
                .padding(.horizontal, 10)
                .padding(.top, SettingsChromeMetrics.sidebarTrafficLightClearance)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: SettingsChromeMetrics.sidebarWidth, alignment: .topLeading)
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow, emphasized: true)
        )
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            settingsToolbar
            Divider().opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch appState.selectedSettingsDestination {
                    case .general:
                        SettingsPane(subtitle: "Choose how Crona fits into your day.") {
                            GeneralSettingsView(appState: appState)
                        }
                    case .menuBar:
                        SettingsPane(subtitle: "Keep the right amount of focus in sight.") {
                            MenuBarSettingsView(appState: appState)
                        }
                    case .breakScreen:
                        SettingsPane(subtitle: "Step away when a pomodoro break begins.") {
                            BreakScreenSettingsView(appState: appState)
                        }
                    case .notifications:
                        SettingsPane(subtitle: "Decide when Crona should get your attention.") {
                            NotificationSettingsView(appState: appState)
                        }
                    case .stats:
                        SettingsPane(subtitle: "A clear view of the focus time Crona has recorded.") {
                            StatsSettingsView(appState: appState)
                        }
                    case .runtime:
                        SettingsPane(subtitle: "See where Crona is running and reconnect when needed.") {
                            RuntimeSettingsView(appState: appState)
                        }
                    case .diagnostics:
                        SettingsPane(subtitle: "Everything you need when something feels off.") {
                            DiagnosticsSettingsView(appState: appState)
                        }
                    case .about:
                        SettingsPane(subtitle: "Crona for macOS, at a glance.") {
                            AboutSettingsView(appState: appState)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 36)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.38))
    }

    private var settingsToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button(action: appState.goBackInSettings) {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 30)
                        .contentShape(Rectangle())
                }
                .disabled(!appState.settingsNavigation.canGoBack)

                Divider()
                    .frame(height: 16)

                Button(action: appState.goForwardInSettings) {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 30)
                        .contentShape(Rectangle())
                }
                .disabled(!appState.settingsNavigation.canGoForward)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.075))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    )
            )

            Text(appState.selectedSettingsDestination.title)
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: SettingsChromeMetrics.titlebarBandHeight)
    }
}

private enum SettingsChromeMetrics {
    static let titlebarBandHeight: CGFloat = 54
    static let sidebarTrafficLightClearance: CGFloat = 50
    static let sidebarWidth: CGFloat = 210
}

private struct SettingsSidebarSection: View {
    let title: String
    let items: [SettingsDestination]
    let selected: SettingsDestination
    let onSelect: (SettingsDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
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
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPane<Content: View>: View {
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
                    subtitle: "Have Crona ready in the menu bar when you sign in.",
                    isOn: Binding(
                        get: { appState.launchAtLoginService.isEnabled },
                        set: { appState.launchAtLoginService.setEnabled($0) }
                    )
                )

                if let error = appState.launchAtLoginService.lastError, !error.isEmpty {
                    settingsFootnote(error)
                }
            }

            SettingsCard("Menu Popover") {
                SettingsToggleRow(
                    title: "Pin Popover",
                    subtitle: "Keep the popover open while you work with it.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.pinPopover },
                        set: { appState.preferences.preferences.pinPopover = $0 }
                    )
                )
            }

            SettingsMediaPlaceholder(
                assetName: "SettingsGeneralDemo",
                title: "Crona in your workflow",
                subtitle: "Add a walkthrough image or GIF named SettingsGeneralDemo."
            )
        }
    }
}

private struct MenuBarSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your menu bar")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Spacer()
                        if appState.preferences.preferences.menuBarDisplayMode.showsIcon {
                            Image(nsImage: CronaAppIcon.image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 18, height: 18)
                        }
                        if appState.preferences.preferences.menuBarDisplayMode.showsText {
                            Text(previewStatus)
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    .frame(height: 34)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75))
                    )
                }
            }

            SettingsCard("Display") {
                SettingsPickerRow(
                    title: "Show",
                    subtitle: "Choose whether Crona appears as an icon, text, or both.",
                    selection: Binding(
                        get: { appState.preferences.preferences.menuBarDisplayMode },
                        set: { appState.preferences.preferences.menuBarDisplayMode = $0 }
                    )
                ) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if appState.preferences.preferences.menuBarDisplayMode.showsText {
                    SettingsPickerRow(
                        title: "When Idle",
                        subtitle: "Show a quiet Idle label or today’s focus time.",
                        selection: Binding(
                            get: { appState.preferences.preferences.menuBarIdleTextMode },
                            set: { appState.preferences.preferences.menuBarIdleTextMode = $0 }
                        )
                    ) {
                        ForEach(MenuBarIdleTextMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    SettingsPickerRow(
                        title: "Timer Style",
                        subtitle: "Choose how active session time is written.",
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
                        subtitle: "Keep the active timer precise down to the second.",
                        isOn: Binding(
                            get: { appState.preferences.preferences.menuBarShowsSeconds },
                            set: { appState.preferences.preferences.menuBarShowsSeconds = $0 }
                        )
                    )
                }
            }
        }
        .onAppear {
            Task {
                await appState.popoverStatsService.refresh()
                await appState.popoverStatsService.refreshTodayMetrics()
            }
        }
    }

    private var previewStatus: String {
        MenuBarTextFormatter.statusItemTitle(
            preferences: appState.preferences.preferences,
            connectionState: appState.daemonConnection.connectionState,
            timerSnapshot: appState.timerService.snapshot,
            todayWorkedSeconds: appState.popoverStatsService.todayWorkedSeconds
        )
    }
}

private struct BreakScreenSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    private var preferences: CompanionPreferences {
        appState.preferences.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Break Screen") {
                SettingsToggleRow(
                    title: "Take Over the Screen",
                    subtitle: "Cover every display when a pomodoro break begins.",
                    isOn: Binding(
                        get: { preferences.breakScreenEnabled },
                        set: { appState.preferences.preferences.breakScreenEnabled = $0 }
                    )
                )
            }

            SettingsCard("Enforcement") {
                HStack(spacing: 10) {
                    ForEach(BreakScreenMode.allCases) { mode in
                        BreakScreenModeCard(
                            mode: mode,
                            selected: preferences.breakScreenMode == mode
                        ) {
                            appState.preferences.preferences.breakScreenMode = mode
                        }
                    }
                }
                .padding(.vertical, 10)

                if preferences.breakScreenMode == .strict {
                    SettingsPickerRow(
                        title: "Skip Delay",
                        subtitle: "Keep Skip unavailable at the beginning of each break.",
                        selection: Binding(
                            get: { preferences.breakScreenStrictDelaySeconds },
                            set: {
                                appState.preferences.preferences.breakScreenStrictDelaySeconds =
                                    CompanionPreferences.normalizedBreakScreenStrictDelaySeconds($0)
                            }
                        )
                    ) {
                        ForEach(CompanionPreferences.breakScreenStrictDelayOptions, id: \.self) {
                            Text("\($0) seconds").tag($0)
                        }
                    }
                }
            }

            SettingsCard("Background") {
                SettingsPickerRow(
                    title: "Style",
                    subtitle: "Choose what appears behind the break countdown.",
                    selection: Binding(
                        get: { preferences.breakScreenBackgroundStyle },
                        set: { appState.preferences.preferences.breakScreenBackgroundStyle = $0 }
                    )
                ) {
                    ForEach(BreakScreenBackgroundStyle.allCases) {
                        Text($0.title).tag($0)
                    }
                }

                switch preferences.breakScreenBackgroundStyle {
                case .systemWallpaper:
                    settingsFootnote("Uses each display’s current wallpaper with a quiet dimming layer.")
                case .solidColor:
                    HStack {
                        Text("Break Color")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        ColorPicker("", selection: solidColorBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                    .padding(.vertical, 10)
                case .gradient:
                    SettingsPickerRow(
                        title: "Gradient",
                        subtitle: "Choose a calm background for your break.",
                        selection: Binding(
                            get: { preferences.breakScreenGradientPreset },
                            set: { appState.preferences.preferences.breakScreenGradientPreset = $0 }
                        )
                    ) {
                        ForEach(BreakScreenGradientPreset.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                }
            }

            BreakScreenSettingsPreview(preferences: preferences)
        }
        .animation(.easeInOut(duration: 0.16), value: preferences.breakScreenMode)
        .animation(.easeInOut(duration: 0.16), value: preferences.breakScreenBackgroundStyle)
    }

    private var solidColorBinding: Binding<Color> {
        Binding(
            get: { Color(rgba: preferences.breakScreenSolidColor) },
            set: {
                appState.preferences.preferences.breakScreenSolidColor =
                    CompanionRGBAColor(nsColor: NSColor($0))
            }
        )
    }
}

private struct BreakScreenModeCard: View {
    let mode: BreakScreenMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.07),
                        lineWidth: selected ? 2 : 0.75
                    )
            )
        }
        .buttonStyle(SettingsPressButtonStyle())
    }

    private var symbolName: String {
        switch mode {
        case .easy: return "forward.end"
        case .strict: return "timer"
        case .hard: return "lock.fill"
        }
    }

    private var subtitle: String {
        switch mode {
        case .easy: return "Skip anytime"
        case .strict: return "Skip after a pause"
        case .hard: return "No skipping"
        }
    }
}

private struct BreakScreenSettingsPreview: View {
    let preferences: CompanionPreferences

    var body: some View {
        ZStack {
            BreakScreenBackgroundView(preferences: preferences, screen: NSScreen.main)
            VStack(spacing: 5) {
                Text("Short Break")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text("04:32")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Ends at 4:45 PM")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        )
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var alertSettings: AlertSettingsService

    init(appState: CompanionAppState) {
        self.appState = appState
        _alertSettings = ObservedObject(wrappedValue: appState.alertSettingsService)
    }

    var body: some View {
        let settings = alertSettings.settings

        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Native Notifications") {
                SettingsValueRow(
                    title: "Permission",
                    subtitle: "Let Crona deliver alerts with native actions and sounds.",
                    value: notificationStatusText(
                        appState.notificationService.authorizationStatus
                    )
                )

                SettingsValueRow(
                    title: "Delivery",
                    subtitle: "The daemon falls back automatically whenever the app cannot deliver.",
                    value: deliveryStatusText
                )

                HStack(spacing: 10) {
                    SettingsActionButton("Allow Notifications", systemImage: "bell.badge.fill") {
                        appState.requestNotificationAuthorization()
                    }

                    SettingsActionButton("System Settings", systemImage: "gear", prominent: false) {
                        appState.notificationService.openSystemNotificationSettings()
                    }
                }
            }

            SettingsCard("Alerts") {
                SettingsToggleRow(
                    title: "Show Notifications",
                    subtitle: "Keep focus boundaries, reminders, and Crona updates in Notification Center.",
                    isOn: Binding(
                        get: { settings?.boundaryNotificationsEnabled ?? true },
                        set: {
                            appState.alertSettingsService.setBoolean(
                                "boundaryNotificationsEnabled",
                                value: $0
                            )
                        }
                    )
                )
                .disabled(settings == nil)

                SettingsToggleRow(
                    title: "Play Alert Sounds",
                    subtitle: "Use the selected Crona sound when an alert needs your attention.",
                    isOn: Binding(
                        get: { settings?.boundarySoundEnabled ?? true },
                        set: {
                            appState.alertSettingsService.setBoolean(
                                "boundarySoundEnabled",
                                value: $0
                            )
                        }
                    )
                )
                .disabled(settings == nil)

                SettingsPickerRow(
                    title: "Sound",
                    subtitle: "Choose the tone used for Crona alerts.",
                    selection: Binding(
                        get: {
                            alertSettings.settings?.alertSoundPreset ?? .chime
                        },
                        set: {
                            alertSettings.setSoundPreset($0)
                            appState.notificationService.playPresetPreview($0.rawValue)
                        }
                    )
                ) {
                    Text("Chime").tag(CronaAlertSoundPreset.chime)
                    Text("Soft Bell").tag(CronaAlertSoundPreset.softBell)
                    Text("Notification Ping").tag(CronaAlertSoundPreset.notificationPing)
                    Text("Focus Gong").tag(CronaAlertSoundPreset.focusGong)
                    Text("Minimal Click").tag(CronaAlertSoundPreset.minimalClick)
                }
                .disabled(settings == nil || settings?.boundarySoundEnabled == false)

                SettingsPickerRow(
                    title: "Prominence",
                    subtitle: "Choose how strongly Crona alerts should break through.",
                    selection: Binding(
                        get: {
                            alertSettings.settings?.alertUrgency ?? .standard
                        },
                        set: {
                            alertSettings.setProminence($0)
                        }
                    )
                ) {
                    Text("Quiet").tag(CronaAlertProminence.quiet)
                    Text("Standard").tag(CronaAlertProminence.standard)
                    Text("Time Sensitive").tag(CronaAlertProminence.timeSensitive)
                }
                .disabled(settings == nil)

                HStack(spacing: 10) {
                    SettingsActionButton("Send Test", systemImage: "paperplane.fill") {
                        appState.sendTestNotification()
                    }

                    SettingsActionButton("Play Sound", systemImage: "speaker.wave.2.fill", prominent: false) {
                        appState.sendTestSound()
                    }
                }
                .disabled(appState.daemonConnection.connectionState != .connected)
            }

            SettingsCard("Focus Reminders") {
                SettingsToggleRow(
                    title: "Inactivity Reminder",
                    subtitle: "Nudge me when a focus session may have been left running.",
                    isOn: Binding(
                        get: { settings?.inactivityAlertsEnabled ?? true },
                        set: {
                            appState.alertSettingsService.setBoolean(
                                "inactivityAlertsEnabled",
                                value: $0
                            )
                        }
                    )
                )
                .disabled(settings == nil)

                SettingsPickerRow(
                    title: "Remind After",
                    subtitle: "Wait this long without activity before the first reminder.",
                    selection: Binding(
                        get: { settings?.inactivityThresholdMinutes ?? 60 },
                        set: {
                            appState.alertSettingsService.setInteger(
                                "inactivityThresholdMinutes",
                                value: $0
                            )
                        }
                    )
                ) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) {
                        Text("\($0) minutes").tag($0)
                    }
                }
                .disabled(settings == nil || settings?.inactivityAlertsEnabled == false)

                SettingsPickerRow(
                    title: "Repeat",
                    subtitle: "Space out follow-up reminders while the session stays active.",
                    selection: Binding(
                        get: { settings?.inactivityRepeatMinutes ?? 60 },
                        set: {
                            appState.alertSettingsService.setInteger(
                                "inactivityRepeatMinutes",
                                value: $0
                            )
                        }
                    )
                ) {
                    ForEach([15, 30, 60, 90, 120], id: \.self) {
                        Text("\($0) minutes").tag($0)
                    }
                }
                .disabled(settings == nil || settings?.inactivityAlertsEnabled == false)
            }

            SettingsCard("Focus Boundaries") {
                SettingsToggleRow(
                    title: "Show Action Popup",
                    subtitle: "Bring up End and Extend when a hard-limit session reaches its boundary.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showHardLimitActionPopups },
                        set: { appState.preferences.preferences.showHardLimitActionPopups = $0 }
                    )
                )

                SettingsToggleRow(
                    title: "Show Early Warning",
                    subtitle: "Place a small warning beside the pointer before a session changes.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showHardLimitWarningIndicator },
                        set: { appState.preferences.preferences.showHardLimitWarningIndicator = $0 }
                    )
                )

                SettingsPickerRow(
                    title: "Warn Me",
                    subtitle: "Choose how soon the early warning appears.",
                    selection: Binding(
                        get: {
                            CompanionPreferences.normalizedHardLimitWarningLeadSeconds(
                                appState.preferences.preferences.hardLimitWarningLeadSeconds
                            )
                        },
                        set: {
                            appState.preferences.preferences.hardLimitWarningLeadSeconds = $0
                        }
                    )
                ) {
                    ForEach(CompanionPreferences.hardLimitWarningLeadTimeOptions, id: \.self) {
                        Text("\($0) seconds").tag($0)
                    }
                }
            }

            SettingsMediaPlaceholder(
                assetName: "SettingsNotificationDemo",
                title: "Notification preview",
                subtitle: "Add an image or GIF named SettingsNotificationDemo."
            )

            if let error = alertSettings.lastErrorDescription {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var deliveryStatusText: String {
        switch appState.notificationService.deliveryState {
        case .active: return "Crona for macOS"
        case .connecting: return "Connecting"
        case .failed: return "Daemon fallback"
        case .unavailable: return "Daemon fallback"
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
                            .foregroundStyle(.secondary)
                        Text(snapshot.focusScore.map { "\($0.score)" } ?? "—")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text(snapshot.focusScore?.level.capitalized ?? "Unavailable")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(snapshot.scoreMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let metrics = snapshot.todayMetrics, let score = snapshot.focusScore {
                SettingsCard("Session Summary") {
                    SettingsValueRow(
                        title: "Focus Time",
                        subtitle: "Time spent in focused sessions.",
                        value: MenuBarTextFormatter.formatElapsed(seconds: metrics.workedSeconds, format: .expanded, showsSeconds: false)
                    )
                    SettingsValueRow(
                        title: "Break Time",
                        subtitle: "Time Crona recorded between focus blocks.",
                        value: MenuBarTextFormatter.formatElapsed(seconds: metrics.restSeconds, format: .expanded, showsSeconds: false)
                    )
                    SettingsValueRow(
                        title: "Sessions",
                        subtitle: "Focus sessions completed on this day.",
                        value: "\(metrics.sessionCount)"
                    )
                    SettingsValueRow(
                        title: "Target",
                        subtitle: "The focus goal behind this score.",
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
                subtitle: "Where Crona looks for the running kernel.",
                value: appState.kernelDiscovery.loadedRuntime.config.runtimeDirectoryPath
            )
            SettingsValueRow(
                title: "Discovery File",
                subtitle: "The kernel.json currently used for discovery.",
                value: appState.kernelDiscovery.loadedRuntime.config.discoveryFilePath
            )
            SettingsValueRow(
                title: "Endpoint",
                subtitle: "The socket Crona is connected through.",
                value: appState.daemonConnection.kernelInfo?.endpoint ?? appState.kernelDiscovery.loadedRuntime.resolvedDiscovery?.endpoint ?? "Unavailable"
            )

            SettingsActionButton("Reconnect", systemImage: "arrow.clockwise") {
                appState.manualReconnect()
            }
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
                    subtitle: "Whether the macOS app can reach Crona.",
                    value: appState.diagnosticsService.snapshot.connectionState
                )
                SettingsValueRow(
                    title: "Protocol Version",
                    subtitle: "The language shared by the app and kernel.",
                    value: appState.diagnosticsService.snapshot.protocolVersion
                )
                SettingsValueRow(
                    title: "Kernel Version",
                    subtitle: "The kernel build currently running.",
                    value: appState.diagnosticsService.snapshot.kernelVersion
                )
                SettingsValueRow(
                    title: "Runtime Directory",
                    subtitle: "The active Crona runtime location.",
                    value: appState.diagnosticsService.snapshot.runtimeDirectory
                )
                SettingsValueRow(
                    title: "Health",
                    subtitle: "The kernel’s latest health report.",
                    value: appState.diagnosticsService.snapshot.healthSummary
                )
                SettingsValueRow(
                    title: "Last Reconnect",
                    subtitle: "When the app last found the kernel again.",
                    value: appState.diagnosticsService.snapshot.lastReconnect
                )
            }

            SettingsCard("Actions") {
                HStack(spacing: 12) {
                    SettingsActionButton("Copy Diagnostics", systemImage: "doc.on.doc", prominent: false) {
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

private struct AboutSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Crona for macOS") {
                HStack(spacing: 16) {
                    Image(nsImage: CronaAppIcon.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Crona")
                            .font(.title2.weight(.bold))
                        Text("Focus stays in the daemon. Crona brings it naturally into macOS.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsCard("Build") {
                SettingsValueRow(
                    title: "Version",
                    subtitle: "The version of Crona installed on this Mac.",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                )
                SettingsValueRow(
                    title: "Protocol",
                    subtitle: "The protocol this build expects from the kernel.",
                    value: CronaProtocolVersion.current.rawValue
                )
                SettingsValueRow(
                    title: "Channel",
                    subtitle: "The channel reported by the running kernel.",
                    value: appState.daemonConnection.kernelInfo?.runningChannel ?? "Unknown"
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.75)
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct SettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let subtitle: String
    let selection: Binding<SelectionValue>
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Picker("", selection: selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .frame(width: 170)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        prominent: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(prominent ? Color.accentColor : Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    prominent ? Color.white.opacity(0.16) : Color.primary.opacity(0.09),
                                    lineWidth: 0.75
                                )
                        )
                )
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(SettingsPressButtonStyle())
    }
}

private struct SettingsPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SettingsMediaPlaceholder: View {
    let assetName: String
    let title: String
    let subtitle: String

    var body: some View {
        Group {
            if let image = NSImage(named: NSImage.Name(assetName)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(
            ZStack {
                VisualEffectView(material: .contentBackground, blendingMode: .withinWindow, emphasized: false)
                LinearGradient(
                    colors: [Color.primary.opacity(0.055), Color.primary.opacity(0.018)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 0.8, dash: [5, 5]))
        )
    }
}

private struct SettingsWindowReader: NSViewRepresentable {
    let windowService: WindowService

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        registerWindow(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        registerWindow(from: nsView)
    }

    private func registerWindow(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            windowService.registerSettingsWindow(window)
        }
    }
}

@ViewBuilder
private func settingsFootnote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
}

private extension SettingsDestination {
    var title: String {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .breakScreen: return "Break Screen"
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
        case .breakScreen: return "moon.stars.fill"
        case .notifications: return "bell.fill"
        case .stats: return "chart.line.uptrend.xyaxis"
        case .runtime: return "bolt.horizontal.circle.fill"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle.fill"
        }
    }
}
