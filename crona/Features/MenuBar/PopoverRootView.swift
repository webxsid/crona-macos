import Combine
import SwiftUI

struct PopoverRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                header

                switch appState.selectedPopoverTab {
                case .now:
                    NowTabView(appState: appState)
                case .habits:
                    HabitsTabView(appState: appState)
                case .stats:
                    StatsTabView(appState: appState)
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
            .background(
                PopoverGlassBackground()
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .opacity(appState.isEndSessionSheetPresented ? 0.55 : 1)
            .blur(radius: appState.isEndSessionSheetPresented ? 2.5 : 0)
            .scaleEffect(appState.isEndSessionSheetPresented ? 0.985 : 1)
            .allowsHitTesting(!appState.isEndSessionSheetPresented)

            if appState.isEndSessionSheetPresented {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(.white.opacity(0.02))
                    )
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !appState.isSubmittingEndSession {
                            appState.cancelEndSession()
                        }
                    }

                VStack {
                    Spacer(minLength: 0)
                    EndSessionSheetView(appState: appState)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                        .zIndex(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 420)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: appState.isEndSessionSheetPresented)
    }

    private var header: some View {

        SegmentedControl(
            selection: $appState.selectedPopoverTab,
            title: \.title
        )
        .frame(width: 210)
        .onChange(of: appState.selectedPopoverTab) { _, newTab in
            appState.setSelectedPopoverTab(newTab)
        }

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
                    .frame(height: 10)
                    .padding(.horizontal, 6)
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
                    actionPill("Pause", fill: Color.white.opacity(0.18)) { appState.pauseTimer() }
                }
                if presentation.canResume {
                    actionPill("Resume", fill: Color.white.opacity(0.18)) { appState.resumeTimer() }
                }
                if presentation.canEnd {
                    actionPill("End", fill: Color.white.opacity(0.08)) { appState.endTimer() }
                }
            }

            if presentation.showsQuickExtend {
                HStack(spacing: 10) {
                    actionPill("+1m", fill: Color.white.opacity(0.08)) {
                        appState.extendTimer(by: 60)
                    }
                    actionPill("+5m", fill: Color.white.opacity(0.08)) {
                        appState.extendTimer(by: 300)
                    }
                    actionPill("+15m", fill: Color.white.opacity(0.08)) {
                        appState.extendTimer(by: 900)
                    }
                }
            }

            VStack(spacing: 10) {
                MetricStripCard(
                    icon: "bolt.fill", tint: .yellow, title: "Current focus",
                    value: shortDuration(presentation.currentFocusSeconds))
                if let upcomingBreak = presentation.upcomingBreakSeconds {
                    MetricStripCard(
                        icon: "cup.and.saucer.fill", tint: .pink, title: "Upcoming break",
                        value: shortDuration(upcomingBreak))
                }
                MetricStripCard(
                    icon: appState.daemonConnection.connectionState == .connected
                        ? "wifi" : "wifi.slash",
                    tint: .gray,
                    title: "Connection",
                    value: connectionLabel(appState.daemonConnection.connectionState)
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

    private func connectionLabel(_ state: CompanionConnectionState) -> String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .incompatible: return "Incompatible"
        case .error: return "Error"
        case .idle: return "Idle"
        }
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
                VStack(spacing: 10) {
                    ForEach(appState.dailyFocusService.snapshot.issues) { issue in
                        FocusIssueRow(issue: issue) {
                            appState.selectFocusIssue(issue)
                        }
                    }
                }
            }
        }
    }
}

struct FocusStartConfigView: View {
    @ObservedObject var appState: CompanionAppState
    let issue: DailyFocusIssue
    @StateObject private var editor: FocusStartConfigEditor

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
                    ConfigMenuRow(
                        icon: "bolt.fill",
                        tint: .yellow,
                        title: "Focus",
                        displayValue: editor.focusDisplay,
                        choices: FocusStartConfigState.focusChoices,
                        selection: editor.state.focusChoice,
                        onSelect: editor.selectFocus
                    )
                    ConfigMenuRow(
                        icon: "cup.and.saucer.fill",
                        tint: .pink,
                        title: "Short break",
                        displayValue: editor.breakDisplay,
                        choices: FocusStartConfigState.shortBreakChoices,
                        selection: editor.state.breakChoice,
                        onSelect: editor.selectBreak
                    )
                    if editor.state.showsLongBreakControls {
                        ConfigMenuRow(
                            icon: "moon.zzz.fill",
                            tint: .purple,
                            title: "Long break",
                            displayValue: editor.longBreakDisplay,
                            choices: FocusStartConfigState.longBreakChoices,
                            selection: editor.state.longBreakChoice,
                            onSelect: editor.selectLongBreak
                        )
                    }
                    if editor.state.showsCycleControls {
                        NumberMenuRow(
                            icon: "repeat.circle.fill",
                            tint: .orange,
                            title: "Cycles",
                            displayValue: "\(editor.state.effectivePomodoroCycles)",
                            values: Array(1...12),
                            selection: editor.state.pomodoroCycles,
                            onSelect: { editor.state.pomodoroCycles = $0 }
                        )
                    }
                    if editor.state.showsLongBreakAfterControls {
                        NumberMenuRow(
                            icon: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill",
                            tint: .mint,
                            title: "Long break after",
                            displayValue: "\(editor.state.effectiveCyclesBeforeLongBreak)",
                            values: Array(1...12),
                            selection: editor.state.pomodoroCyclesBeforeLongBreak,
                            onSelect: { editor.state.pomodoroCyclesBeforeLongBreak = $0 }
                        )
                    }
                case .timer:
                    ConfigMenuRow(
                        icon: "timer",
                        tint: .orange,
                        title: "Countdown",
                        displayValue: editor.countdownDisplay,
                        choices: FocusStartConfigState.countdownChoices,
                        selection: editor.state.countdownChoice,
                        onSelect: editor.selectCountdown
                    )
                }
            }

            VStack(spacing: 10) {
                switch editor.state.mode {
                case .stopwatch:
                    EmptyView()
                case .pomodoro:
                    if editor.state.showsCustomFocusField {
                        CustomMinutesField(
                            title: "Custom focus", value: $editor.state.customFocusMinutes)
                    }
                    if editor.state.showsCustomBreakField {
                        CustomMinutesField(
                            title: "Custom short break", value: $editor.state.customBreakMinutes,
                            allowsZero: true)
                    }
                    if editor.state.showsCustomLongBreakField {
                        CustomMinutesField(
                            title: "Custom long break", value: $editor.state.customLongBreakMinutes,
                            allowsZero: true)
                    }
                case .timer:
                    if editor.state.showsCustomCountdownField {
                        CustomMinutesField(
                            title: "Custom duration", value: $editor.state.customCountdownMinutes)
                    }
                }
            }
            .tint(.white)
            .foregroundStyle(.white)

            HStack {
                Spacer()
                actionPill("Start Focus", fill: Color.white.opacity(0.18)) {
                    appState.startSelectedFocusSession(using: editor.state)
                }
                Spacer()
            }
        }
    }
}

struct StatsTabView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        let snapshot = appState.popoverStatsService.snapshot

        VStack(spacing: 14) {
            if let score = snapshot.focusScore {
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
                            .background(Capsule().fill(Color.white.opacity(0.06)))

                        statsDateArrow(
                            systemName: "chevron.right",
                            isEnabled: appState.popoverStatsService.canShowNextDay()
                        ) {
                            appState.popoverStatsService.showNextDay()
                        }
                    }

                    ScoreArcView(score: score.score)
                        .frame(width: 190, height: 126)

                    Text(snapshot.scoreMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                        .background(cardBackground(stroke: Color.white.opacity(0.08)))
                }
            } else {
                PlaceholderPanel(
                    icon: "chart.xyaxis.line",
                    title: "No stats yet",
                    subtitle: "Start a focus session to populate today’s summary."
                )
            }

            if let metrics = snapshot.todayMetrics, let score = snapshot.focusScore {
                StatsCard(
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    title: "Focus Stats",
                    rows: [
                        ("Total focus time", compactDuration(metrics.workedSeconds)),
                        ("Sessions", "\(metrics.sessionCount)"),
                        ("Target", compactDuration(score.targetWorkedSeconds)),
                    ]
                )

                StatsCard(
                    icon: "cup.and.saucer.fill",
                    iconColor: .pink,
                    title: "Break Stats",
                    rows: [
                        ("Total break time", compactDuration(metrics.restSeconds)),
                        ("Score level", score.level.capitalized),
                        (
                            "Worked / Rest",
                            ratioText(worked: metrics.workedSeconds, rest: metrics.restSeconds)
                        ),
                    ]
                )

                StatsCard(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "Issue Stats",
                    rows: [
                        ("Completed", "\(metrics.completedIssues)"),
                        ("Abandoned", "\(metrics.abandonedIssues)"),
                        ("Planned today", "\(metrics.totalIssues)"),
                    ]
                )
            }
        }
    }

    private func compactDuration(_ seconds: Int) -> String {
        MenuBarTextFormatter.formatElapsed(seconds: seconds, format: .expanded, showsSeconds: false)
    }

    private func ratioText(worked: Int, rest: Int) -> String {
        guard worked > 0 else { return "0%" }
        let ratio = Int((Double(rest) / Double(worked)) * 100)
        return "\(ratio)%"
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

struct HabitsTabView: View {
    @ObservedObject var appState: CompanionAppState

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
                        HabitRow(habit: habit) {
                            if habit.supportsClearAction {
                                appState.clearHabitCompletion(habit)
                            } else {
                                appState.completeHabit(habit)
                            }
                        }
                    }
                }
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
        .padding(18)
        .background(cardBackground(stroke: Color.white.opacity(0.08)))
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
                    .keyboardShortcut(.defaultAction)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground(stroke: Color.clear))
    }
}

struct StatsCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(iconColor))
                }
                Spacer()
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text(row.1)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(16)
        .background(cardBackground(stroke: iconColor.opacity(0.25)))
    }
}

struct ScoreArcView: View {
    let score: Int

    var body: some View {
        ZStack {
            ArcTrack(color: Color.white.opacity(0.12), start: 0.16, end: 0.84, lineWidth: 12)
            ArcTrack(color: .yellow, start: 0.16, end: 0.84, lineWidth: 10)
            ArcTrack(
                color: .pink, start: 0.24, end: max(0.24, 0.24 + (0.44 * CGFloat(score) / 100.0)),
                lineWidth: 10)

            Text("\(score)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: 18)
        }
    }
}

private struct ArcTrack: View {
    let color: Color
    let start: CGFloat
    let end: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let rect = geometry.frame(in: .local)
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.maxY),
                    radius: min(rect.width / 2, rect.height),
                    startAngle: .degrees(Double(180 * (1 + start))),
                    endAngle: .degrees(Double(180 * (1 + end))),
                    clockwise: false
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

struct ReverseProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.pink, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * max(0, min(1, progress)))
                    .animation(.linear(duration: 0.2), value: progress)
            }
        }
    }
}

struct FocusIssueRow: View {
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
            Button(action: onStart) {
                Label("Start", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(cardBackground(stroke: Color.white.opacity(0.08)))
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

struct HabitRow: View {
    let habit: HabitRowModel
    let action: () -> Void

    var body: some View {
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

            Button(action: action) {
                Label(actionTitle, systemImage: actionSymbolName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(cardBackground(stroke: statusColor.opacity(0.28)))
    }

    private var actionTitle: String {
        habit.supportsClearAction ? "Clear" : "Complete"
    }

    private var actionSymbolName: String {
        habit.supportsClearAction ? "arrow.uturn.backward" : "checkmark"
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

struct ConfigMenuRow: View {
    let icon: String
    let tint: Color
    let title: String
    let displayValue: String
    let choices: [FocusPresetChoice]
    let selection: FocusPresetChoice
    let onSelect: (FocusPresetChoice) -> Void

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
            Menu {
                ForEach(choices) { choice in
                    Button {
                        onSelect(choice)
                    } label: {
                        if choice == selection {
                            Label(choice.title, systemImage: "checkmark")
                        } else {
                            Text(choice.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(displayValue)
                        .foregroundStyle(.white)
                        .font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground(stroke: Color.clear))
    }
}

struct NumberMenuRow: View {
    let icon: String
    let tint: Color
    let title: String
    let displayValue: String
    let values: [Int]
    let selection: Int
    let onSelect: (Int) -> Void

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
            Menu {
                ForEach(values, id: \.self) { value in
                    Button {
                        onSelect(value)
                    } label: {
                        if value == selection {
                            Label("\(value)", systemImage: "checkmark")
                        } else {
                            Text("\(value)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(displayValue)
                        .foregroundStyle(.white)
                        .font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground(stroke: Color.clear))
    }
}

struct CustomMinutesField: View {
    let title: String
    @Binding var value: Int
    var allowsZero = false

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            TextField(
                "Minutes",
                value: Binding(
                    get: { value },
                    set: { value = max(allowsZero ? 0 : 1, $0) }
                ),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 84)
        }
        .padding(.horizontal, 12)
    }
}

private func actionPill(_ title: String, fill: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(fill)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }
    .buttonStyle(.plain)
}

private func cardBackground(stroke: Color) -> some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.white.opacity(0.045),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
}

private struct PopoverGlassBackground: View {
    var body: some View {
        let shellShape = RoundedRectangle(cornerRadius: 32, style: .continuous)

        shellShape
            .fill(Color.clear)
            .overlay(
                shellShape
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 22, y: 14)
    }
}

private struct SheetGlassBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        shape
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.17, green: 0.17, blue: 0.18).opacity(0.96),
                        Color(red: 0.13, green: 0.13, blue: 0.14).opacity(0.94),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                shape
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.03),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}
