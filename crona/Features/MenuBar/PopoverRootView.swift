import Combine
import SwiftUI

enum PopoverModalKind {
    case statusNote
    case endSession
    case dueDate

    var minimumHeight: CGFloat {
        switch self {
        case .statusNote: return 260
        case .endSession: return 360
        case .dueDate: return 430
        }
    }
}

struct PopoverRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(spacing: 16) {
            header

            if appState.hasActiveFocusSession {
                NowTabView(appState: appState)
            } else {
                switch appState.selectedPopoverTab {
                case .now:
                    NowTabView(appState: appState)
                case .habits:
                    HabitsTabView(appState: appState)
                case .stats:
                    StatsTabView(appState: appState)
                }
            }

            if let error = appState.daemonConnection.lastErrorDescription,
                !error.isEmpty,
                appState.daemonConnection.connectionState == .connected
            {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .lineLimit(2)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(width: 420)
        .frame(minHeight: modalMinimumHeight)
        .background(PopoverGlassBackground())
        .opacity(hasPresentedModal ? 0.38 : 1)
        .blur(radius: hasPresentedModal ? 3 : 0)
        .scaleEffect(hasPresentedModal ? 0.985 : 1)
        .allowsHitTesting(!hasPresentedModal)
        .overlay {
            if appState.isEndSessionSheetPresented {
                PopoverModalScrim {
                    if !appState.isSubmittingEndSession {
                        appState.cancelEndSession()
                    }
                }

                EndSessionSheetView(appState: appState)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .overlay {
            if appState.issueActionEditor != nil {
                PopoverModalScrim {
                    appState.cancelIssueActionEditor()
                }

                IssueActionEditorView(appState: appState)
                    .padding(.horizontal, 28)
                    .transition(
                        .scale(scale: 0.96)
                            .combined(with: .opacity)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .animation(.easeInOut(duration: 0.16), value: appState.isEndSessionSheetPresented)
        .animation(.easeInOut(duration: 0.16), value: appState.issueActionEditor)
    }

    private var hasPresentedModal: Bool {
        appState.isEndSessionSheetPresented || appState.issueActionEditor != nil
    }

    private var modalMinimumHeight: CGFloat? {
        if appState.isEndSessionSheetPresented {
            return PopoverModalKind.endSession.minimumHeight
        }
        switch appState.issueActionEditor {
        case .status:
            return PopoverModalKind.statusNote.minimumHeight
        case .dueDate:
            return PopoverModalKind.dueDate.minimumHeight
        case nil:
            return nil
        }
    }

    private var header: some View {
        ZStack {
            if !appState.hasActiveFocusSession {
                SegmentedControl(
                    selection: $appState.selectedPopoverTab,
                    title: \.title
                )
                .frame(width: 210)
                .onChange(of: appState.selectedPopoverTab) { _, newTab in
                    appState.setSelectedPopoverTab(newTab)
                }
            }

            HStack {
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        appState.dismissMenuBarPopup()
                    }
                )
                .keyboardShortcut(",", modifiers: [.command])
                .help("Open Settings")
                .accessibilityLabel("Open Settings")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30)
    }
}

struct NowTabView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        Group {
            switch appState.daemonConnection.connectionState {
            case .connected:
                if appState.timerService.snapshot.sessionID != nil,
                    appState.timerService.snapshot.state != "idle",
                    appState.timerService.snapshot.state != "disconnected"
                {
                    ActiveTimerView(appState: appState)
                } else if let issue = appState.selectedFocusIssue {
                    FocusStartConfigView(appState: appState, issue: issue)
                } else {
                    IdleFocusView(appState: appState)
                }
            case .connecting, .disconnected, .idle:
                PlaceholderPanel(
                    icon: "bolt.horizontal.circle",
                    title: "Connecting to Crona",
                    subtitle: "The companion is waiting for the daemon to become available."
                )
            case .incompatible, .error:
                PlaceholderPanel(
                    icon: "exclamationmark.triangle.fill",
                    title: "Connection Error",
                    subtitle: appState.daemonConnection.lastErrorDescription
                        ?? "Unable to reach Crona."
                )
            }
        }
    }
}

struct ActiveTimerView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        let presentation = TimerPresentation.from(appState.timerService.snapshot)

        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: presentation.phaseSymbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.58))

                Text(presentation.phaseTitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.68))

                Text(timeText(for: presentation))
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            if let progress = presentation.progressFraction {
                ReverseProgressBar(progress: progress)
                    .frame(height: 6)
                    .padding(.horizontal, 8)
            }

            if let endDate = TimerEndProjection.activeEndDate(snapshot: appState.timerService.snapshot) {
                EndsAtRow(date: endDate)
            }

            if hasContext {
                VStack(alignment: .center, spacing: 10) {
                    if let issue = appState.contextService.snapshot.issueTitle {
                        Label {
                            Text(issue)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: "record.circle.fill")
                                .foregroundStyle(.yellow)
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
                .background(cardBackground(stroke: Color.white.opacity(0.08)))
            }

            HStack(spacing: 10) {
                if presentation.canPause {
                    actionPill(
                        "Pause",
                        fill: Color.white.opacity(0.18),
                        shortcut: KeyboardShortcut("p", modifiers: []),
                        shortcutLabel: "P"
                    ) {
                        appState.pauseTimer()
                    }
                }
                if presentation.canResume {
                    actionPill(
                        "Resume",
                        fill: Color.white.opacity(0.18),
                        shortcut: KeyboardShortcut("r", modifiers: []),
                        shortcutLabel: "R"
                    ) {
                        appState.resumeTimer()
                    }
                }
                if presentation.canEnd {
                    actionPill(
                        "End",
                        fill: Color.white.opacity(0.08),
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
                    tint: upcoming.kind == .work ? .yellow : .pink,
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
        .foregroundStyle(.white.opacity(0.72))
    }

    private func timeText(for presentation: TimerPresentation) -> String {
        MenuBarTextFormatter.formatElapsed(
            seconds: presentation.displaySeconds,
            format: appState.preferences.preferences.menuBarTimeFormat,
            showsSeconds: appState.preferences.preferences.menuBarShowsSeconds
        )
    }

    private func shortDuration(_ seconds: Int) -> String {
        MenuBarTextFormatter.formatElapsed(seconds: seconds, format: .expanded, showsSeconds: false)
    }

}

struct IdleFocusView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .foregroundStyle(.yellow)
                Text("Ready to Focus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
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
                        .foregroundStyle(.yellow)
                    Text(error)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        appState.issueActionsService.clearError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
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
                .foregroundStyle(.white.opacity(0.8))
                .keyboardShortcut(.cancelAction)
                Spacer()
            }

            Label {
                Text(issue.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.yellow)
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
                        icon: "play.fill", tint: .green, title: "Open-ended focus",
                        value: "No hard limit")
                case .pomodoro:
                    ExpandablePresetRow(
                        icon: "bolt.fill",
                        tint: .yellow,
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
                        tint: .pink,
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
                            tint: .purple,
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
                            tint: .orange,
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
                        tint: .orange,
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
                    fill: Color.white.opacity(0.18),
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

struct StatsTabView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        let snapshot = appState.popoverStatsService.snapshot

        VStack(spacing: 12) {
            HStack(spacing: 10) {
                statsDateArrow(systemName: "chevron.left") {
                    appState.popoverStatsService.showPreviousDay()
                }

                Text(statsTitle(for: snapshot.date))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(glassCapsuleBackground())

                statsDateArrow(
                    systemName: "chevron.right",
                    isEnabled: appState.popoverStatsService.canShowNextDay()
                ) {
                    appState.popoverStatsService.showNextDay()
                }
            }

            ScrollView(.vertical) {
                ZStack {
                    VStack(spacing: 12) {
                        if let score = snapshot.focusScore, let metrics = snapshot.todayMetrics {
                            scoreHero(score: score, message: snapshot.scoreMessage)
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                ],
                                spacing: 10
                            ) {
                                StatsMetricTile(
                                    icon: "bolt.fill",
                                    tint: .yellow,
                                    title: "Focus",
                                    value: compactDuration(metrics.workedSeconds)
                                )
                                StatsMetricTile(
                                    icon: "cup.and.saucer.fill",
                                    tint: .pink,
                                    title: "Breaks",
                                    value: compactDuration(metrics.restSeconds)
                                )
                                StatsMetricTile(
                                    icon: "rectangle.stack.fill",
                                    tint: .orange,
                                    title: "Sessions",
                                    value: "\(metrics.sessionCount)"
                                )
                                StatsMetricTile(
                                    icon: "scope",
                                    tint: .mint,
                                    title: "Target",
                                    value: compactDuration(score.targetWorkedSeconds)
                                )
                            }

                            FocusRestBalanceView(
                                workedSeconds: metrics.workedSeconds,
                                restSeconds: metrics.restSeconds
                            )

                            StatsOutcomeCard(
                                icon: "checkmark.circle.fill",
                                tint: .green,
                                title: "Issues",
                                values: [
                                    ("Completed", metrics.completedIssues),
                                    ("Planned", metrics.totalIssues),
                                    ("Abandoned", metrics.abandonedIssues),
                                ]
                            )

                            StatsOutcomeCard(
                                icon: "checklist.checked",
                                tint: .cyan,
                                title: "Habits",
                                values: [
                                    ("Done", metrics.habitCompletedCount),
                                    ("Due", metrics.habitDueCount),
                                    ("Failed", metrics.habitFailedCount),
                                ]
                            )
                        } else if !snapshot.isLoading {
                            PlaceholderPanel(
                                icon: "chart.xyaxis.line",
                                title: "No stats yet",
                                subtitle: "Start a focus session to populate this day’s summary."
                            )
                        }

                        if let error = snapshot.lastErrorDescription, !error.isEmpty {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: snapshot.date)
                    .animation(.easeOut(duration: 0.2), value: snapshot.focusScore?.score)

                    if snapshot.isLoading && snapshot.focusScore == nil {
                        PlaceholderPanel(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Loading stats",
                            subtitle: "Refreshing this day from the daemon."
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 480)
            .overlay(alignment: .topTrailing) {
                if snapshot.isLoading && snapshot.focusScore != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                }
            }
        }
    }

    private func scoreHero(
        score: CronaFocusScoreSummary,
        message: String
    ) -> some View {
        HStack(spacing: 18) {
            CompactScoreRing(score: score.score)
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 7) {
                Text(score.level.capitalized)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(cardBackground(stroke: Color.white.opacity(0.1), cornerRadius: 26))
    }

    private func compactDuration(_ seconds: Int) -> String {
        MenuBarTextFormatter.formatElapsed(seconds: seconds, format: .expanded, showsSeconds: false)
    }

    private func statsTitle(for date: String) -> String {
        let today = DailyFocusService.todayString()
        if date == today || date.isEmpty {
            return "Today’s Focus Score"
        }
        return "\(displayDate(date)) Focus Score"
    }

    private func displayDate(_ date: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"

        let renderer = DateFormatter()
        renderer.calendar = Calendar(identifier: .gregorian)
        renderer.locale = Locale.current
        renderer.timeZone = TimeZone.current
        renderer.dateFormat = "MMM d"

        guard let parsed = parser.date(from: date) else {
            return date
        }
        return renderer.string(from: parsed)
    }

    private func statsDateArrow(
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? .white : .white.opacity(0.28))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(isEnabled ? 0.08 : 0.04)))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct CompactScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 9)

            Circle()
                .trim(from: 0, to: min(1, max(0, Double(score) / 100)))
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.82), Color.yellow.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("score")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .foregroundStyle(.white)
        }
        .animation(.easeOut(duration: 0.35), value: score)
    }
}

private struct StatsMetricTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
            }

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(cardBackground(stroke: tint.opacity(0.14), cornerRadius: 20))
    }
}

private struct FocusRestBalanceView: View {
    let workedSeconds: Int
    let restSeconds: Int

    var body: some View {
        let total = max(1, workedSeconds + restSeconds)
        let focusFraction = Double(workedSeconds) / Double(total)

        VStack(spacing: 10) {
            HStack {
                Label("Focus balance", systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text("\(Int(focusFraction * 100))% focus")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(Color.pink.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.56))
                            .frame(width: geometry.size.width * focusFraction)
                    }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(cardBackground(stroke: Color.white.opacity(0.07), cornerRadius: 20))
    }
}

private struct StatsOutcomeCard: View {
    let icon: String
    let tint: Color
    let title: String
    let values: [(String, Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 4) {
                        Text("\(value.1)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text(value.0)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity)

                    if index < values.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                            .frame(height: 30)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground(stroke: tint.opacity(0.16), cornerRadius: 22))
    }
}

struct HabitsTabView: View {
    @ObservedObject var appState: CompanionAppState
    @State private var loggingHabitID: Int64?
    @State private var logMinutes = 1

    var body: some View {
        let snapshot = appState.habitsService.snapshot

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(.green)
                Text("Habits Due")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !snapshot.date.isEmpty {
                    Text(snapshot.date)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            if snapshot.isLoading && snapshot.items.isEmpty {
                PlaceholderPanel(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Loading habits",
                    subtitle: "Refreshing today’s due habits from the daemon."
                )
            } else if snapshot.items.isEmpty {
                PlaceholderPanel(
                    icon: "checkmark.circle",
                    title: "No due habits",
                    subtitle: "No due habits for this date."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(snapshot.items) { habit in
                        HabitRow(
                            habit: habit,
                            isWorking: appState.habitsService.actionInFlightHabitID == habit.id,
                            activeAction: appState.habitsService.actionInFlightHabitID == habit.id
                                ? appState.habitsService.actionInFlightStatus : nil,
                            actionsDisabled: appState.habitsService.actionInFlightHabitID != nil,
                            isLogging: loggingHabitID == habit.id,
                            logMinutes: $logMinutes,
                            onComplete: { appState.completeHabit(habit) },
                            onBeginLog: {
                                logMinutes = max(1, habit.targetMinutes ?? 1)
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    loggingHabitID = habit.id
                                }
                            },
                            onSubmitLog: {
                                appState.logHabit(habit, durationMinutes: logMinutes)
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    loggingHabitID = nil
                                }
                            },
                            onCancelLog: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    loggingHabitID = nil
                                }
                            },
                            onFail: { appState.failHabit(habit) },
                            onClear: { appState.clearHabitCompletion(habit) }
                        )
                    }
                }
            }

            if let error = snapshot.lastRefreshError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct PlaceholderPanel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .padding(20)
        .background(cardBackground(stroke: Color.white.opacity(0.08), cornerRadius: 24))
    }
}

struct EndSessionSheetView: View {
    @ObservedObject var appState: CompanionAppState
    @FocusState private var isCommitFieldFocused: Bool

    var body: some View {
        ZStack {
            SheetGlassBackground()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("End Session")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Add the commit message that will be stored with this session.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.66))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Commit Message")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ZStack(alignment: .topLeading) {
                        if appState.endSessionCommitMessage.isEmpty {
                            Text("Describe what you completed")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.28))
                                .padding(.horizontal, 19)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $appState.endSessionCommitMessage)
                            .scrollContentBackground(.hidden)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(height: 104)
                            .focused($isCommitFieldFocused)
                            .disabled(appState.isSubmittingEndSession)
                    }
                    .background(cardBackground(stroke: Color.white.opacity(0.08)))

                    if let error = appState.endSessionErrorMessage, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }

                HStack {
                    Button("Cancel") {
                        appState.cancelEndSession()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(appState.isSubmittingEndSession)

                    Spacer()

                    Button {
                        appState.confirmEndSession()
                    } label: {
                        if appState.isSubmittingEndSession {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("End Session")
                        }
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isSubmittingEndSession)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .frame(maxWidth: 384, alignment: .leading)
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(0.34), radius: 32, y: 22)
        .onAppear {
            DispatchQueue.main.async {
                isCommitFieldFocused = true
            }
        }
        .onChange(of: appState.endSessionFocusRequest) {
            DispatchQueue.main.async {
                isCommitFieldFocused = true
            }
        }
    }
}

struct MetricStripCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .foregroundStyle(.white)
                    .font(.headline)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(tint))
            }
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .font(.headline)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(cardBackground(stroke: Color.white.opacity(0.05), cornerRadius: 22))
    }
}

struct EndsAtRow: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))

            Text("Ends At")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            Text(TimerEndTimeFormatter.string(from: date))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 42)
        .background(cardBackground(stroke: Color.white.opacity(0.08), cornerRadius: 16))
    }
}

struct ReverseProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let shape = Capsule()
            let clampedProgress = max(0, min(1, progress))

            ZStack(alignment: .trailing) {
                shape
                    .fill(Color.white.opacity(0.045))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.46),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: geometry.size.width * clampedProgress)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            )
            .animation(.easeOut(duration: 0.24), value: clampedProgress)
        }
    }
}

struct FocusIssueRow: View {
    @ObservedObject var appState: CompanionAppState
    let issue: DailyFocusIssue
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(issue.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.yellow)
                }

                HStack(spacing: 12) {
                    metaLabel(
                        icon: "smallcircle.filled.circle",
                        text: issue.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    metaLabel(icon: "clock.fill", text: metaLine)
                }
            }
            Spacer()
            if isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 90)
            } else {
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 90)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(glassCapsuleBackground(emphasis: 0.18))
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .padding(16)
        .background(cardBackground(stroke: Color.white.opacity(0.08), cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
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
        return value.isEmpty ? DailyFocusService.todayString() : value
    }

    private var isWorking: Bool {
        appState.issueActionsService.actionInFlightIssueID == issue.id
    }

    private var metaLine: String {
        let worked = MenuBarTextFormatter.formatElapsed(
            seconds: issue.workedSeconds, format: .expanded, showsSeconds: false)
        if let estimate = issue.estimateMinutes, estimate > 0 {
            return "\(worked) / \(estimate)m"
        }
        return worked
    }

    private func metaLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))
    }
}

struct IssueActionEditorView: View {
    @ObservedObject var appState: CompanionAppState
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch appState.issueActionEditor {
            case let .status(issue, status):
                statusEditor(issue: issue, status: status)
            case let .dueDate(issue):
                dueDateEditor(issue: issue)
            case nil:
                EmptyView()
            }
        }
        .padding(20)
        .frame(maxWidth: 350)
        .background(PopoverDialogBackground(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 28, y: 16)
        .onAppear {
            if case .status = appState.issueActionEditor {
                DispatchQueue.main.async {
                    noteIsFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private func statusEditor(
        issue: DailyFocusIssue,
        status: CronaIssueStatus
    ) -> some View {
        editorHeader(
            title: status.title,
            subtitle: issue.title,
            systemImage: status.systemImage
        )

        TextField(
            status.notePrompt ?? "Note",
            text: $appState.issueActionNote,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .lineLimit(3...5)
        .focused($noteIsFocused)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.48))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    noteIsFocused ? Color.accentColor.opacity(0.72) : .white.opacity(0.16),
                    lineWidth: noteIsFocused ? 1.2 : 0.7
                )
        )

        editorError
        editorActions(
            submitTitle: "Change Status",
            submitDisabled: status.requiresNote
                && appState.issueActionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    @ViewBuilder
    private func dueDateEditor(issue: DailyFocusIssue) -> some View {
        editorHeader(
            title: "Choose Due Date",
            subtitle: issue.title,
            systemImage: "calendar"
        )

        DatePicker(
            "Due date",
            selection: $appState.issueActionDate,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .frame(maxWidth: .infinity)

        editorError
        editorActions(submitTitle: "Set Due Date", submitDisabled: false)
    }

    @ViewBuilder
    private var editorError: some View {
        if let error = appState.issueActionsService.lastErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func editorHeader(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.yellow)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
    }

    private func editorActions(
        submitTitle: String,
        submitDisabled: Bool
    ) -> some View {
        HStack {
            Button("Cancel") {
                appState.cancelIssueActionEditor()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(submitTitle) {
                appState.submitIssueActionEditor()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(
                submitDisabled
                    || appState.issueActionsService.actionInFlightIssueID != nil
            )
        }
    }
}

struct HabitRow: View {
    let habit: HabitRowModel
    let isWorking: Bool
    let activeAction: String?
    let actionsDisabled: Bool
    let isLogging: Bool
    @Binding var logMinutes: Int
    let onComplete: () -> Void
    let onBeginLog: () -> Void
    let onSubmitLog: () -> Void
    let onCancelLog: () -> Void
    let onFail: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: isLogging ? 10 : 0) {
            HStack(spacing: 12) {
                statusBadge

                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        metaLabel(icon: "folder.fill", text: habit.repoName)
                        metaLabel(icon: "arrow.triangle.branch", text: habit.streamName)
                        if let detailText {
                            metaLabel(icon: "clock.fill", text: detailText)
                        }
                    }
                }

                Spacer()

                if habit.supportsClearAction {
                    habitActionButton(
                        title: "Clear",
                        symbol: "arrow.uturn.backward",
                        tint: .white,
                        actionID: "clear",
                        action: onClear
                    )
                } else if !isLogging {
                    HStack(spacing: 7) {
                        habitActionButton(
                            title: "Fail",
                            symbol: "xmark",
                            tint: .red,
                            actionID: "failed",
                            action: onFail
                        )
                        habitActionButton(
                            title: usesDurationLogging ? "Log" : "Complete",
                            symbol: usesDurationLogging ? "clock.fill" : "checkmark",
                            tint: .green,
                            actionID: "completed",
                            action: usesDurationLogging ? onBeginLog : onComplete
                        )
                    }
                }
            }

            if isLogging {
                InlineHabitLogEditor(
                    value: $logMinutes,
                    onCancel: onCancelLog,
                    onSubmit: onSubmitLog
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(cardBackground(stroke: statusColor.opacity(0.2), cornerRadius: 19))
    }

    private func habitActionButton(
        title: String,
        symbol: String?,
        tint: Color,
        actionID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isWorking && activeAction == actionID {
                    ProgressView()
                        .controlSize(.small)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(actionsDisabled && !isWorking ? 0.42 : 0.9))
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(title == "Complete" || title == "Log" ? 0.16 : 0.08))
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(actionsDisabled)
    }

    private var usesDurationLogging: Bool {
        (habit.targetMinutes ?? 0) > 0
    }

    private var detailText: String? {
        if let durationMinutes = habit.durationMinutes {
            return MenuBarTextFormatter.formatMinutes(durationMinutes)
        }
        if let targetMinutes = habit.targetMinutes {
            return "target \(MenuBarTextFormatter.formatMinutes(targetMinutes))"
        }
        return nil
    }

    private var statusColor: Color {
        switch habit.status {
        case "completed":
            return .green
        case "failed":
            return .red
        default:
            return .yellow
        }
    }

    private var statusSymbolName: String {
        switch habit.status {
        case "completed":
            return "checkmark.circle.fill"
        case "failed":
            return "exclamationmark.circle.fill"
        default:
            return "circle"
        }
    }

    private var statusBadge: some View {
        Image(systemName: statusSymbolName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(statusColor)
            .frame(width: 22, height: 22)
    }

    private func metaLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))
    }
}

private struct InlineHabitLogEditor: View {
    @Binding var value: Int
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("Time logged")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))

            Spacer()

            stepButton("minus") {
                setValue(max(1, value - 5))
            }

            HStack(spacing: 3) {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .focused($isFocused)
                    .frame(width: 36)
                    .onChange(of: draft) {
                        let digits = draft.filter(\.isNumber)
                        if digits != draft {
                            draft = digits
                        } else if let parsed = Int(digits) {
                            value = max(1, parsed)
                        }
                    }
                    .onSubmit(onSubmit)
                Text("min")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .strokeBorder(Color.white.opacity(isFocused ? 0.22 : 0.08), lineWidth: 1)
            )

            stepButton("plus") {
                setValue(value + 5)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.58))
            .keyboardShortcut(.cancelAction)

            Button(action: onSubmit) {
                Image(systemName: "checkmark")
                    .fontWeight(.bold)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.green.opacity(0.2)))
            }
            .buttonStyle(GlassPressButtonStyle())
            .foregroundStyle(.white)
            .keyboardShortcut(.defaultAction)
            .help("Log \(value) minutes")
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Divider()
                .overlay(Color.white.opacity(0.07))
        }
        .onAppear {
            draft = "\(value)"
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: value) {
            if Int(draft) != value {
                draft = "\(value)"
            }
        }
    }

    private func setValue(_ newValue: Int) {
        value = max(1, newValue)
        draft = "\(value)"
    }

    private func stepButton(
        _ symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .frame(width: 27, height: 27)
                .background(Circle().fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(GlassPressButtonStyle())
        .foregroundStyle(.white.opacity(0.8))
    }
}

@MainActor
final class FocusStartConfigEditor: ObservableObject {
    @Published var state: FocusStartConfigState

    init(initialState: FocusStartConfigState) {
        state = initialState
    }

    var focusDisplay: String {
        displayText(for: state.focusChoice, customMinutes: state.customFocusMinutes)
    }

    var breakDisplay: String {
        displayText(for: state.breakChoice, customMinutes: state.customBreakMinutes)
    }

    var longBreakDisplay: String {
        displayText(for: state.longBreakChoice, customMinutes: state.customLongBreakMinutes)
    }

    var countdownDisplay: String {
        displayText(for: state.countdownChoice, customMinutes: state.customCountdownMinutes)
    }

    func handleModeChange(_ mode: FocusSessionMode) {
        state.mode = mode
    }

    func selectFocus(_ choice: FocusPresetChoice) {
        state.focusChoice = choice
    }

    func selectBreak(_ choice: FocusPresetChoice) {
        state.breakChoice = choice
        if choice == .noBreak {
            state.longBreakChoice = .noBreak
            state.pomodoroCycles = 1
            state.pomodoroCyclesBeforeLongBreak = 0
        } else {
            if state.longBreakChoice == .noBreak {
                state.pomodoroCyclesBeforeLongBreak = max(4, state.pomodoroCyclesBeforeLongBreak)
            }
            state.pomodoroCycles = max(1, state.pomodoroCycles)
        }
    }

    func selectLongBreak(_ choice: FocusPresetChoice) {
        state.longBreakChoice = choice
        state.pomodoroCyclesBeforeLongBreak =
            choice == .noBreak ? 0 : max(1, state.pomodoroCyclesBeforeLongBreak)
    }

    func selectCountdown(_ choice: FocusPresetChoice) {
        state.countdownChoice = choice
    }

    private func displayText(for choice: FocusPresetChoice, customMinutes: Int) -> String {
        switch choice {
        case .custom:
            return "\(max(0, customMinutes))m"
        default:
            return choice.title
        }
    }
}

private enum FocusConfigControl {
    case focus
    case shortBreak
    case longBreak
    case cycles
    case longBreakAfter
    case countdown
}

struct ExpandablePresetRow: View {
    let icon: String
    let tint: Color
    let title: String
    let displayValue: String
    let choices: [FocusPresetChoice]
    let selection: FocusPresetChoice
    let isExpanded: Bool
    @Binding var customValue: Int
    let allowsZero: Bool
    let onToggle: () -> Void
    let onSelect: (FocusPresetChoice) -> Void

    var body: some View {
        VStack(spacing: 0) {
            configDisclosureHeader(
                icon: icon,
                tint: tint,
                title: title,
                displayValue: displayValue,
                isExpanded: isExpanded,
                action: onToggle
            )

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 14)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(choices) { choice in
                        configOptionButton(
                            title: choice.title,
                            isSelected: choice == selection
                        ) {
                            onSelect(choice)
                        }
                    }
                }
                .padding(12)

                if selection == .custom {
                    InlineMinutesEditor(value: $customValue, allowsZero: allowsZero)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(cardBackground(
            stroke: Color.white.opacity(isExpanded ? 0.14 : 0.05),
            cornerRadius: 22
        ))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}

struct ExpandableNumberRow: View {
    let icon: String
    let tint: Color
    let title: String
    let displayValue: String
    let values: [Int]
    let selection: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            configDisclosureHeader(
                icon: icon,
                tint: tint,
                title: title,
                displayValue: displayValue,
                isExpanded: isExpanded,
                action: onToggle
            )

            if isExpanded {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 14)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 48), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(values, id: \.self) { value in
                        configOptionButton(
                            title: "\(value)",
                            isSelected: value == selection
                        ) {
                            onSelect(value)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(cardBackground(
            stroke: Color.white.opacity(isExpanded ? 0.14 : 0.05),
            cornerRadius: 22
        ))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}

private struct InlineMinutesEditor: View {
    @Binding var value: Int
    let allowsZero: Bool
    @FocusState private var isFocused: Bool
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 12) {
            Text("Custom")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            Spacer()

            minuteStepButton(systemName: "minus") {
                setValue(max(minimum, value - 5))
            }

            HStack(spacing: 4) {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.headline.monospacedDigit())
                    .focused($isFocused)
                    .frame(width: 42)
                    .accessibilityLabel("Custom duration in minutes")
                    .onChange(of: draft) {
                        let digits = draft.filter(\.isNumber)
                        if digits != draft {
                            draft = digits
                            return
                        }
                        if let parsed = Int(digits) {
                            value = max(minimum, parsed)
                        }
                    }
                    .onSubmit {
                        setValue(max(minimum, Int(draft) ?? minimum))
                    }
                Text("min")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .strokeBorder(
                        Color.white.opacity(isFocused ? 0.24 : 0.08),
                        lineWidth: 1
                    )
            )

            minuteStepButton(systemName: "plus") {
                setValue(value + 5)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .onAppear {
            draft = "\(value)"
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: value) {
            if Int(draft) != value {
                draft = "\(value)"
            }
        }
    }

    private var minimum: Int { allowsZero ? 0 : 1 }

    private func setValue(_ newValue: Int) {
        value = max(minimum, newValue)
        draft = "\(value)"
    }

    private func minuteStepButton(
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(systemName == "plus" ? "Add five minutes" : "Remove five minutes")
    }
}

private func configDisclosureHeader(
    icon: String,
    tint: Color,
    title: String,
    displayValue: String,
    isExpanded: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint))

            Text(title)
                .foregroundStyle(.white)
                .font(.headline)

            Spacer()

            Text(displayValue)
                .foregroundStyle(.white)
                .font(.headline.monospacedDigit())

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.52))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
    .buttonStyle(.plain)
}

private func configOptionButton(
    title: String,
    isSelected: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.72))
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.14 : 0.05))
                .strokeBorder(Color.white.opacity(isSelected ? 0.16 : 0.05), lineWidth: 1)
        )
    }
    .buttonStyle(GlassPressButtonStyle())
}

func actionPill(
    _ title: String,
    fill: Color,
    shortcut: KeyboardShortcut? = nil,
    shortcutLabel: String? = nil,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 7) {
            Text(title)
            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            glassCapsuleBackground(emphasis: 0.16)
        )
    }
    .buttonStyle(GlassPressButtonStyle())
    .modifier(OptionalKeyboardShortcut(shortcut: shortcut))
}

private struct OptionalKeyboardShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}

func cardBackground(stroke: Color, cornerRadius: CGFloat = 20) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    return shape
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.085),
                    Color.black.opacity(0.2),
                    Color.white.opacity(0.03),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.02),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            shape
                .strokeBorder(stroke, lineWidth: 1)
        )
        .overlay(
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
}

struct PopoverGlassBackground: View {
    var body: some View {
        let shellShape = RoundedRectangle(cornerRadius: 36, style: .continuous)

        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, emphasized: true)
                .clipShape(shellShape)

            shellShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.16),
                            Color.white.opacity(0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            shellShape
                .fill(Color.black.opacity(0.14))

            shellShape
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.9)

            shellShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.03),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 16)
    }
}

private struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private func glassCapsuleBackground(emphasis: Double = 0.12) -> some View {
    Capsule()
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(emphasis),
                    Color.white.opacity(max(0.04, emphasis * 0.45)),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)
        )
}

private struct SheetGlassBackground: View {
    var body: some View {
        PopoverDialogBackground(cornerRadius: 28)
    }
}

private struct PopoverModalScrim: View {
    let onDismiss: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 36, style: .continuous)
            .fill(.black.opacity(0.56))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.white.opacity(0.015))
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }
}

private struct PopoverDialogBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            VisualEffectView(
                material: .popover,
                blendingMode: .withinWindow,
                emphasized: true
            )

            shape.fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.19, green: 0.19, blue: 0.20).opacity(0.96),
                        Color(red: 0.105, green: 0.105, blue: 0.115).opacity(0.97),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)

            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.035),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.6
            )
        }
        .clipShape(shape)
    }
}
