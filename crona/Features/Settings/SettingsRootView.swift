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
                        items: [.smartPause, .breakScreen, .notifications],
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
                        items: [.updates, .about],
                        selected: appState.selectedSettingsDestination,
                        onSelect: appState.setSelectedSettingsDestination
                    )

#if DEBUG
                    SettingsSidebarSection(
                        title: "Developer",
                        items: [.developer],
                        selected: appState.selectedSettingsDestination,
                        onSelect: appState.setSelectedSettingsDestination
                    )
#endif
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
                    case .smartPause:
                        SettingsPane(subtitle: "Keep stopwatch time aligned with the time you are actually at your Mac.") {
                            SmartPauseSettingsView(appState: appState)
                        }
                    case .breakScreen:
                        SettingsPane(subtitle: "Step away when a pomodoro break begins.") {
                            BreakScreenSettingsView(appState: appState)
                        }
                    case .notifications:
                        SettingsPane(subtitle: "Decide when Crona should get your attention.") {
                            NotificationSettingsView(appState: appState)
                        }
                    case .runtime:
                        SettingsPane(subtitle: "See where Crona is running and reconnect when needed.") {
                            RuntimeSettingsView(appState: appState)
                        }
                    case .diagnostics:
                        SettingsPane(subtitle: "Everything you need when something feels off.") {
                            DiagnosticsSettingsView(appState: appState)
                        }
                    case .updates:
                        SettingsPane(subtitle: "Keep Crona current without interrupting your focus.") {
                            UpdatesSettingsView(appState: appState)
                        }
                    case .about:
                        SettingsPane(subtitle: "Crona for macOS, at a glance.") {
                            AboutSettingsView(appState: appState)
                        }
#if DEBUG
                    case .developer:
                        SettingsPane(subtitle: "Preview companion presenters without changing the daemon or starting a session.") {
                            DeveloperSettingsView(appState: appState)
                        }
#endif
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

                SettingsToggleRow(
                    title: "Hide Dock Icon When Closed",
                    subtitle: "Keep Crona in the menu bar only unless a full app window is open.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.hideDockIconWhenNoWindowsOpen },
                        set: { appState.preferences.preferences.hideDockIconWhenNoWindowsOpen = $0 }
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

    private var previewIconState: MenuBarIconState {
        MenuBarIconState.resolve(
            connectionState: appState.popoverModel.connectionState,
            timerSnapshot: appState.popoverModel.timerSnapshot
        )
    }

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
                            if let image = MenuBarIconProvider.image(for: previewIconState) {
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 18, height: 18)
                            }
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

                    TimerDisplayStyleRow(
                        selection: Binding(
                            get: { appState.preferences.preferences.menuBarTimeFormat },
                            set: { appState.preferences.preferences.menuBarTimeFormat = $0 }
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

private struct SmartPauseSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    private var preferences: CompanionPreferences {
        appState.preferences.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Smart Pause") {
                SettingsToggleRow(
                    title: "Pause Automatically",
                    subtitle: "Pause a running stopwatch when you step away from your Mac.",
                    isOn: binding(\.smartPauseEnabled)
                )
            }

            SettingsCard("When You Step Away") {
                Group {
                    SettingsToggleRow(
                        title: "Mac Is Locked",
                        subtitle: "Pause immediately when your user session moves to the Lock Screen.",
                        isOn: binding(\.smartPauseOnLock)
                    )

                    SettingsToggleRow(
                        title: "Display Goes to Sleep",
                        subtitle: "Pause immediately when your Mac turns its displays off.",
                        isOn: binding(\.smartPauseOnDisplaySleep)
                    )

                    SettingsToggleRow(
                        title: "No Keyboard or Mouse Input",
                        subtitle: "Pause only after there has been no input for the selected time.",
                        isOn: binding(\.smartPauseOnInactivity)
                    )

                    if preferences.smartPauseOnInactivity {
                        SettingsPickerRow(
                            title: "No-Input Delay",
                            subtitle: "This delay applies only to keyboard and mouse inactivity.",
                            selection: binding(\.smartPauseIdleSeconds)
                        ) {
                            ForEach(CompanionPreferences.smartPauseIdleOptions, id: \.self) { seconds in
                                Text(Self.durationTitle(seconds)).tag(seconds)
                            }
                        }
                    }
                }
                .disabled(!preferences.smartPauseEnabled)
                .opacity(preferences.smartPauseEnabled ? 1 : 0.55)
            }

            SettingsCard("When You Return") {
                SettingsValueRow(
                    title: "Resume Automatically",
                    subtitle: "Crona resumes only when it initiated the pause and every pause condition has cleared.",
                    value: "On"
                )
            }

            settingsFootnote(
                "Smart Pause applies only to Stopwatch sessions. Pomodoro and countdown timers keep their existing behavior."
            )
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CompanionPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { appState.preferences.preferences[keyPath: keyPath] },
            set: { appState.preferences.preferences[keyPath: keyPath] = $0 }
        )
    }

    private static func durationTitle(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) seconds"
        }
        let minutes = seconds / 60
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
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
                SettingsActionGroup {
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

                SettingsActionGroup {
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

                SettingsToggleRow(
                    title: "Show Action Popup",
                    subtitle: "Open a small desktop prompt when that reminder fires.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showInactivityActionPopups },
                        set: {
                            appState.preferences.preferences.showInactivityActionPopups = $0
                        }
                    )
                )
                .disabled(settings == nil || settings?.inactivityAlertsEnabled == false)

                InactivityPopupPositionRow(
                    selection: Binding(
                        get: { appState.preferences.preferences.inactivityPopupPosition },
                        set: { appState.preferences.preferences.inactivityPopupPosition = $0 }
                    )
                )
                .disabled(
                    settings == nil
                        || settings?.inactivityAlertsEnabled == false
                        || !appState.preferences.preferences.showInactivityActionPopups
                )
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

#if DEBUG
private struct DeveloperSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Presentation Lab") {
                Text("These previews use local fixtures only. They never start, pause, extend, or end a daemon session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)

                SettingsActionGroup {
                    SettingsActionButton("Hard Limit Flow", systemImage: "hourglass.circle") {
                        appState.showDeveloperHardLimitPreview()
                    }
                    SettingsActionButton("Inactivity Prompt", systemImage: "timer.circle", prominent: false) {
                        appState.showDeveloperInactivityPreview()
                    }
                }

                SettingsActionGroup {
                    SettingsActionButton("Warning Indicator", systemImage: "exclamationmark.circle", prominent: false) {
                        appState.showDeveloperWarningPreview()
                    }
                    SettingsActionButton("Focus Resumed", systemImage: "play.circle", prominent: false) {
                        appState.showDeveloperSmartPauseResumePreview()
                    }
                    SettingsActionButton("Break Screen", systemImage: "moon.stars", prominent: false) {
                        appState.showDeveloperBreakScreenPreview()
                    }
                }
            }

            SettingsCard("Cleanup") {
                SettingsActionGroup {
                    SettingsActionButton("Dismiss All Previews", systemImage: "xmark.circle", prominent: false) {
                        appState.dismissDeveloperPreviews()
                    }
                }
            }
        }
    }
}
#endif

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

            SettingsActionGroup {
                SettingsActionButton("Reconnect", systemImage: "arrow.clockwise") {
                    appState.manualReconnect()
                }
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
                SettingsActionGroup {
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

private struct UpdatesSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    private var service: AppUpdateService { appState.appUpdateService }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Installed") {
                SettingsValueRow(
                    title: "Crona",
                    subtitle: "The version currently installed on this Mac.",
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
                        subtitle: "The most recent completed update check.",
                        value: lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            SettingsCard("Release Channel") {
                SettingsPickerRow(
                    title: "Channel",
                    subtitle: "Stable is dependable. Beta includes early releases and every stable update.",
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
                    subtitle: "Look for new releases quietly in the background.",
                    isOn: Binding(
                        get: { service.automaticallyChecksForUpdates },
                        set: { service.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                SettingsToggleRow(
                    title: "Download Automatically",
                    subtitle: "Prepare verified updates so they are ready when Crona next quits.",
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
                        SettingsActionLink(title: "Release Notes", systemImage: "doc.text", destination: releaseNotesURL)
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
                    value: appState.appUpdateService.snapshot.currentVersion
                )
                SettingsValueRow(
                    title: "Protocol",
                    subtitle: "The protocol this build expects from the kernel.",
                    value: CronaProtocolVersion.current.rawValue
                )
                SettingsValueRow(
                    title: "App Channel",
                    subtitle: "The release track used by this macOS app.",
                    value: appState.appUpdateService.selectedChannel.title
                )
                SettingsValueRow(
                    title: "Engine Channel",
                    subtitle: "The channel reported by the running Crona engine.",
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

private struct TimerDisplayStyleRow: View {
    let selection: Binding<MenuBarTimeFormat>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timer Display")
                    .font(.subheadline.weight(.medium))
                Text("Choose how an active timer fits into the menu bar.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            HStack(spacing: 10) {
                styleButton(
                    .clock,
                    detail: "A precise digital clock.",
                    preview: "04:07  ·  1:04:07"
                )
                styleButton(
                    .adaptive,
                    detail: "Compact until the final minute.",
                    preview: "1h4m  ·  4m  ·  42s"
                )
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    private func styleButton(
        _ style: MenuBarTimeFormat,
        detail: String,
        preview: String
    ) -> some View {
        Button {
            selection.wrappedValue = style
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(style.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: selection.wrappedValue == style
                        ? "checkmark.circle.fill"
                        : "circle")
                        .foregroundStyle(selection.wrappedValue == style ? Color.accentColor : .secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selection.wrappedValue == style
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                selection.wrappedValue == style
                                    ? Color.accentColor.opacity(0.55)
                                    : Color.primary.opacity(0.07),
                                lineWidth: 0.8
                            )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title) timer display")
        .accessibilityAddTraits(selection.wrappedValue == style ? .isSelected : [])
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

private struct InactivityPopupPositionRow: View {
    let selection: Binding<CompanionPopupPosition>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Popup Position")
                    .font(.subheadline.weight(.medium))
                Text("Choose where the reminder appears on screen.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            placementGrid
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    private var placementGrid: some View {
        VStack(spacing: 26) {
            positionRow([.topLeft, .topCenter, .topRight])
            positionRow([.bottomLeft, .bottomCenter, .bottomRight])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 156, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inactivity popup position")
    }

    private func positionRow(_ positions: [CompanionPopupPosition]) -> some View {
        HStack(spacing: 20) {
            ForEach(positions) { position in
                Button {
                    selection.wrappedValue = position
                } label: {
                    Circle()
                        .fill(selection.wrappedValue == position ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: 9, height: 9)
                        .overlay {
                            if selection.wrappedValue == position {
                                Circle()
                                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 4)
                                    .scaleEffect(1.7)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(position.title)
                .accessibilityAddTraits(selection.wrappedValue == position ? .isSelected : [])
            }
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(prominent ? Color.primary.opacity(0.16) : Color.primary.opacity(0.075))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    prominent ? Color.primary.opacity(0.2) : Color.primary.opacity(0.11),
                                    lineWidth: 0.75
                                )
                        )
                )
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(SettingsPressButtonStyle())
    }
}

private struct SettingsActionGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsActionLink: View {
    let title: String
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.075))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
                        )
                )
        }
        .foregroundStyle(Color.primary)
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
        case .smartPause: return "Smart Pause"
        case .breakScreen: return "Break Screen"
        case .notifications: return "Notifications"
        case .runtime: return "Runtime"
        case .diagnostics: return "Diagnostics"
        case .updates: return "Updates"
        case .about: return "About"
#if DEBUG
        case .developer: return "Dev"
#endif
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .menuBar: return "menubar.rectangle"
        case .smartPause: return "pause.circle.fill"
        case .breakScreen: return "moon.stars.fill"
        case .notifications: return "bell.fill"
        case .runtime: return "bolt.horizontal.circle.fill"
        case .diagnostics: return "stethoscope"
        case .updates: return "arrow.triangle.2.circlepath.circle.fill"
        case .about: return "info.circle.fill"
#if DEBUG
        case .developer: return "hammer.fill"
#endif
        }
    }
}
