import AppKit
import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
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

            DateDisplaySettingsCard(appState: appState)

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

struct DateDisplaySettingsCard: View {
    @ObservedObject var appState: CompanionAppState
    @State private var customFormat = ""

    private let presets = [
        ("iso", "ISO (2026-08-16)"),
        ("us", "US (08/16/2026)"),
        ("europe", "Europe (16/08/2026)"),
        ("long", "Long (16 Aug 2026)"),
        ("custom", "Custom"),
    ]

    var body: some View {
        let settings = appState.coreSettingsService.settings

        SettingsCard("Date Display") {
            SettingsPickerRow(
                title: "Format",
                subtitle: "Use the same date format across Crona.",
                selection: Binding(
                    get: { settings.dateDisplayPreset },
                    set: { preset in
                        Task { await appState.coreSettingsService.patch(key: "dateDisplayPreset", value: .string(preset)) }
                    }
                )
            ) {
                ForEach(presets, id: \.0) { preset in
                    Text(preset.1).tag(preset.0)
                }
            }

            if settings.dateDisplayPreset == "custom" {
                HStack(spacing: SettingsLayoutMetrics.rowSpacing) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Custom format")
                            .font(.subheadline)
                        Text("Moment-style format, for example Do MMM YYYY.")
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                    }
                    Spacer()
                    TextField("Do MMM YYYY", text: $customFormat)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                    Button("Save") {
                        Task {
                            await appState.coreSettingsService.patch(
                                key: "dateDisplayFormat",
                                value: .string(customFormat)
                            )
                        }
                    }
                    .disabled(customFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, 8)
            }

            Text("Preview: \(CronaDateDisplayFormatter.string(fromISODate: "2026-08-16", settings: settings))")
                .font(.caption)
                .foregroundStyle(PopupVisualTheme.secondaryText)
        }
        .onAppear { customFormat = settings.dateDisplayFormat }
        .onChange(of: settings.dateDisplayFormat) { _, value in customFormat = value }
    }
}

struct AwaySettingsView: View {
    @ObservedObject var appState: CompanionAppState
    @State private var selectedDate = Date()

    private let weekdayNames = Calendar.current.weekdaySymbols

    var body: some View {
        let settings = appState.coreSettingsService.settings
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            SettingsCard("Away Mode") {
                SettingsToggleRow(
                    title: "Away Today",
                    subtitle: "Temporarily protect the current Crona day from focus work.",
                    isOn: Binding(
                        get: { settings.awayModeEnabled },
                        set: { enabled in Task { await appState.coreSettingsService.setAwayMode(enabled) } }
                    )
                )
            }

            SettingsCard("Recurring Days") {
                Text("Automatically mark these weekdays as away.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)

                ForEach(0..<7, id: \.self) { weekday in
                    let isSelected = settings.restWeekdays.contains(weekday)
                    Button {
                        var weekdays = Set(settings.restWeekdays)
                        if isSelected { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                        Task {
                            await appState.coreSettingsService.patch(
                                key: "restWeekdays",
                                value: .array(weekdays.sorted().map { .number(Double($0)) })
                            )
                        }
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : PopupVisualTheme.secondaryText)
                            Text(weekdayNames[weekday])
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsCard("Specific Dates") {
                HStack {
                    DatePicker("Add date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    Button("Add") { addSpecificDate() }
                }

                if settings.restSpecificDates.isEmpty {
                    Text("No specific away dates.")
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                } else {
                    ForEach(settings.restSpecificDates.sorted(), id: \.self) { date in
                        HStack {
                            Text(formattedPopoverDate(date, appState: appState))
                            Spacer()
                            Button {
                                removeSpecificDate(date)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                }
            }

            if let error = appState.coreSettingsService.lastErrorDescription, !error.isEmpty {
                settingsFootnote(error)
                    .foregroundStyle(.red)
            }
        }
    }

    private func addSpecificDate() {
        let date = wireDate(selectedDate)
        var dates = Set(appState.coreSettingsService.settings.restSpecificDates)
        dates.insert(date)
        Task {
            await appState.coreSettingsService.patch(
                key: "restSpecificDates",
                value: .array(dates.sorted().map { .string($0) })
            )
        }
    }

    private func removeSpecificDate(_ date: String) {
        let dates = appState.coreSettingsService.settings.restSpecificDates.filter { $0 != date }
        Task {
            await appState.coreSettingsService.patch(
                key: "restSpecificDates",
                value: .array(dates.sorted().map { .string($0) })
            )
        }
    }

    private func wireDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct DayBoundarySettingsCard: View {
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

struct DayBoundaryScheduleEditor: View {
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

struct DayBoundaryOverrideGroup: Identifiable, Equatable {
    let time: String
    let days: [Int]

    var id: String {
        "\(time)-\(days.map(String.init).joined(separator: ","))"
    }
}

struct DayBoundaryOverrideDraft: Equatable {
    var time: String
    var selectedDays: Set<Int>
    var originalDays: Set<Int>
}

struct TimePopupPicker: View {
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

struct StepperRow: View {
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

struct DayBoundaryOverrideGroupRow: View {
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

struct DayBoundaryOverrideEditor: View {
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

struct WrapDayPills: View {
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
