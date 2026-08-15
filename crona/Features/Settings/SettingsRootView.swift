import AppKit
import SwiftUI
import UserNotifications

struct SettingsRootView: View {
    @ObservedObject var appState: CompanionAppState
    @State private var sidebarSelection: SettingsDestination

    init(appState: CompanionAppState) {
        self.appState = appState
        _sidebarSelection = State(initialValue: appState.selectedSettingsDestination)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            settingsWorkArea
        }
        .frame(minWidth: 860, minHeight: 620)
        .ignoresSafeArea(.container, edges: .top)
        .background(
            SettingsWindowReader(
                windowService: appState.windowService,
                appearance: appState.preferences.preferences.appearance
            )
        )
        .companionAppearance(appState)
        .onChange(of: sidebarSelection) { _, destination in
            appState.setSelectedSettingsDestination(destination)
        }
        .onChange(of: appState.selectedSettingsDestination) { _, destination in
            guard destination != sidebarSelection else { return }
            sidebarSelection = destination
        }
    }

    private var settingsSidebar: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, emphasized: true)

            VStack(spacing: 0) {
                List(selection: $sidebarSelection) {
                    sidebarSection("Preferences", items: [.general, .menuBar])
                    sidebarSection(
                        "Focus", items: [.daySchedule, .smartPause, .breakScreen, .notifications])
                    sidebarSection("System", items: [.advanced])
                    sidebarSection("Crona", items: [.about])
                    #if DEBUG
                        sidebarSection("Developer", items: [.developer])
                    #endif
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .padding(.top, 32)
            }
        }
        .frame(width: SettingsChromeMetrics.sidebarWidth)
    }

    @ViewBuilder
    private func sidebarSection(_ title: String, items: [SettingsDestination]) -> some View {
        Section(title) {
            ForEach(items) { item in
                Label(item.title, systemImage: item.iconName)
                    .tag(item)
                    .help(item.title)
            }
        }
    }

    private var settingsWorkArea: some View {
        VStack(spacing: 0) {
            settingsToolbar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsPageContent
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
        .background(
            VisualEffectView(
                material: .contentBackground, blendingMode: .withinWindow, emphasized: false)
        )
    }

    @ViewBuilder
    private var settingsPageContent: some View {
        switch sidebarSelection {
        case .general:
            SettingsPane(
                title: "General",
                subtitle: "Choose how Crona starts and looks on this Mac."
            ) {
                GeneralSettingsView(appState: appState)
            }
        case .menuBar:
            SettingsPane(
                title: "Menu Bar", subtitle: "Choose what Crona shows while you work."
            ) {
                MenuBarSettingsView(appState: appState)
            }
        case .daySchedule:
            SettingsPane(
                title: "Day Schedule",
                subtitle: "Set when each Crona day starts and ends."
            ) {
                DayBoundarySettingsCard(appState: appState)
            }
        case .smartPause:
            SettingsPane(
                title: "Smart Pause",
                subtitle: "Pause Stopwatch sessions when you step away."
            ) {
                SmartPauseSettingsView(appState: appState)
            }
        case .breakScreen:
            SettingsPane(
                title: "Breaks",
                subtitle: "Choose how Pomodoro breaks appear on your displays."
            ) {
                BreakScreenSettingsView(appState: appState)
            }
        case .notifications:
            SettingsPane(
                title: "Notifications",
                subtitle: "Choose which alerts appear and how they get your attention."
            ) {
                NotificationSettingsView(appState: appState)
            }
        case .advanced:
            SettingsPane(
                title: "Advanced",
                subtitle: "Check Crona’s local service connection and diagnostics."
            ) {
                RuntimeSettingsView(appState: appState)
                DiagnosticsSettingsView(appState: appState)
            }
        case .about:
            SettingsPane(
                title: "About",
                subtitle: "View version details, updates, and release information."
            ) {
                AboutSettingsView(appState: appState)
                UpdatesSettingsView(appState: appState)
            }
        #if DEBUG
            case .developer:
                SettingsPane(
                    title: "Developer",
                    subtitle: "Open safe, local previews of Crona’s transient surfaces."
                ) {
                    DeveloperSettingsView(appState: appState)
                }
        #endif
        }
    }

    private var settingsToolbar: some View {
        HStack(spacing: 12) {
            Text(sidebarSelection.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: SettingsChromeMetrics.toolbarHeight)
        .background(
            VisualEffectView(material: .headerView, blendingMode: .behindWindow, emphasized: false)
        )
    }

}

private enum SettingsChromeMetrics {
    static let sidebarWidth: CGFloat = 236
    static let toolbarHeight: CGFloat = 52
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
                    subtitle: "Open Crona when you sign in.",
                    isOn: Binding(
                        get: { appState.launchAtLoginService.isEnabled },
                        set: { appState.launchAtLoginService.setEnabled($0) }
                    )
                )

                SettingsToggleRow(
                    title: "Show Dock Icon",
                    subtitle: "Keep Crona in the Dock when no windows are open.",
                    isOn: Binding(
                        get: { !appState.preferences.preferences.hideDockIconWhenNoWindowsOpen },
                        set: {
                            appState.preferences.preferences.hideDockIconWhenNoWindowsOpen = !$0
                        }
                    )
                )

                if let error = appState.launchAtLoginService.lastError, !error.isEmpty {
                    settingsFootnote(error)
                }
            }

            SettingsCard("Appearance") {
                SettingsPickerRow(
                    title: "Appearance",
                    subtitle: "Use the system appearance, Light, or Dark.",
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

            SettingsCard("Menu") {
                SettingsToggleRow(
                    title: "Keep Menu Open",
                    subtitle: "Keep the menu open until you dismiss it.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.pinPopover },
                        set: { appState.preferences.preferences.pinPopover = $0 }
                    )
                )
            }

            SettingsCard("Access") {
                SettingsShortcutRow(
                    shortcut: Binding(
                        get: { appState.preferences.preferences.settingsShortcut },
                        set: { appState.preferences.preferences.settingsShortcut = $0 }
                    )
                )
            }

        }
    }
}

private struct DayBoundarySettingsCard: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            if !appState.daemonConnection.timezone.isEmpty {
                Label(appState.daemonConnection.timezone, systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
            }

            SettingsCard("Start of Day") {
                VStack(alignment: .leading, spacing: 12) {
                    DayBoundaryScheduleEditor(
                        title: "Schedule",
                        subtitle: "When a new Crona day begins.",
                        key: "startOfDay",
                        schedule: appState.dayBoundarySettingsService.settings.startOfDay,
                        service: appState.dayBoundarySettingsService
                    )
                }
            }

            SettingsCard("End of Day") {
                DayBoundaryScheduleEditor(
                    title: "Schedule",
                    subtitle: "When Crona stops counting into the current day.",
                    key: "endOfDay",
                    schedule: appState.dayBoundarySettingsService.settings.endOfDay,
                    service: appState.dayBoundarySettingsService
                )
            }

            if let error = appState.dayBoundarySettingsService.lastErrorDescription,
                !error.isEmpty
            {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
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

                Toggle(
                    "",
                    isOn: Binding(
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
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: SettingsLayoutMetrics.rowSpacing) {
                    Text("Default")
                        .font(.subheadline)
                        .foregroundStyle(
                            isDefaultDisabled
                                ? PopupVisualTheme.secondaryText.opacity(0.55)
                                : PopupVisualTheme.primaryText
                        )
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
                        .foregroundStyle(
                            hasAvailableWeekdays
                                ? Color.accentColor : PopupVisualTheme.secondaryText
                        )
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
                    RoundedRectangle(
                        cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius,
                        style: .continuous
                    )
                    .fill(PopupVisualTheme.primaryText.opacity(0.04))
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: SettingsLayoutMetrics.detailCardCornerRadius,
                            style: .continuous
                        )
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
            .foregroundStyle(
                isDisabled
                    ? PopupVisualTheme.secondaryText.opacity(0.55) : PopupVisualTheme.primaryText
            )
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
                draftDate = updatedDate(
                    hour: newHour, minute: Calendar.current.component(.minute, from: draftDate))
                time.wrappedValue = timeString(from: draftDate)
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: draftDate) },
            set: { newMinute in
                draftDate = updatedDate(
                    hour: Calendar.current.component(.hour, from: draftDate), minute: newMinute)
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
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate)
            ?? draftDate
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
                    .foregroundStyle(
                        isSaveEnabled ? Color.accentColor : PopupVisualTheme.secondaryText
                    )
                    .disabled(!isSaveEnabled)
            }

            Text("Select weekdays that should share this time.")
                .font(.caption)
                .foregroundStyle(PopupVisualTheme.secondaryText)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 54), spacing: 8), count: 4),
                spacing: 8
            ) {
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
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 50), spacing: 6), count: 4),
            spacing: 6
        ) {
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

private struct SettingsPreviewFrame<Content: View>: View {
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

private struct SettingsPopupPreviewStage<Content: View>: View {
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

private struct SettingsPopupPreviewChrome<Content: View>: View {
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

private struct SettingsInactivityPreviewButtonStyle: ButtonStyle {
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

private struct SettingsMenuBarStrip: View {
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

private struct MenuBarSettingsPreview: View {
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

private struct FloatingTimerSettingsPreview: View {
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

private struct FocusResumeSettingsPreview: View {
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

private struct InactivityReminderSettingsPreview: View {
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

private struct WarningIndicatorSettingsPreview: View {
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

private struct BreakScreenSettingsView: View {
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
                    subtitle: "Access to native alerts, actions, and sounds.",
                    value: notificationStatusText(
                        appState.notificationService.authorizationStatus
                    )
                )

                SettingsValueRow(
                    title: "Delivery",
                    subtitle:
                        "See when the daemon falls back automatically if the app cannot deliver.",
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
                    subtitle: "Show boundaries, reminders, and updates in Notification Center.",
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
                    subtitle: "Play a sound when an alert needs attention.",
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
                    subtitle: "How strongly alerts can interrupt you.",
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

                    SettingsActionButton(
                        "Play Sound", systemImage: "speaker.wave.2.fill", prominent: false
                    ) {
                        appState.sendTestSound()
                    }
                }
                .disabled(appState.daemonConnection.connectionState != .connected)
            }

            SettingsCard("Focus Reminders") {
                SettingsToggleRow(
                    title: "Inactivity Reminder",
                    subtitle: "Nudge you when a session may have been left running.",
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
                    subtitle: "Wait before the first reminder.",
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
                    subtitle: "Repeat while the session stays active.",
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
                    subtitle: "Show desktop actions with the reminder.",
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

                InactivityReminderSettingsPreview()
            }

            SettingsCard("Focus Boundaries") {
                SettingsToggleRow(
                    title: "Show Action Popup",
                    subtitle: "Show End and Extend at a session boundary.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showHardLimitActionPopups },
                        set: { appState.preferences.preferences.showHardLimitActionPopups = $0 }
                    )
                )

                SettingsToggleRow(
                    title: "Show Early Warning",
                    subtitle: "Show a pointer-side warning before a session changes.",
                    isOn: Binding(
                        get: { appState.preferences.preferences.showHardLimitWarningIndicator },
                        set: { appState.preferences.preferences.showHardLimitWarningIndicator = $0 }
                    )
                )

                SettingsPickerRow(
                    title: "Warn Me",
                    subtitle: "Lead time for the early warning.",
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

                WarningIndicatorSettingsPreview(
                    leadSeconds: CompanionPreferences.normalizedHardLimitWarningLeadSeconds(
                        appState.preferences.preferences.hardLimitWarningLeadSeconds
                    )
                )
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
                    Text(
                        "These previews use local fixtures only. They never start, pause, extend, or end a daemon session."
                    )
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)

                    SettingsActionGroup {
                        SettingsActionButton("Hard Limit Flow", systemImage: "hourglass.circle") {
                            appState.showDeveloperHardLimitPreview()
                        }
                        SettingsActionButton(
                            "Inactivity Prompt", systemImage: "timer.circle", prominent: false
                        ) {
                            appState.showDeveloperInactivityPreview()
                        }
                    }

                    SettingsActionGroup {
                        SettingsActionButton(
                            "Warning Indicator", systemImage: "exclamationmark.circle",
                            prominent: false
                        ) {
                            appState.showDeveloperWarningPreview()
                        }
                        SettingsActionButton(
                            "Focus Resumed", systemImage: "play.circle", prominent: false
                        ) {
                            appState.showDeveloperSmartPauseResumePreview()
                        }
                        SettingsActionButton(
                            "Break Screen", systemImage: "moon.stars", prominent: false
                        ) {
                            appState.showDeveloperBreakScreenPreview()
                        }
                    }
                }

                SettingsCard("Cleanup") {
                    SettingsActionGroup {
                        SettingsActionButton(
                            "Dismiss All Previews", systemImage: "xmark.circle", prominent: false
                        ) {
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
            ("Completed", .completed),
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

private struct DiagnosticsSettingsView: View {
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

private struct UpdatesSettingsView: View {
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

private struct AboutSettingsView: View {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.secondaryText)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, SettingsLayoutMetrics.cardContentHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.cardContentVerticalPadding)
            .background(
                PopupVisualTheme.cardBackground,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .strokeBorder(PopupVisualTheme.border.opacity(0.72), lineWidth: 0.75)
            }
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
                Text("How an active timer fits in the menu bar.")
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
                    Image(
                        systemName: selection.wrappedValue == style
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        selection.wrappedValue == style ? Color.accentColor : .secondary)
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
                RoundedRectangle(
                    cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius, style: .continuous
                )
                .fill(
                    selection.wrappedValue == style
                        ? Color.accentColor.opacity(0.12)
                        : PopupVisualTheme.primaryText.opacity(0.045)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: SettingsLayoutMetrics.actionButtonCornerRadius,
                        style: .continuous
                    )
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
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

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
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

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
    var title = "Popup Position"
    var subtitle = "Choose where the reminder appears on screen."
    var accessibilityTitle = "Inactivity popup position"

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
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

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
        .accessibilityLabel(accessibilityTitle)
    }

    private func positionRow(_ positions: [CompanionPopupPosition]) -> some View {
        HStack(spacing: 20) {
            ForEach(positions) { position in
                Button {
                    selection.wrappedValue = position
                } label: {
                    Circle()
                        .fill(
                            selection.wrappedValue == position
                                ? Color.accentColor : Color.secondary.opacity(0.5)
                        )
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

private struct TimerHUDPositionRow: View {
    let selection: Binding<CompanionPopupPosition>

    var body: some View {
        InactivityPopupPositionRow(
            selection: selection,
            title: "Default Position",
            subtitle: "Choose where the timer first appears on screen.",
            accessibilityTitle: "Floating timer default position"
        )
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
            .frame(maxWidth: SettingsLayoutMetrics.labelColumnWidth, alignment: .leading)
            .layoutPriority(1)

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
                .frame(minHeight: 22)
        }
        .buttonStyle(.bordered)
        .tint(prominent ? Color.accentColor : nil)
        .controlSize(.regular)
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
                .frame(minHeight: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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
    let appearance: CompanionAppearance

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
            windowService.registerSettingsWindow(window, appearance: appearance)
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

extension SettingsDestination {
    fileprivate var title: String {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .daySchedule: return "Day Schedule"
        case .smartPause: return "Smart Pause"
        case .breakScreen: return "Breaks"
        case .notifications: return "Notifications"
        case .advanced: return "Advanced"
        case .about: return "About"
        #if DEBUG
            case .developer: return "Dev"
        #endif
        }
    }

    fileprivate var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .menuBar: return "menubar.rectangle"
        case .daySchedule: return "calendar.badge.clock"
        case .smartPause: return "pause.circle.fill"
        case .breakScreen: return "moon.stars.fill"
        case .notifications: return "bell.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        case .about: return "info.circle.fill"
        #if DEBUG
            case .developer: return "hammer.fill"
        #endif
        }
    }
}
