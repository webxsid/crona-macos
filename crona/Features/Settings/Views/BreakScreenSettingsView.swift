import AppKit
import SwiftUI
import UserNotifications

struct BreakScreenSettingsView: View {
    @ObservedObject var appState: CompanionAppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var preferences: CompanionPreferences {
        appState.preferences.preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Break Screen") {
                SettingsToggleRow(
                    title: "Take Over the Screen",
                    subtitle: "Cover every display during Pomodoro breaks.",
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
                .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)

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

                SettingsPickerRow(
                    title: "Activity Guard",
                    subtitle: "Delay the break screen while you are typing or dragging.",
                    selection: Binding(
                        get: { preferences.breakScreenActivityDeferral },
                        set: { appState.preferences.preferences.breakScreenActivityDeferral = $0 }
                    )
                ) {
                    ForEach(BreakScreenActivityDeferral.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                if preferences.breakScreenActivityDeferral != .off {
                    SettingsPickerRow(
                        title: "Activity Extension",
                        subtitle:
                            "Extra work time granted when the boundary is reached during activity.",
                        selection: Binding(
                            get: { preferences.breakScreenActivityExtensionSeconds },
                            set: { value in
                                appState.preferences.preferences
                                    .breakScreenActivityExtensionSeconds =
                                    CompanionPreferences.breakScreenActivityExtensionOptions.min {
                                        abs($0 - value) < abs($1 - value)
                                    } ?? 60
                            }
                        )
                    ) {
                        ForEach(
                            CompanionPreferences.breakScreenActivityExtensionOptions, id: \.self
                        ) {
                            Text("\($0) seconds").tag($0)
                        }
                    }

                }
            }

            SettingsCard("Background") {
                SettingsPickerRow(
                    title: "Style",
                    subtitle: "What appears behind the break countdown.",
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
                    settingsFootnote(
                        "Uses each display’s current wallpaper with a quiet dimming layer.")
                case .solidColor:
                    BreakScreenSolidColorSwatchPicker(
                        selection: Binding(
                            get: { preferences.breakScreenSolidColor },
                            set: { appState.preferences.preferences.breakScreenSolidColor = $0 }
                        )
                    )
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
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.16), value: preferences.breakScreenMode
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.16),
            value: preferences.breakScreenBackgroundStyle)
    }
}

struct BreakScreenSolidColorSwatchPicker: View {
    @Binding var selection: CompanionRGBAColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Break Color")
                        .font(.subheadline.weight(.medium))
                    Text("Choose a calm swatch for the break screen.")
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                }

                Spacer(minLength: 0)

                Text(selectedTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PopupVisualTheme.secondaryText)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 42), spacing: 10), count: 6),
                spacing: 10
            ) {
                ForEach(Self.swatches) { swatch in
                    Button {
                        selection = swatch.color
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(rgba: swatch.color))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if isSelected(swatch.color) {
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if isSelected(swatch.color) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(Circle().fill(Color.accentColor))
                                            .offset(x: 3, y: -3)
                                    }
                                }

                            Text(swatch.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(PopupVisualTheme.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    isSelected(swatch.color)
                                        ? Color.accentColor.opacity(0.12)
                                        : PopupVisualTheme.primaryText.opacity(0.04)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(
                                            isSelected(swatch.color)
                                                ? Color.accentColor.opacity(0.45)
                                                : PopupVisualTheme.border, lineWidth: 0.75)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(
                cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous
            )
            .fill(PopupVisualTheme.primaryText.opacity(0.04))
            .overlay(
                RoundedRectangle(
                    cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous
                )
                .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
            )
        )
    }

    private var selectedTitle: String {
        Self.swatches.first(where: { $0.color == selection })?.name ?? "Custom"
    }

    private func isSelected(_ color: CompanionRGBAColor) -> Bool {
        selection == color
    }

    private static let swatches: [BreakScreenSolidColorSwatch] = [
        .init(name: "Slate", color: .init(red: 0.055, green: 0.075, blue: 0.11, alpha: 1)),
        .init(name: "Blue", color: .init(red: 0.04, green: 0.13, blue: 0.23, alpha: 1)),
        .init(name: "Teal", color: .init(red: 0.04, green: 0.14, blue: 0.11, alpha: 1)),
        .init(name: "Rose", color: .init(red: 0.2, green: 0.07, blue: 0.1, alpha: 1)),
        .init(name: "Violet", color: .init(red: 0.18, green: 0.11, blue: 0.24, alpha: 1)),
        .init(name: "Warm", color: .init(red: 0.52, green: 0.2, blue: 0.15, alpha: 1)),
    ]
}

struct BreakScreenSolidColorSwatch: Identifiable {
    let name: String
    let color: CompanionRGBAColor

    var id: String { name }
}

struct BreakScreenModeCard: View {
    let mode: BreakScreenMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        selected
                            ? Color.accentColor.opacity(0.16)
                            : PopupVisualTheme.primaryText.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : PopupVisualTheme.primaryText.opacity(0.07),
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

struct BreakScreenSettingsPreview: View {
    let preferences: CompanionPreferences

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ZStack {
                BreakScreenBackgroundView(
                    preferences: preferences,
                    screen: NSScreen.main,
                    date: timeline.date
                )
                VStack(spacing: 4) {
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
            .frame(height: 138)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(PopupVisualTheme.primaryText.opacity(0.12), lineWidth: 0.75)
            )
        }
    }
}
