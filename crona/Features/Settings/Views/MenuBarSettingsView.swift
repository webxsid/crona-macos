import AppKit
import SwiftUI
import UserNotifications

struct MenuBarSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Status Item") {
                SettingsToggleRow(
                    title: "Show Menu Bar Item",
                    subtitle: "Keep Crona available from the menu bar.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showMenuBarItem },
                        set: { appState.preferences.preferences.showMenuBarItem = $0 }
                    )
                )
            }

            SettingsCard("Preview") {
                VStack(alignment: .leading, spacing: 12) {

                    MenuBarSettingsPreview(
                        displayMode: appState.preferences.preferences.menuBarDisplayMode,
                        idleTextMode: appState.preferences.preferences.menuBarIdleTextMode,
                        timeFormat: appState.preferences.preferences.menuBarTimeFormat
                    )
                }
            }

            SettingsCard("Display") {
                SettingsPickerRow(
                    title: "Menu Bar Content",
                    subtitle: "Show an icon, text, or both in the menu bar.",
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
                        title: "When No Timer Is Running",
                        subtitle: "Choose what appears when no timer is active.",
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

            SettingsCard("Floating Timer") {
                SettingsToggleRow(
                    title: "Show Floating Timer",
                    subtitle: "Show a movable timer while a session is active.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showTimerHUD },
                        set: { appState.preferences.preferences.showTimerHUD = $0 }
                    )
                )

                TimerHUDPositionRow(
                    selection: Binding(
                        get: { appState.preferences.preferences.timerHUDPosition },
                        set: { appState.preferences.preferences.timerHUDPosition = $0 }
                    )
                )

                SettingsPickerRow(
                    title: "Floating Timer Size",
                    subtitle: "Choose the size of the floating timer surface.",
                    selection: Binding(
                        get: { appState.preferences.preferences.timerHUDSize },
                        set: { appState.preferences.preferences.timerHUDSize = $0 }
                    )
                ) {
                    ForEach(TimerHUDSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Example")
                        .font(.subheadline.weight(.medium))
                    FloatingTimerSettingsPreview(
                        size: appState.preferences.preferences.timerHUDSize)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct SmartPauseSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    private var preferences: CompanionPreferences {
        appState.preferences.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Smart Pause") {
                SettingsToggleRow(
                    title: "Pause Automatically",
                    subtitle: "Pause a running Stopwatch when you step away.",
                    isOn: binding(\.smartPauseEnabled)
                )
            }

            SettingsCard("When You Step Away") {
                Group {
                    SettingsToggleRow(
                        title: "Mac Is Locked",
                        subtitle: "Pause when your Mac reaches the Lock Screen.",
                        isOn: binding(\.smartPauseOnLock)
                    )

                    SettingsToggleRow(
                        title: "Display Goes to Sleep",
                        subtitle: "Pause when your displays turn off.",
                        isOn: binding(\.smartPauseOnDisplaySleep)
                    )

                    SettingsToggleRow(
                        title: "No Keyboard or Mouse Input",
                        subtitle: "Pause after a period without input.",
                        isOn: binding(\.smartPauseOnInactivity)
                    )

                    if preferences.smartPauseOnInactivity {
                        SettingsPickerRow(
                            title: "No-Input Delay",
                            subtitle: "How long to wait before pausing.",
                            selection: binding(\.smartPauseIdleSeconds)
                        ) {
                            ForEach(CompanionPreferences.smartPauseIdleOptions, id: \.self) {
                                seconds in
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
                    subtitle: "Resume when you return and every pause condition has cleared.",
                    value: "On"
                )

                FocusResumeSettingsPreview()
            }

            settingsFootnote(
                "Smart Pause applies only to Stopwatch sessions. Pomodoro and countdown timers keep their existing behavior."
            )
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CompanionPreferences, Value>) -> Binding<
        Value
    > {
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

struct SettingsPreviewFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack { content }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PopupVisualTheme.primaryText.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                    }
            )
            .accessibilityElement(children: .contain)
            .allowsHitTesting(false)
    }
}

struct SettingsPopupPreviewStage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack { content }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PopupVisualTheme.primaryText.opacity(0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                    }
            )
            .accessibilityElement(children: .contain)
            .allowsHitTesting(false)
    }
}

struct SettingsPopupPreviewChrome<Content: View>: View {
    let width: CGFloat
    let cornerRadius: CGFloat
    var height: CGFloat? = nil
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            PopoverGlassBackground(cornerRadius: cornerRadius)
            content
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}

struct SettingsInactivityPreviewButtonStyle: ButtonStyle {
    var progress: Double? = nil

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        configuration.label
            .foregroundStyle(
                PopupVisualTheme.primaryText.opacity(configuration.isPressed ? 0.82 : 0.92)
            )
            .frame(maxWidth: .infinity, minHeight: 32)
            .background {
                ZStack(alignment: .leading) {
                    if let progress {
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PopupVisualTheme.primaryText.opacity(0.08))
                                .frame(width: geometry.size.width * min(1, max(0, progress)))
                        }
                        .allowsHitTesting(false)
                    }

                    shape
                        .fill(
                            PopupVisualTheme.controlBackground.opacity(
                                configuration.isPressed ? 0.92 : 0.82))
                }
            }
            .overlay(shape.strokeBorder(PopupVisualTheme.highlightedBorder, lineWidth: 0.8))
            .clipShape(shape)
            .contentShape(shape)
    }
}

struct SettingsMenuBarStrip: View {
    let content: AnyView

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                Text("File")
                Text("Edit")
                Text("View")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))

            Spacer(minLength: 12)
            content
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.7)
        }
    }
}

struct MenuBarSettingsPreview: View {
    let displayMode: MenuBarDisplayMode
    let idleTextMode: MenuBarIdleTextMode
    let timeFormat: MenuBarTimeFormat

    var body: some View {
        SettingsPreviewFrame {
            SettingsMenuBarStrip(content: AnyView(statusItem))
        }
        .accessibilityLabel("Menu bar preview showing the selected icon and text settings")
    }

    private var statusItem: some View {
        HStack(spacing: 6) {
            if displayMode.showsIcon {
                Image(nsImage: MenuBarIconProvider.image(for: .idle))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 15, height: 15)
            }
            if displayMode.showsText {
                Text(idleText).monospacedDigit()
            }
        }
    }

    private var idleText: String {
        switch idleTextMode {
        case .idle: "Idle"
        case .focusToday: "42m"
        case .issueBreakdown: "3/8"
        case .totalTime: "1h12m"
        case .focusScore: "86"
        }
    }
}

struct FloatingTimerSettingsPreview: View {
    let size: TimerHUDSize

    var body: some View {
        SettingsPreviewFrame {
            HStack(spacing: size == .compact ? 8 : 12) {
                Image(systemName: "timer")
                    .font(.system(size: size == .compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.pink)

                VStack(alignment: .leading, spacing: 2) {
                    Text("24:37")
                        .font(.system(size: size.clockFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if size != .compact {
                        Text("Deep work")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
                HStack(spacing: size == .compact ? 2 : 5) {
                    settingsPreviewButton("pause.fill", label: "Pause")
                    settingsPreviewButton("stop.fill", label: "End")
                }
            }
            .padding(.horizontal, size.horizontalPadding)
            .frame(width: size.contentSize.width, height: size.contentSize.height)
            .background(
                .regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                    PopupVisualTheme.border, lineWidth: 0.75)
            )
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Static floating timer preview")
    }

    private func settingsPreviewButton(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size == .compact ? 9 : 11, weight: .bold))
            .frame(width: size == .compact ? 22 : 27, height: size == .compact ? 22 : 27)
            .background(Circle().fill(.primary.opacity(0.1)))
            .accessibilityLabel(label)
    }
}

struct FocusResumeSettingsPreview: View {
    var body: some View {
        SettingsPopupPreviewStage {
            SettingsPopupPreviewChrome(width: 272, cornerRadius: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Focus resumed")
                            .font(.subheadline.weight(.semibold))
                        Text("Crona resumed your Stopwatch when you returned.")
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
        .accessibilityLabel("Static focus resumed notification preview")
    }
}

struct InactivityReminderSettingsPreview: View {
    var body: some View {
        SettingsPopupPreviewStage {
            SettingsPopupPreviewChrome(width: 372, cornerRadius: 24) {
                VStack(spacing: 6) {
                    HStack(spacing: 9) {
                        Image(systemName: "timer.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.64))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Still focusing?")
                                .font(.subheadline.weight(.semibold))
                            HStack(spacing: 10) {
                                Label("1:02:00", systemImage: "timer")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)

                    HStack(spacing: 8) {
                        Button {
                        } label: {
                            inactivityPreviewButtonLabel(title: "End Session", shortcut: "E")
                        }
                        .buttonStyle(SettingsInactivityPreviewButtonStyle())
                        .disabled(true)

                        Button {
                        } label: {
                            inactivityPreviewButtonLabel(
                                title: "Keep Running", detail: "30s", shortcut: "esc")
                        }
                        .buttonStyle(SettingsInactivityPreviewButtonStyle(progress: 0.5))
                        .disabled(true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .accessibilityLabel("Static inactivity reminder preview")
    }

    private func inactivityPreviewButtonLabel(
        title: String, detail: String? = nil, shortcut: String
    ) -> some View {
        ZStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.48))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                Text(shortcut)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.38))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32)
    }
}

struct WarningIndicatorSettingsPreview: View {
    let leadSeconds: Int

    var body: some View {
        SettingsPopupPreviewStage {
            SettingsPopupPreviewChrome(width: 184, cornerRadius: 20) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(nsColor: HardLimitWarningKind.expiry.tint))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: HardLimitWarningKind.expiry.symbolName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                    Text("Session ending soon")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 4)
                    Text("\(leadSeconds)s")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
            }
        }
        .accessibilityLabel("Static session ending warning preview")
    }
}
