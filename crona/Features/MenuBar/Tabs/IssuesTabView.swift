import AppKit
import SwiftUI

struct IssuesTabView: View {
    @ObservedObject var appState: CompanionAppState
    let displayClock: PopupDisplayClock

    var body: some View {
        switch appState.daemonConnection.connectionState {
        case .connected:
            if appState.timerService.snapshot.sessionID != nil,
                appState.timerService.snapshot.state != "idle",
                appState.timerService.snapshot.state != "disconnected"
            {
                fitOrScroll {
                    ActiveTimerView(
                        appState: appState,
                        displayClock: displayClock
                    )
                }
            } else if appState.todayIsAway {
                AwayModeView(appState: appState)
            } else if let issue = appState.selectedFocusIssue {
                FocusStartConfigView(appState: appState, issue: issue)
            } else {
                fitOrScroll {
                    IdleFocusView(appState: appState)
                }
            }
        case .connecting, .disconnected, .idle:
            fitOrScroll {
                PlaceholderPanel(
                    icon: "bolt.horizontal.circle",
                    title: "Connecting to Crona",
                    subtitle: "The companion is waiting for the daemon to become available."
                )
            }
        case .incompatible, .error:
            fitOrScroll {
                VStack(spacing: 12) {
                    PlaceholderPanel(
                        icon: "exclamationmark.triangle.fill",
                        title: "Connection Error",
                        subtitle: appState.daemonConnection.lastErrorDescription
                            ?? "Unable to reach Crona."
                    )
                    if appState.daemonConnection.connectionState == .incompatible {
                        Link(destination: CronaConnectionFailure.updateURL) {
                            Label("Update Crona", systemImage: "arrow.up.circle")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private func fitOrScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ViewThatFits(in: .vertical) {
            content()

            ScrollView(.vertical) {
                content()
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 480)
        }
    }
}

struct AwayModeView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.semantic(.away).opacity(0.82))

            Text("Away Mode")
                .font(.title3.weight(.bold))
                .foregroundStyle(PopupVisualTheme.primaryText)

            Text("You chose to rest and recover today.")
                .font(.subheadline)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))
                .multilineTextAlignment(.center)

            if appState.coreSettingsService.settings.awayModeEnabled {
                Button {
                    appState.setAwayMode(false)
                } label: {
                    if appState.coreSettingsService.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Disable Away", systemImage: "sun.max.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.coreSettingsService.isSaving)
            } else {
                Text("Today is protected by a configured rest rule.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.52))
            }

            if let error = appState.coreSettingsService.lastErrorDescription, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
        .background(cardBackground(stroke: PopupVisualTheme.border, cornerRadius: 24))
    }
}

struct ActiveTimerView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var displayClock: PopupDisplayClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let now = displayClock.now
        let presentation = TimerPresentation.from(
            appState.timerService.snapshot,
            at: now
        )

        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: presentation.phaseSymbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.58))

                Text(presentation.phaseTitle)
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))

                Text(timeText(for: presentation))
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: presentation.mode != .stopwatch))
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.22),
                        value: presentation.displaySeconds
                    )
                    .foregroundStyle(PopupVisualTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            if let progress = presentation.progressFraction {
                ReverseProgressBar(progress: progress)
                    .frame(height: 6)
                    .padding(.horizontal, 8)
            }

            if let endDate = TimerEndProjection.activeEndDate(
                snapshot: appState.timerService.snapshot,
                now: now
            ) {
                EndsAtRow(date: endDate)
            }

            if hasContext {
                VStack(alignment: .center, spacing: 10) {
                    if let issue = appState.contextService.snapshot.issueTitle {
                        Label {
                            Text(issue)
                                .font(.headline)
                                .foregroundStyle(PopupVisualTheme.primaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: "record.circle.fill")
                                .foregroundStyle(PopupVisualTheme.semantic(.focus))
                        }
                    }

                    HStack(spacing: 14) {
                        if let repo = appState.contextService.snapshot.repoName {
                            compactMetaChip(icon: "folder.fill", text: repo)
                        }
                        if let stream = appState.contextService.snapshot.streamName {
                            compactMetaChip(icon: "arrow.triangle.branch", text: stream)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(cardBackground(stroke: PopupVisualTheme.border))
            }

            HStack(spacing: 10) {
                if presentation.canAdvance, let title = presentation.advanceTitle {
                    actionPill(
                        title,
                        fill: PopupVisualTheme.primaryText.opacity(0.18),
                        shortcut: nil,
                        shortcutLabel: nil,
                        action: appState.advanceTimer
                    )
                }
                if presentation.canPause {
                    actionPill(
                        "Pause",
                        fill: PopupVisualTheme.primaryText.opacity(0.18),
                        shortcut: KeyboardShortcut("p", modifiers: []),
                        shortcutLabel: "P"
                    ) {
                        appState.pauseTimer()
                    }
                }
                if presentation.canResume {
                    actionPill(
                        "Resume",
                        fill: PopupVisualTheme.primaryText.opacity(0.18),
                        shortcut: KeyboardShortcut("r", modifiers: []),
                        shortcutLabel: "R"
                    ) {
                        appState.resumeTimer()
                    }
                }
                if presentation.canEnd {
                    actionPill(
                        "End",
                        fill: PopupVisualTheme.primaryText.opacity(0.08),
                        shortcut: KeyboardShortcut("e", modifiers: []),
                        shortcutLabel: "E"
                    ) {
                        appState.endTimer()
                    }
                }
            }

            if let upcoming = presentation.upcomingSegment {
                MetricStripCard(
                    icon: upcoming.kind == .work ? "bolt.fill" : "cup.and.saucer.fill",
                    tint: upcoming.kind == .work ? PopupVisualTheme.semantic(.focus) : PopupVisualTheme.semantic(.breakTime),
                    title: upcoming.title,
                    value: shortDuration(upcoming.durationSeconds)
                )
            }
        }
    }

    private var hasContext: Bool {
        appState.contextService.snapshot.issueTitle != nil
            || appState.contextService.snapshot.repoName != nil
            || appState.contextService.snapshot.streamName != nil
    }

    private func compactMetaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
    }

    private func timeText(for presentation: TimerPresentation) -> String {
        MenuBarTextFormatter.formatClock(seconds: presentation.displaySeconds)
    }

    private func shortDuration(_ seconds: Int) -> String {
        MenuBarTextFormatter.formatCompactDuration(seconds: seconds)
    }

}

struct IdleFocusView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .foregroundStyle(PopupVisualTheme.semantic(.focus))
                    .frame(width: 22)
                Text(
                    formattedPopoverDate(
                        appState.dailyFocusService.snapshot.date, appState: appState)
                )
                .font(.title3.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 14)

            if appState.coreSettingsService.isSaving {
                ProgressView().controlSize(.small)
            }

            if let error = appState.coreSettingsService.lastErrorDescription, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.9))
            }

            if appState.dailyFocusService.snapshot.issues.isEmpty {
                PlaceholderPanel(
                    icon: "checkmark.circle",
                    title: "Today is clear",
                    subtitle: "No planned focus issues for today."
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(appState.dailyFocusService.snapshot.issues) { issue in
                        FocusIssueRow(appState: appState, issue: issue) {
                            appState.selectFocusIssue(issue)
                        }
                    }
                }
            }

            if let error = appState.issueActionsService.lastErrorMessage {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PopupVisualTheme.semantic(.warning))
                    Text(error)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        appState.issueActionsService.clearError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .menuBarIconHitTarget()
                }
                .font(.caption)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
                .padding(.horizontal, 4)
            }
        }
    }
}

struct FocusStartConfigView: View {
    @ObservedObject var appState: CompanionAppState
    let issue: DailyFocusIssue
    @StateObject private var editor: FocusStartConfigEditor
    @State private var expandedControl: FocusConfigControl?

    init(appState: CompanionAppState, issue: DailyFocusIssue) {
        self.appState = appState
        self.issue = issue
        _editor = StateObject(
            wrappedValue: FocusStartConfigEditor(
                initialState: FocusStartConfigState.defaultState(
                    estimateMinutes: issue.estimateMinutes,
                    workedSeconds: issue.workedSeconds
                )
            ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    appState.dismissStartConfig()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.8))
                .keyboardShortcut(.cancelAction)
                Spacer()
            }

            Text(formattedPopoverDate(appState.dailyFocusService.snapshot.date, appState: appState))
                .font(.caption.weight(.medium))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.55))

            Label {
                Text(issue.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(PopupVisualTheme.semantic(.focus))
            }

            SegmentedControl(
                selection: $editor.state.mode,
                title: \.title
            )
            .onChange(of: editor.state.mode) { _, newMode in
                editor.handleModeChange(newMode)
            }

            VStack(spacing: 10) {
                switch editor.state.mode {
                case .stopwatch:
                    MetricStripCard(
                        icon: "play.fill", tint: PopupVisualTheme.semantic(.success), title: "Open-ended focus",
                        value: "No hard limit")
                case .pomodoro:
                    ExpandablePresetRow(
                        icon: "bolt.fill",
                        tint: PopupVisualTheme.semantic(.focus),
                        title: "Focus",
                        displayValue: editor.focusDisplay,
                        choices: FocusStartConfigState.focusChoices,
                        selection: editor.state.focusChoice,
                        isExpanded: expandedControl == .focus,
                        customValue: $editor.state.customFocusMinutes,
                        allowsZero: false,
                        onToggle: { toggle(.focus) },
                        onSelect: {
                            editor.selectFocus($0)
                            collapseUnlessCustom($0)
                        }
                    )
                    ExpandablePresetRow(
                        icon: "cup.and.saucer.fill",
                        tint: PopupVisualTheme.semantic(.breakTime),
                        title: "Short break",
                        displayValue: editor.breakDisplay,
                        choices: FocusStartConfigState.shortBreakChoices,
                        selection: editor.state.breakChoice,
                        isExpanded: expandedControl == .shortBreak,
                        customValue: $editor.state.customBreakMinutes,
                        allowsZero: true,
                        onToggle: { toggle(.shortBreak) },
                        onSelect: {
                            editor.selectBreak($0)
                            if $0 == .noBreak {
                                expandedControl = nil
                            } else {
                                collapseUnlessCustom($0)
                            }
                        }
                    )
                    if editor.state.showsLongBreakControls {
                        ExpandablePresetRow(
                            icon: "moon.zzz.fill",
                            tint: PopupVisualTheme.semantic(.review),
                            title: "Long break",
                            displayValue: editor.longBreakDisplay,
                            choices: FocusStartConfigState.longBreakChoices,
                            selection: editor.state.longBreakChoice,
                            isExpanded: expandedControl == .longBreak,
                            customValue: $editor.state.customLongBreakMinutes,
                            allowsZero: true,
                            onToggle: { toggle(.longBreak) },
                            onSelect: {
                                editor.selectLongBreak($0)
                                if $0 == .noBreak {
                                    expandedControl = nil
                                } else {
                                    collapseUnlessCustom($0)
                                }
                            }
                        )
                    }
                    if editor.state.showsCycleControls {
                        ExpandableNumberRow(
                            icon: "repeat.circle.fill",
                            tint: PopupVisualTheme.semantic(.warning),
                            title: "Cycles",
                            displayValue: "\(editor.state.effectivePomodoroCycles)",
                            values: Array(1...12),
                            selection: editor.state.pomodoroCycles,
                            isExpanded: expandedControl == .cycles,
                            onToggle: { toggle(.cycles) },
                            onSelect: {
                                editor.state.pomodoroCycles = $0
                                expandedControl = nil
                            }
                        )
                    }
                    if editor.state.showsLongBreakAfterControls {
                        ExpandableNumberRow(
                            icon: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill",
                            tint: .mint,
                            title: "Long break after",
                            displayValue: "\(editor.state.effectiveCyclesBeforeLongBreak)",
                            values: Array(1...12),
                            selection: editor.state.pomodoroCyclesBeforeLongBreak,
                            isExpanded: expandedControl == .longBreakAfter,
                            onToggle: { toggle(.longBreakAfter) },
                            onSelect: {
                                editor.state.pomodoroCyclesBeforeLongBreak = $0
                                expandedControl = nil
                            }
                        )
                    }
                case .timer:
                    ExpandablePresetRow(
                        icon: "timer",
                        tint: PopupVisualTheme.semantic(.warning),
                        title: "Countdown",
                        displayValue: editor.countdownDisplay,
                        choices: FocusStartConfigState.countdownChoices,
                        selection: editor.state.countdownChoice,
                        isExpanded: expandedControl == .countdown,
                        customValue: $editor.state.customCountdownMinutes,
                        allowsZero: false,
                        onToggle: { toggle(.countdown) },
                        onSelect: {
                            editor.selectCountdown($0)
                            collapseUnlessCustom($0)
                        }
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: editor.state.breaksEnabled)
            .animation(.easeInOut(duration: 0.2), value: editor.state.longBreakEnabled)

            if let endDate = TimerEndProjection.startEndDate(config: editor.state) {
                EndsAtRow(date: endDate)
            }

            HStack {
                Spacer()
                actionPill(
                    "Start Focus",
                    fill: PopupVisualTheme.primaryText.opacity(0.18),
                    shortcut: .defaultAction,
                    shortcutLabel: "↩"
                ) {
                    appState.startSelectedFocusSession(using: editor.state)
                }
                Spacer()
            }
        }
        .onChange(of: editor.state.mode) {
            expandedControl = nil
        }
    }

    private func toggle(_ control: FocusConfigControl) {
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedControl = expandedControl == control ? nil : control
        }
    }

    private func collapseUnlessCustom(_ choice: FocusPresetChoice) {
        if choice != .custom {
            expandedControl = nil
        }
    }
}

struct FocusIssueRow: View {
    @ObservedObject var appState: CompanionAppState
    let issue: DailyFocusIssue
    let onStart: () -> Void
    @State private var isActionsHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(issue.title)
                        .font(.headline)
                        .foregroundStyle(PopupVisualTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(issue.title)
                } icon: {
                    Image(systemName: CronaIssueStatusPresentation.icon(for: issue.status))
                        .foregroundStyle(CronaIssueStatusPresentation.color(for: issue.status))
                }
                .onTapGesture {
                    appState.openIssueDetails(issue)
                }

                HStack(spacing: 12) {
                    metaLabel(
                        icon: CronaIssueStatusPresentation.icon(for: issue.status),
                        text: CronaIssueStatusPresentation.status(for: issue.status)?.title
                            ?? issue.status.replacingOccurrences(of: "_", with: " ").capitalized,
                        color: CronaIssueStatusPresentation.color(for: issue.status))
                    metaLabel(icon: "clock.fill", text: metaLine)
                }
                .padding(.leading, 24)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Spacer()

            Menu {
                Button {
                    appState.openIssueDetails(issue)
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }
                Button {
                    appState.presentIssueEditor(for: issue)
                } label: {
                    Label("Edit Issue", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    appState.presentDeleteIssue(for: issue)
                } label: {
                    Label("Delete Issue", systemImage: "trash")
                }

                Divider()
                Button {
                    appState.presentManualSession(for: issue)
                } label: {
                    Label("Log Session…", systemImage: "clock.fill")
                }

                Divider()
                statusMenu
                dueDateMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        PopupVisualTheme.primaryText.opacity(isActionsHovered ? 0.9 : 0.62)
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(PopupVisualTheme.primaryText.opacity(isActionsHovered ? 0.1 : 0))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onHover { isActionsHovered = $0 }
                    .animation(.easeOut(duration: 0.12), value: isActionsHovered)
                    .menuBarIconHitTarget()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Issue actions")

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.82))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                        .background(glassCapsuleBackground(emphasis: 0.08))
                }
                .buttonStyle(GlassPressButtonStyle())
                .help("Start focus")
                .accessibilityLabel("Start focus")
            }
        }
        .padding(16)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            Button {
                appState.presentIssueEditor(for: issue)
            } label: {
                Label("Edit Issue", systemImage: "pencil")
            }
            Button(role: .destructive) {
                appState.presentDeleteIssue(for: issue)
            } label: {
                Label("Delete Issue", systemImage: "trash")
            }
            Divider()
            Button {
                appState.presentManualSession(for: issue)
            } label: {
                Label("Log Session…", systemImage: "clock.fill")
            }
            Divider()
            statusMenu
            dueDateMenu
        }
        .disabled(isWorking)
    }

    @ViewBuilder
    private var statusMenu: some View {
        Menu {
            if let transitions = appState.issueActionsService.transitionsByIssueID[issue.id] {
                if let blockedReason = transitions.blockedReason {
                    Text(blockedReason)
                } else if transitions.allowedStatuses.isEmpty {
                    Text("No available transitions")
                } else {
                    ForEach(transitions.allowedStatuses) { status in
                        Button {
                            appState.requestIssueStatusChange(issue: issue, status: status)
                        } label: {
                            Label(status.title, systemImage: status.systemImage)
                        }
                    }
                }
            } else {
                Text("Loading statuses…")
            }
        } label: {
            Label("Change Status", systemImage: "arrow.triangle.branch")
        }
    }

    @ViewBuilder
    private var dueDateMenu: some View {
        Menu {
            Button {
                appState.setIssueDueDate(issue, date: anchorDate)
            } label: {
                Label("Today", systemImage: "calendar")
            }

            if let tomorrow = CronaCalendarDate.adding(days: 1, to: anchorDate) {
                Button {
                    appState.setIssueDueDate(issue, date: tomorrow)
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
            }

            if let nextWeek = CronaCalendarDate.adding(days: 7, to: anchorDate) {
                Button {
                    appState.setIssueDueDate(issue, date: nextWeek)
                } label: {
                    Label("Next Week", systemImage: "calendar.badge.plus")
                }
            }

            Divider()

            Button {
                appState.presentCustomDueDate(for: issue)
            } label: {
                Label("Choose Date…", systemImage: "calendar.circle")
            }

            if issue.todoForDate != nil {
                Button(role: .destructive) {
                    appState.clearIssueDueDate(issue)
                } label: {
                    Label("Clear Due Date", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            Label("Due Date", systemImage: "calendar")
        }
    }

    private var anchorDate: String {
        let value = appState.dailyFocusService.snapshot.date
        if !value.isEmpty { return value }
        return appState.daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString()
            : appState.daemonConnection.currentDate
    }

    private var isWorking: Bool {
        appState.issueActionsService.actionInFlightIssueID == issue.id
    }

    private var metaLine: String {
        let worked = MenuBarTextFormatter.formatCompactDuration(seconds: issue.workedSeconds)
        if let estimate = issue.estimateMinutes, estimate > 0 {
            return "\(worked) / \(estimate)m"
        }
        return worked
    }

    private func metaLabel(icon: String, text: String, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(color ?? PopupVisualTheme.primaryText.opacity(0.62))
    }
}
