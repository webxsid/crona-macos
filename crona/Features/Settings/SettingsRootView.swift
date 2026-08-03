import AppKit
import SwiftUI
import UserNotifications

struct SettingsRootView: View {
    @ObservedObject var appState: CompanionAppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            settingsSidebar
                .toolbar(removing: .sidebarToggle)
        } detail: {
            settingsDetail
        }
        .frame(minWidth: 860, minHeight: 620)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            ZStack(alignment: .leading) {
                PopupVisualTheme.windowBackground
                SettingsSidebarBackground()
                    .frame(width: SettingsChromeMetrics.sidebarWidth)
                SettingsToolbarSurfaceBackground()
                    .frame(height: SettingsChromeMetrics.toolbarSurfaceHeight)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea()
        }
        .background(SettingsWindowReader(windowService: appState.windowService))
        .companionAppearance(appState)
        .modifier(SettingsWindowToolbarBackgroundModifier())
        .toolbar {
            if #available(macOS 27.0, *) {
                ToolbarItem(placement: .navigation) {
                    Button(action: appState.goBackInSettings) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!appState.settingsNavigation.canGoBack)
                    .help("Back")
                }
                ToolbarSpacer(.fixed)

                ToolbarItem(placement: .navigation) {
                    Button(action: appState.goForwardInSettings) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!appState.settingsNavigation.canGoForward)
                    .help("Forward")
                }
                ToolbarSpacer(.fixed)

                ToolbarItem(placement: .navigation) {
                    Text(appState.selectedSettingsDestination.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText)
                }
                .sharedBackgroundVisibility(.hidden)
            } else if #available(macOS 26.1, *) {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: appState.goBackInSettings) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!appState.settingsNavigation.canGoBack)
                    .help("Back")

                    Button(action: appState.goForwardInSettings) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!appState.settingsNavigation.canGoForward)
                    .help("Forward")
                }
                ToolbarItem(placement: .navigation) {
                    Text(appState.selectedSettingsDestination.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText)
                }
                .sharedBackgroundVisibility(.hidden)
            } else if #available(macOS 26.0, *) {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: appState.goBackInSettings) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!appState.settingsNavigation.canGoBack)
                    .help("Back")

                    Button(action: appState.goForwardInSettings) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!appState.settingsNavigation.canGoForward)
                    .help("Forward")
                }

                ToolbarItem(placement: .navigation) {
                    Text(appState.selectedSettingsDestination.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText)
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 12) {
                        SettingsNavigationCluster(
                            canGoBack: appState.settingsNavigation.canGoBack,
                            canGoForward: appState.settingsNavigation.canGoForward,
                            goBack: appState.goBackInSettings,
                            goForward: appState.goForwardInSettings
                        )

                        Text(appState.selectedSettingsDestination.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(PopupVisualTheme.primaryText)
                    }
                }
            }
        }
        .modifier(SettingsWindowToolbarChromeModifier())
        .onAppear {
            columnVisibility = .all
        }
        .onChange(of: columnVisibility) { _, visibility in
            if visibility != .all {
                columnVisibility = .all
            }
        }
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
                .padding(.top, SettingsLayoutMetrics.sidebarTopPadding)
                .padding(.bottom, SettingsLayoutMetrics.sidebarBottomPadding)
            }
            .scrollIndicators(.visible)
            .scrollContentBackground(.hidden)
        }
        .frame(width: SettingsChromeMetrics.sidebarWidth, alignment: .topLeading)
        .background(Color.clear)
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch appState.selectedSettingsDestination {
                    case .general:
                        SettingsPane(title: "General", subtitle: "Choose how Crona starts, appears, and marks the day.") {
                            GeneralSettingsView(appState: appState)
                        }
                    case .menuBar:
                        SettingsPane(title: "Menu Bar", subtitle: "Choose how Crona appears in the menu bar.") {
                            MenuBarSettingsView(appState: appState)
                        }
                    case .smartPause:
                        SettingsPane(title: "Smart Pause", subtitle: "Choose when Crona pauses and resumes automatically.") {
                            SmartPauseSettingsView(appState: appState)
                        }
                    case .breakScreen:
                        SettingsPane(title: "Break Screen", subtitle: "Choose how break time appears on your Mac.") {
                            BreakScreenSettingsView(appState: appState)
                        }
                    case .notifications:
                        SettingsPane(title: "Notifications", subtitle: "Choose how Crona alerts you.") {
                            NotificationSettingsView(appState: appState)
                        }
                    case .runtime:
                        SettingsPane(title: "Runtime", subtitle: "Review the active runtime and kernel connection.") {
                            RuntimeSettingsView(appState: appState)
                        }
                    case .diagnostics:
                        SettingsPane(title: "Diagnostics", subtitle: "Review runtime health and recent issues.") {
                            DiagnosticsSettingsView(appState: appState)
                        }
                    case .updates:
                        SettingsPane(title: "Updates", subtitle: "Review the installed build and update settings.") {
                            UpdatesSettingsView(appState: appState)
                        }
                    case .about:
                        SettingsPane(title: "About", subtitle: "See the installed version and release channel.") {
                            AboutSettingsView(appState: appState)
                        }
#if DEBUG
                    case .developer:
                        SettingsPane(title: "Developer", subtitle: "Preview companion presenters without touching the daemon.") {
                            DeveloperSettingsView(appState: appState)
                        }
#endif
                    }
                }
                .padding(.horizontal, SettingsLayoutMetrics.detailHorizontalPadding)
                .padding(.top, SettingsLayoutMetrics.detailTopPadding)
                .padding(.bottom, SettingsLayoutMetrics.detailBottomPadding)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .modifier(SettingsScrollEdgeEffectModifier())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PopupVisualTheme.windowBackground)
    }

}

private enum SettingsChromeMetrics {
    static let sidebarWidth: CGFloat = 210
    static let toolbarSurfaceHeight: CGFloat = 52
}

private enum SettingsLayoutMetrics {
    static let sidebarTopPadding: CGFloat = 20
    static let sidebarBottomPadding: CGFloat = 26
    static let detailHorizontalPadding: CGFloat = 28
    static let detailTopPadding: CGFloat = 20
    static let detailBottomPadding: CGFloat = 28
    static let sectionSpacing: CGFloat = 22
    static let cardHeaderSpacing: CGFloat = 10
    static let cardContentHorizontalPadding: CGFloat = 14
    static let cardContentVerticalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 18
    static let labelColumnWidth: CGFloat = 260
    static let controlColumnWidth: CGFloat = 178
    static let actionButtonMinimumHeight: CGFloat = 38
    static let actionButtonCornerRadius: CGFloat = 11
    static let detailCardCornerRadius: CGFloat = 14
}

private struct SettingsScrollEdgeEffectModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

private struct SettingsWindowToolbarChromeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 27.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else if #available(macOS 26.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else if #available(macOS 15.0, *) {
            content
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

private struct SettingsWindowToolbarBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbarBackground(.regularMaterial, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

private struct SettingsNavigationCluster: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            settingsToolbarButton(
                systemImage: "chevron.left",
                action: goBack,
                isEnabled: canGoBack
            )

            Divider()
                .frame(height: 18)
                .padding(.vertical, 4)
                .opacity(0.28)

            settingsToolbarButton(
                systemImage: "chevron.right",
                action: goForward,
                isEnabled: canGoForward
            )
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(PopupVisualTheme.primaryText.opacity(0.08))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(PopupVisualTheme.primaryText.opacity(0.1), lineWidth: 0.75)
                )
        )
    }

    private func settingsToolbarButton(
        systemImage: String,
        action: @escaping () -> Void,
        isEnabled: Bool
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? PopupVisualTheme.primaryText : PopupVisualTheme.secondaryText.opacity(0.55))
        .disabled(!isEnabled)
        .help(systemImage == "chevron.left" ? "Back" : "Forward")
    }
}

private struct SettingsToolbarSurfaceBackground: View {
    var body: some View {
        Group {
            if #available(macOS 27.0, *) {
                ZStack {
                    VisualEffectView(
                        material: .headerView,
                        blendingMode: .withinWindow,
                        emphasized: false
                    )

                    LinearGradient(
                        colors: [
                            PopupVisualTheme.windowBackground.opacity(0.72),
                            PopupVisualTheme.windowBackground.opacity(0.42),
                            PopupVisualTheme.windowBackground.opacity(0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottom) {
                    Divider()
                        .opacity(0.18)
                }
            } else if #available(macOS 26.0, *) {
                ZStack {
                    VisualEffectView(
                        material: .headerView,
                        blendingMode: .withinWindow,
                        emphasized: false
                    )

                    LinearGradient(
                        colors: [
                            PopupVisualTheme.windowBackground.opacity(0.56),
                            PopupVisualTheme.windowBackground.opacity(0.24),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottom) {
                    Divider()
                        .opacity(0.14)
                }
            } else {
                EmptyView()
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SettingsSidebarBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(false), in: Rectangle())
        } else {
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow, emphasized: true)
        }
    }
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
                .foregroundStyle(PopupVisualTheme.secondaryText)
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
            HStack(spacing: 12) {
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
                    .fill(isSelected ? PopupVisualTheme.primaryText.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? PopupVisualTheme.primaryText.opacity(0.08) : Color.clear, lineWidth: 0.75)
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
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Startup") {
                SettingsToggleRow(
                    title: "Launch at Login",
                    subtitle: "Choose whether Crona is ready in the menu bar when you sign in.",
                    isOn: Binding(
                        get: { appState.launchAtLoginService.isEnabled },
                        set: { appState.launchAtLoginService.setEnabled($0) }
                    )
                )

                SettingsToggleRow(
                    title: "Hide Dock Icon When Closed",
                    subtitle: "Choose whether Crona stays in the menu bar only unless a full app window is open.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.hideDockIconWhenNoWindowsOpen },
                        set: { appState.preferences.preferences.hideDockIconWhenNoWindowsOpen = $0 }
                    )
                )

                if let error = appState.launchAtLoginService.lastError, !error.isEmpty {
                    settingsFootnote(error)
                }
            }

            SettingsCard("Appearance") {
                SettingsPickerRow(
                    title: "Theme",
                    subtitle: "Choose a light or dark palette, or follow macOS.",
                    selection: Binding(
                        get: { appState.preferences.preferences.appearance },
                        set: { appState.preferences.preferences.appearance = $0 }
                    )
                ) {
                    ForEach(CompanionAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            }

            SettingsCard("Menu Popover") {
                SettingsToggleRow(
                    title: "Pin Popover",
                    subtitle: "Choose whether the popover stays open while you work with it.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.pinPopover },
                        set: { appState.preferences.preferences.pinPopover = $0 }
                    )
                )
            }

            DayBoundarySettingsCard(appState: appState)
        }
    }
}

private struct DayBoundarySettingsCard: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        SettingsCard("Crona Day") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Local times tell the daemon when a Crona day starts and ends.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                DayBoundaryScheduleEditor(
                    title: "Start of Day",
                    subtitle: "Defines when a new Crona day begins.",
                    key: "startOfDay",
                    schedule: appState.dayBoundarySettingsService.settings.startOfDay,
                    service: appState.dayBoundarySettingsService
                )

                DayBoundaryScheduleEditor(
                    title: "End of Day",
                    subtitle: "Defines when Crona stops counting into the next day.",
                    key: "endOfDay",
                    schedule: appState.dayBoundarySettingsService.settings.endOfDay,
                    service: appState.dayBoundarySettingsService
                )

                if !appState.daemonConnection.timezone.isEmpty {
                    Text("Timezone: \(appState.daemonConnection.timezone)")
                        .font(.caption2)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                }

                if let error = appState.dayBoundarySettingsService.lastErrorDescription,
                   !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .task {
            await appState.dayBoundarySettingsService.refresh()
        }
    }
}

private struct DayBoundaryScheduleEditor: View {
    let title: String
    let subtitle: String
    let key: String
    let schedule: CronaDayBoundarySchedule
    let service: DayBoundarySettingsService

    @State private var defaultTime = "00:00"
    @State private var overrides: [Int: String] = [:]
    @State private var draft: DayBoundaryOverrideDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { schedule.enabled },
                    set: { enabled in
                        service.setSchedule(
                            key,
                            schedule: CronaDayBoundarySchedule(
                                enabled: enabled,
                                defaultTime: defaultTime,
                                weekdayOverrides: overrides
                            )
                        )
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: SettingsLayoutMetrics.rowSpacing) {
                    Text("Default")
                        .font(.subheadline)
                        .foregroundStyle(isDefaultDisabled ? PopupVisualTheme.secondaryText.opacity(0.55) : PopupVisualTheme.primaryText)
                        .frame(width: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)

                    Spacer(minLength: 0)

                    DatePicker(
                        "",
                        selection: Binding(
                            get: { dayBoundaryTimeDate(from: defaultTime) },
                            set: { newDate in
                                defaultTime = dayBoundaryTimeString(from: newDate)
                                save()
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    .controlSize(.small)
                    .labelsHidden()
                    .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
                    .disabled(isDefaultDisabled)
                    .opacity(isDefaultDisabled ? 0.55 : 1)
                }
                .padding(.vertical, 10)

                Divider().opacity(0.35)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Weekday overrides")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(PopupVisualTheme.secondaryText)

                        Spacer(minLength: 0)

                        Button {
                            beginNewOverride()
                        } label: {
                            Label("Add Override", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hasAvailableWeekdays ? Color.accentColor : PopupVisualTheme.secondaryText)
                        .disabled(!hasAvailableWeekdays)
                    }

                    if groupedOverrides.isEmpty {
                        Text("No weekday overrides yet.")
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                            .padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(groupedOverrides) { group in
                                DayBoundaryOverrideGroupRow(
                                    group: group,
                                    onEdit: { beginEditing(group) },
                                    onDelete: { remove(group) }
                                )
                            }
                        }
                    }

                    if let draft {
                        DayBoundaryOverrideEditor(
                            draft: Binding(
                                get: { draft },
                                set: { self.draft = $0 }
                            ),
                            occupiedDays: occupiedDays(excluding: draft.originalDays),
                            onCancel: { self.draft = nil },
                            onSave: { saveDraft() }
                        )
                        .padding(.top, 6)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous)
                        .fill(PopupVisualTheme.primaryText.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous)
                                .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                        )
                )
            }
        }
        .onAppear { load() }
        .onChange(of: schedule) { _, _ in load() }
    }

    private var groupedOverrides: [DayBoundaryOverrideGroup] {
        Dictionary(grouping: overrides, by: { $0.value })
            .map { time, entries in
                DayBoundaryOverrideGroup(time: time, days: entries.map(\.key).sorted())
            }
            .sorted {
                if $0.time == $1.time {
                    return ($0.days.first ?? 0) < ($1.days.first ?? 0)
                }
                return $0.time < $1.time
            }
    }

    private var hasAvailableWeekdays: Bool {
        availableWeekdays.count > 0
    }

    private var availableWeekdays: [Int] {
        (1...7).filter { overrides[$0] == nil }
    }

    private var isDefaultDisabled: Bool {
        availableWeekdays.isEmpty
    }

    private func occupiedDays(excluding excludedDays: Set<Int>) -> Set<Int> {
        Set(overrides.keys).subtracting(excludedDays)
    }

    private func beginNewOverride() {
        guard hasAvailableWeekdays else { return }
        draft = DayBoundaryOverrideDraft(
            time: defaultTime,
            selectedDays: [],
            originalDays: []
        )
    }

    private func beginEditing(_ group: DayBoundaryOverrideGroup) {
        draft = DayBoundaryOverrideDraft(
            time: group.time,
            selectedDays: Set(group.days),
            originalDays: Set(group.days)
        )
    }

    private func remove(_ group: DayBoundaryOverrideGroup) {
        for weekday in group.days {
            overrides.removeValue(forKey: weekday)
        }
        save()
    }

    private func saveDraft() {
        guard let draft, !draft.selectedDays.isEmpty, isValidTime(draft.time) else { return }

        var projected = overrides
        for weekday in draft.originalDays {
            projected.removeValue(forKey: weekday)
        }
        for weekday in draft.selectedDays {
            projected[weekday] = draft.time
        }
        overrides = projected
        self.draft = nil
        save()
    }

    private func overrideBinding(for weekday: Int) -> Binding<String> {
        Binding(
            get: { overrides[weekday] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    overrides.removeValue(forKey: weekday)
                } else {
                    overrides[weekday] = value
                }
            }
        )
    }

    private func isValidTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2,
              parts[1].count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }

    private func timeSelectionBinding(for value: Binding<String>) -> Binding<Date> {
        Binding(
            get: { dateValue(for: value.wrappedValue) },
            set: { newDate in
                value.wrappedValue = timeString(from: newDate)
            }
        )
    }

    private func dateValue(for value: String) -> Date {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return Date()
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let baseDate = calendar.date(from: components) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? Date()
    }

    private func timeString(from date: Date) -> String {
        let calendar = Calendar.current
        return String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }

    private func load() {
        defaultTime = schedule.defaultTime
        overrides = schedule.weekdayOverrides
        draft = nil
    }

    private func save() {
        service.setSchedule(
            key,
            schedule: CronaDayBoundarySchedule(
                enabled: schedule.enabled,
                defaultTime: defaultTime,
                weekdayOverrides: overrides
            )
        )
    }

    fileprivate static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = weekday == 7 ? 0 : weekday
        return symbols[index]
    }

    fileprivate static func weekdayShortName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = weekday == 7 ? 0 : weekday
        return symbols[index]
    }
}

private struct DayBoundaryOverrideGroup: Identifiable, Equatable {
    let time: String
    let days: [Int]

    var id: String {
        "\(time)-\(days.map(String.init).joined(separator: ","))"
    }
}

private struct DayBoundaryOverrideDraft: Equatable {
    var time: String
    var selectedDays: Set<Int>
    var originalDays: Set<Int>
}

private func dayBoundaryTimeDate(from value: String) -> Date {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1])
    else {
        return Date()
    }

    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day], from: Date())
    let baseDate = calendar.date(from: components) ?? Date()
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? Date()
}

private func dayBoundaryTimeString(from date: Date) -> String {
    let calendar = Calendar.current
    return String(
        format: "%02d:%02d",
        calendar.component(.hour, from: date),
        calendar.component(.minute, from: date)
    )
}

private struct TimePopupPicker: View {
    let time: Binding<String>
    var isDisabled: Bool = false

    @State private var isPresented = false
    @State private var draftDate = Date()

    var body: some View {
        Button {
            guard !isDisabled else { return }
            draftDate = dateValue(for: time.wrappedValue)
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Text(time.wrappedValue)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isDisabled ? PopupVisualTheme.secondaryText.opacity(0.55) : PopupVisualTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PopupVisualTheme.primaryText.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose Time")
                        .font(.headline)
                    Text("Pick a clock time for this schedule.")
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Spacer(minLength: 0)
                        Text(timeString(from: draftDate))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(PopupVisualTheme.primaryText.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                            )
                    )

                    StepperRow(
                        title: "Hour",
                        value: hourBinding
                    )

                    StepperRow(
                        title: "Minute",
                        value: minuteBinding
                    )
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("Done") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(minWidth: 260)
            .onAppear {
                draftDate = dateValue(for: time.wrappedValue)
            }
        }
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: draftDate) },
            set: { newHour in
                draftDate = updatedDate(hour: newHour, minute: Calendar.current.component(.minute, from: draftDate))
                time.wrappedValue = timeString(from: draftDate)
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: draftDate) },
            set: { newMinute in
                draftDate = updatedDate(hour: Calendar.current.component(.hour, from: draftDate), minute: newMinute)
                time.wrappedValue = timeString(from: draftDate)
            }
        )
    }

    private func dateValue(for value: String) -> Date {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return Date()
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let baseDate = calendar.date(from: components) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? Date()
    }

    private func updatedDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: draftDate)
        let baseDate = calendar.date(from: components) ?? draftDate
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? draftDate
    }

    private func timeString(from date: Date) -> String {
        let calendar = Calendar.current
        return String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }
}

private struct StepperRow: View {
    let title: String
    let value: Binding<Int>

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(PopupVisualTheme.primaryText)
                .frame(width: 54, alignment: .leading)

            Stepper(value: value, in: title == "Hour" ? 0...23 : 0...59) {
                Text(formattedValue)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            .labelsHidden()
        }
    }

    private var formattedValue: String {
        String(format: "%02d", value.wrappedValue)
    }
}

private struct DayBoundaryOverrideGroupRow: View {
    let group: DayBoundaryOverrideGroup
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                WrapDayPills(days: group.days)

                Spacer(minLength: 0)

                Text(group.time)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                Button("Edit", action: onEdit)
                Button("Remove", action: onDelete)
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PopupVisualTheme.secondaryText)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PopupVisualTheme.primaryText.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                )
        )
    }
}

private struct DayBoundaryOverrideEditor: View {
    @Binding var draft: DayBoundaryOverrideDraft
    let occupiedDays: Set<Int>
    let onCancel: () -> Void
    let onSave: () -> Void

    private var isSaveEnabled: Bool {
        !draft.selectedDays.isEmpty && isValidTime(draft.time)
    }

    private func timeSelectionBinding(for value: Binding<String>) -> Binding<Date> {
        Binding(
            get: { dateValue(for: value.wrappedValue) },
            set: { newDate in
                value.wrappedValue = timeString(from: newDate)
            }
        )
    }

    private func dateValue(for value: String) -> Date {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return Date()
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let baseDate = calendar.date(from: components) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? Date()
    }

    private func timeString(from date: Date) -> String {
        let calendar = Calendar.current
        return String(
            format: "%02d:%02d",
            calendar.component(.hour, from: date),
            calendar.component(.minute, from: date)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Override Editor")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PopupVisualTheme.secondaryText)

                Spacer(minLength: 0)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                Button("Save", action: onSave)
                    .buttonStyle(.plain)
                    .foregroundStyle(isSaveEnabled ? Color.accentColor : PopupVisualTheme.secondaryText)
                    .disabled(!isSaveEnabled)
            }

            Text("Select weekdays that should share this time.")
                .font(.caption)
                .foregroundStyle(PopupVisualTheme.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 54), spacing: 8), count: 4), spacing: 8) {
                ForEach(1...7, id: \.self) { weekday in
                    let isSelected = draft.selectedDays.contains(weekday)
                    let isDisabled = occupiedDays.contains(weekday) && !isSelected

                    Button {
                        if isSelected {
                            draft.selectedDays.remove(weekday)
                        } else {
                            draft.selectedDays.insert(weekday)
                        }
                    } label: {
                        Text(DayBoundaryScheduleEditor.weekdayShortName(weekday))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                isSelected
                                    ? PopupVisualTheme.selectedControlText
                                    : isDisabled
                                        ? PopupVisualTheme.secondaryText.opacity(0.45)
                                        : PopupVisualTheme.primaryText
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? PopupVisualTheme.selectedControlBackground
                                            : PopupVisualTheme.primaryText.opacity(0.05)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                isSelected
                                                    ? PopupVisualTheme.highlightedBorder
                                                    : PopupVisualTheme.border,
                                                lineWidth: 0.75
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Time")
                    .font(.subheadline)
                    .frame(width: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
                DatePicker(
                    "",
                    selection: Binding(
                        get: { dayBoundaryTimeDate(from: draft.time) },
                        set: { newDate in
                            draft.time = dayBoundaryTimeString(from: newDate)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .controlSize(.small)
                .labelsHidden()
                    .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PopupVisualTheme.primaryText.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                )
        )
    }

    private func isValidTime(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2,
              parts[1].count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1])
        else {
            return false
        }
        return (0...23).contains(hour) && (0...59).contains(minute)
    }
}

private struct WrapDayPills: View {
    let days: [Int]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 50), spacing: 6), count: 4), spacing: 6) {
            ForEach(days, id: \.self) { weekday in
                Text(DayBoundaryScheduleEditor.weekdayShortName(weekday))
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .background(
                        Capsule()
                            .fill(PopupVisualTheme.primaryText.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                            )
                    )
            }
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Menu bar preview")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PopupVisualTheme.secondaryText)

                    HStack(spacing: 8) {
                        Spacer()
                        if appState.preferences.preferences.menuBarDisplayMode.showsIcon {
                            Image(nsImage: MenuBarIconProvider.image(for: previewIconState))
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
                            .fill(PopupVisualTheme.primaryText.opacity(0.08))
                            .overlay(Capsule().strokeBorder(PopupVisualTheme.primaryText.opacity(0.08), lineWidth: 0.75))
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
                    subtitle: "Choose whether idle text shows a quiet Idle label or today’s focus time.",
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Smart Pause") {
                SettingsToggleRow(
                    title: "Pause Automatically",
                    subtitle: "Choose whether a running stopwatch pauses when you step away from your Mac.",
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
                        subtitle: "Pause only after there has been no keyboard or mouse input for the selected time.",
                        isOn: binding(\.smartPauseOnInactivity)
                    )

                    if preferences.smartPauseOnInactivity {
                        SettingsPickerRow(
                            title: "No-Input Delay",
                            subtitle: "Choose how long to wait before pausing for keyboard and mouse inactivity.",
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
                    subtitle: "See when Crona resumes after it initiated the pause and every pause condition has cleared.",
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
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
                        subtitle: "Extra work time granted when the boundary is reached during activity.",
                        selection: Binding(
                            get: { preferences.breakScreenActivityExtensionSeconds },
                            set: { value in
                                appState.preferences.preferences.breakScreenActivityExtensionSeconds =
                                    CompanionPreferences.breakScreenActivityExtensionOptions.min {
                                        abs($0 - value) < abs($1 - value)
                                    } ?? 60
                            }
                        )
                    ) {
                        ForEach(CompanionPreferences.breakScreenActivityExtensionOptions, id: \.self) {
                            Text("\($0) seconds").tag($0)
                        }
                    }

                    SettingsPickerRow(
                        title: "Maximum Deferral",
                        subtitle: "Maximum extra time granted for one Pomodoro session.",
                        selection: Binding(
                            get: { preferences.breakScreenActivityDeferralCapSeconds },
                            set: { appState.preferences.preferences.breakScreenActivityDeferralCapSeconds = $0 }
                        )
                    ) {
                        ForEach(CompanionPreferences.breakScreenActivityCapOptions, id: \.self) {
                            Text("\($0 / 60) minutes").tag($0)
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
        .animation(.easeInOut(duration: 0.16), value: preferences.breakScreenMode)
        .animation(.easeInOut(duration: 0.16), value: preferences.breakScreenBackgroundStyle)
    }
}

private struct BreakScreenSolidColorSwatchPicker: View {
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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 42), spacing: 10), count: 6), spacing: 10) {
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
                                .fill(isSelected(swatch.color) ? Color.accentColor.opacity(0.12) : PopupVisualTheme.primaryText.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(isSelected(swatch.color) ? Color.accentColor.opacity(0.45) : PopupVisualTheme.border, lineWidth: 0.75)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous)
                .fill(PopupVisualTheme.primaryText.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous)
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
        .init(name: "Warm", color: .init(red: 0.52, green: 0.2, blue: 0.15, alpha: 1))
    ]
}

private struct BreakScreenSolidColorSwatch: Identifiable {
    let name: String
    let color: CompanionRGBAColor

    var id: String { name }
}

private struct BreakScreenModeCard: View {
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
                    .fill(selected ? Color.accentColor.opacity(0.16) : PopupVisualTheme.primaryText.opacity(0.045))
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

private struct BreakScreenSettingsPreview: View {
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

private struct NotificationSettingsView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var alertSettings: AlertSettingsService

    init(appState: CompanionAppState) {
        self.appState = appState
        _alertSettings = ObservedObject(wrappedValue: appState.alertSettingsService)
    }

    var body: some View {
        let settings = alertSettings.settings

        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("System Notifications") {
                SettingsValueRow(
                    title: "Permission",
                    subtitle: "See whether Crona can deliver alerts with native actions and sounds.",
                    value: notificationStatusText(
                        appState.notificationService.authorizationStatus
                    )
                )

                SettingsValueRow(
                    title: "Delivery",
                    subtitle: "See when the daemon falls back automatically if the app cannot deliver.",
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
                    subtitle: "Choose whether focus boundaries, reminders, and Crona updates appear in Notification Center.",
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
                    subtitle: "Choose whether the selected Crona sound plays when an alert needs your attention.",
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

                HStack(spacing: 12) {
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
                    subtitle: "Choose whether Crona nudges you when a focus session may have been left running.",
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
                    subtitle: "Choose how long to wait without activity before the first reminder.",
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
                    subtitle: "Choose how often to repeat follow-up reminders while the session stays active.",
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
                    subtitle: "Choose whether a small desktop prompt appears when that reminder fires.",
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
                    subtitle: "Choose whether End and Extend appear when a hard-limit session reaches its boundary.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showHardLimitActionPopups },
                        set: { appState.preferences.preferences.showHardLimitActionPopups = $0 }
                    )
                )

                SettingsToggleRow(
                    title: "Show Early Warning",
                    subtitle: "Choose whether a small warning appears beside the pointer before a session changes.",
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Preview Tools") {
                Text("These previews use local fixtures only. They never start, pause, extend, or end a daemon session.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)

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

            SettingsCard("Menu Bar Icon Preview") {
                MenuBarIconPreviewGrid()
            }
        }
    }
}
#endif

#if DEBUG
private struct MenuBarIconPreviewGrid: View {
    private let previews: [(String, MenuBarIconState)] = [
        ("Idle", .idle),
        ("Focus", .focus(progress: 0.55)),
        ("Paused", .paused(progress: 0.55)),
        ("Break", .breakTime(progress: 0.55)),
        ("Connecting", .connecting),
        ("Offline", .offline),
        ("Error", .error),
        ("Completed", .completed)
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 14) {
            ForEach(previews, id: \.0) { title, state in
                VStack(spacing: 7) {
                    Image(nsImage: MenuBarIconProvider.image(for: state))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
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
                subtitle: "See where Crona looks for the running kernel.",
                value: appState.kernelDiscovery.loadedRuntime.config.runtimeDirectoryPath
            )
            SettingsValueRow(
                title: "Discovery File",
                subtitle: "See the kernel.json currently used for discovery.",
                value: appState.kernelDiscovery.loadedRuntime.config.discoveryFilePath
            )
            SettingsValueRow(
                title: "Endpoint",
                subtitle: "See the socket Crona is connected through.",
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Snapshot") {
                SettingsValueRow(
                    title: "Connection State",
                    subtitle: "See whether the macOS app can reach Crona.",
                    value: appState.diagnosticsService.snapshot.connectionState
                )
                SettingsValueRow(
                    title: "Protocol Version",
                    subtitle: "See the protocol shared by the app and kernel.",
                    value: appState.diagnosticsService.snapshot.protocolVersion
                )
                SettingsValueRow(
                    title: "Kernel Version",
                    subtitle: "See the kernel build currently running.",
                    value: appState.diagnosticsService.snapshot.kernelVersion
                )
                SettingsValueRow(
                    title: "Runtime Directory",
                    subtitle: "See the active Crona runtime location.",
                    value: appState.diagnosticsService.snapshot.runtimeDirectory
                )
                SettingsValueRow(
                    title: "Health",
                    subtitle: "See the kernel’s latest health report.",
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Installed") {
                SettingsValueRow(
                    title: "Crona",
                    subtitle: "See the version currently installed on this Mac.",
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
                        subtitle: "See the most recent completed update check.",
                        value: lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            SettingsCard("Release Channel") {
                SettingsPickerRow(
                    title: "Channel",
                    subtitle: "Choose Stable for dependable releases or Beta for early access plus every stable update.",
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
                    subtitle: "Choose whether Crona looks for new releases quietly in the background.",
                    isOn: Binding(
                        get: { service.automaticallyChecksForUpdates },
                        set: { service.setAutomaticallyChecksForUpdates($0) }
                    )
                )

                SettingsToggleRow(
                    title: "Download Automatically",
                    subtitle: "Choose whether verified updates are prepared so they are ready when Crona next quits.",
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Crona for macOS") {
                HStack(spacing: 14) {
                    Image(nsImage: CronaAppIcon.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Crona")
                            .font(.title3.weight(.semibold))
                        Text("Focus stays in the daemon. Crona brings it naturally into macOS.")
                            .font(.subheadline)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
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
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.cardHeaderSpacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, SettingsLayoutMetrics.cardContentHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.cardContentVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous)
                    .fill(PopupVisualTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius, style: .continuous)
                            .strokeBorder(PopupVisualTheme.border, lineWidth: 0.75)
                    )
            )
        }
    }
}

private struct TimerDisplayStyleRow: View {
    let selection: Binding<MenuBarTimeFormat>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timer Display")
                    .font(.subheadline.weight(.medium))
                Text("Choose how an active timer fits into the menu bar.")
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
            }

            HStack(spacing: 12) {
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
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
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
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                Text(preview)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(PopupVisualTheme.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous)
                    .fill(selection.wrappedValue == style
                        ? Color.accentColor.opacity(0.12)
                        : PopupVisualTheme.primaryText.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous)
                            .strokeBorder(
                                selection.wrappedValue == style
                                    ? Color.accentColor.opacity(0.55)
                                    : PopupVisualTheme.primaryText.opacity(0.07),
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
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
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
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)

            Spacer(minLength: 0)

            Picker("", selection: selection) {
                content
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
            .padding(.top, 2)
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct InactivityPopupPositionRow: View {
    let selection: Binding<CompanionPopupPosition>

    var body: some View {
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Popup Position")
                    .font(.subheadline.weight(.medium))
                Text("Choose where the reminder appears on screen.")
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)

            Spacer(minLength: 0)

            placementGrid
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
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
                .fill(PopupVisualTheme.primaryText.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(PopupVisualTheme.primaryText.opacity(0.1), lineWidth: 0.75)
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
        HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)

            Spacer(minLength: 0)

            Text(value)
                .foregroundStyle(PopupVisualTheme.secondaryText)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: SettingsLayoutMetrics.controlColumnWidth, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
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
                .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
                .frame(minHeight: SettingsLayoutMetrics.actionButtonMinimumHeight)
                .background(
                    RoundedRectangle(cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous)
                        .fill(prominent ? PopupVisualTheme.primaryText.opacity(0.16) : PopupVisualTheme.primaryText.opacity(0.075))
                        .overlay(
                            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous)
                                .strokeBorder(
                                    prominent ? PopupVisualTheme.primaryText.opacity(0.2) : PopupVisualTheme.primaryText.opacity(0.11),
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
        HStack(spacing: 12) {
            content
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
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
                .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
                .frame(minHeight: SettingsLayoutMetrics.actionButtonMinimumHeight)
                .background(
                    RoundedRectangle(cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous)
                        .fill(PopupVisualTheme.primaryText.opacity(0.075))
                        .overlay(
                            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous)
                                .strokeBorder(PopupVisualTheme.primaryText.opacity(0.11), lineWidth: 0.75)
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
        .foregroundStyle(PopupVisualTheme.secondaryText)
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
