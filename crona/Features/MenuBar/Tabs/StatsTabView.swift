import AppKit
import SwiftUI

struct StatsTabView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var statsService: PopoverStatsService
    @ObservedObject private var systemGlass = SystemGlassSettings.shared
    @Namespace private var calendarTransition

    init(appState: CompanionAppState) {
        self.appState = appState
        self._statsService = ObservedObject(wrappedValue: appState.popoverStatsService)
    }

    var body: some View {
        let snapshot = statsService.snapshot

        Group {
            if appState.isStatsCalendarPresented {
                statsCalendarContent(snapshot: snapshot)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 1.04))
                        ))
            } else {
                VStack(spacing: StatsLayout.sectionSpacing) {
                    ZStack {
                        HStack(spacing: 8) {
                            Button {
                                appState.popoverStatsService.showPreviousDay()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)

                            Text(statsTitle(for: snapshot.date))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PopupVisualTheme.primaryText)
                                .lineLimit(1)

                            Button {
                                appState.popoverStatsService.showNextDay()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .disabled(!appState.popoverStatsService.canShowNextDay())
                        }
                        .frame(height: 22)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .modifier(StatsDatePillSurfaceModifier())
                        .frame(height: 32)

                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        if snapshot.date != statsTodayDate {
                            Button {
                                appState.popoverStatsService.showToday()
                            } label: {
                                Image(systemName: "calendar")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.78))
                            .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.08)))
                            .help("Return to today")
                            .accessibilityLabel("Return to today")
                            .padding(.trailing, 6)
                        }
                    }
                    statsSummaryContent(snapshot: snapshot)
                }
            }
        }
        .animation(statsAnimation, value: appState.isStatsCalendarPresented)
    }

    private func statsSummaryContent(snapshot: PopoverStatsSnapshot) -> some View {
        ViewThatFits(in: .vertical) {
            statsSummaryBody(snapshot: snapshot)

            ScrollView(.vertical) {
                statsSummaryBody(snapshot: snapshot)
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 480)
        }
        .overlay(alignment: .topTrailing) {
            if snapshot.isLoading && snapshot.focusScore != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(6)
            }
        }
    }

    private func statsSummaryBody(snapshot: PopoverStatsSnapshot) -> some View {
        ZStack {
            VStack(spacing: StatsLayout.sectionSpacing) {
                if appState.coreSettingsService.isHistoricalAwayDate(snapshot.date) {
                    HistoricalAwayStatsView(date: snapshot.date)
                } else if let score = snapshot.focusScore, let metrics = snapshot.todayMetrics {
                    scoreHero(score: score, message: snapshot.scoreMessage)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))

                    statsDivider

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: StatsLayout.gridSpacing),
                            GridItem(.flexible(), spacing: StatsLayout.gridSpacing),
                        ],
                        spacing: StatsLayout.gridSpacing
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

                    statsDivider

                    FocusRestBalanceView(
                        workedSeconds: metrics.workedSeconds,
                        restSeconds: metrics.restSeconds
                    )

                    statsDivider

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

                    statsDivider

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
    }

    private func statsCalendarContent(snapshot: PopoverStatsSnapshot) -> some View {
        statsCalendarBody(snapshot: snapshot)
    }

    private func statsCalendarBody(snapshot: PopoverStatsSnapshot) -> some View {
        let anchoredSnapshot = snapshotForCalendar(snapshot)
        return VStack(alignment: .leading, spacing: StatsLayout.sectionSpacing) {
            calendarMonthGrid(
                snapshot: anchoredSnapshot,
                monthDate: statsService.calendarMonthDate ?? anchoredSnapshot.date
            )

            if let error = anchoredSnapshot.lastErrorDescription, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 4)
            }
        }
    }

    private var statsDivider: some View {
        Divider()
            .padding(.horizontal, 4)
            .overlay(PopupVisualTheme.divider.opacity(0.7))
    }

    private func calendarSelectionCard(snapshot: PopoverStatsSnapshot) -> some View {
        let selectedSnapshot =
            appState.popoverStatsService.cachedSnapshot(for: snapshot.date) ?? snapshot

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                CompactScoreRing(score: selectedSnapshot.focusScore?.score ?? 0)
                    .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 7) {
                    Text(displayDate(snapshot.date))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PopupVisualTheme.primaryText)
                        .lineLimit(1)

                    if let score = selectedSnapshot.focusScore {
                        Text(PopoverStatsService.title(for: score.reason))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))

                        Text(selectedSnapshot.scoreMessage)
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    } else if selectedSnapshot.isLoading {
                        Text("Loading day summary")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
                    } else {
                        Text("No summary available for this day.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(StatsLayout.cardPadding)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 22))
    }

    private func calendarMonthGrid(snapshot: PopoverStatsSnapshot, monthDate: String) -> some View {
        let selectedDate = CronaCalendarDate.date(from: snapshot.date) ?? Date()
        let displayedMonthDate = CronaCalendarDate.date(from: monthDate) ?? selectedDate
        let monthTitle = calendarMonthTitle(for: displayedMonthDate)
        let days = calendarGridDays(containing: displayedMonthDate)
        let todayString =
            appState.daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString()
            : appState.daemonConnection.currentDate
        let visibleDates = PopoverStatsService.monthRange(for: monthDate, through: todayString)

        return VStack(alignment: .leading, spacing: StatsLayout.gridSpacing) {
            HStack(spacing: 8) {
                Button {
                    appState.popoverStatsService.showPreviousCalendarMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .lineLimit(1)

                Button {
                    appState.popoverStatsService.showNextCalendarMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!appState.popoverStatsService.canShowNextCalendarMonth())
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .modifier(StatsDatePillSurfaceModifier())
            .frame(height: 32)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7),
                spacing: 6
            ) {
                ForEach(calendarWeekdaySymbols(), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    calendarDayCell(
                        date: date,
                        selectedDate: snapshot.date,
                        displayedMonth: monthDate
                    )
                }
            }
        }
        .padding(StatsLayout.cardPadding)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 22))
        .task(id: visibleDates) {
            let scoreDates = visibleDates.filter {
                !appState.coreSettingsService.isHistoricalAwayDate($0)
            }
            await appState.popoverStatsService.prefetchCalendarDates(scoreDates)
        }
    }

    private func snapshotForCalendar(_ snapshot: PopoverStatsSnapshot) -> PopoverStatsSnapshot {
        guard let anchor = statsService.calendarAnchorDate, anchor != snapshot.date else {
            return snapshot
        }
        return statsService.cachedSnapshot(for: anchor)
            ?? PopoverStatsSnapshot(date: anchor, isLoading: true)
    }

    private func calendarDayCell(
        date: Date?,
        selectedDate: String,
        displayedMonth: String
    ) -> some View {
        let calendar = calendarForLayout()
        let todayString =
            appState.daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString()
            : appState.daemonConnection.currentDate
        let today = CronaCalendarDate.date(from: todayString) ?? Date()
        let dateString = date.map(calendarDateString(for:))
        let isInDisplayedMonth = dateString?.hasPrefix(String(displayedMonth.prefix(7))) == true
        let selected = isInDisplayedMonth && dateString == selectedDate
        let isToday = date.map { calendar.isDate($0, inSameDayAs: today) } ?? false
        let isFuture =
            date.map { calendar.compare($0, to: today, toGranularity: .day) == .orderedDescending }
            ?? false
        let cached = isInDisplayedMonth ? date.flatMap {
            appState.popoverStatsService.cachedSnapshot(for: calendarDateString(for: $0))
        } : nil
        let score = cached?.focusScore?.score
        let isAway =
            date.map {
                appState.coreSettingsService.isHistoricalAwayDate(calendarDateString(for: $0))
            } ?? false
        let tileFill: AnyShapeStyle
        if isFuture {
            tileFill = AnyShapeStyle(PopupVisualTheme.primaryText.opacity(0.025))
        } else if isAway {
            tileFill = AnyShapeStyle(Color.green.opacity(0.055))
        } else if let score {
            tileFill = AnyShapeStyle(
                LinearGradient(
                    colors: calendarHeatMapColors(score),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            tileFill = AnyShapeStyle(PopupVisualTheme.primaryText.opacity(0.05))
        }

        return Button {
            guard let date else { return }
            withAnimation(statsAnimation) {
                appState.popoverStatsService.selectDate(
                    calendarDateString(for: date),
                    isHistoricalAway: isAway
                )
                appState.isStatsCalendarPresented = false
                appState.popoverStatsService.endCalendar()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 2) {
                    if let date {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                    Spacer(minLength: 0)
                    if isAway {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
                .foregroundStyle(
                    isAway
                        ? Color.green.opacity(0.9)
                        : selected
                            ? PopupVisualTheme.selectedControlText : PopupVisualTheme.primaryText
                )

                Spacer(minLength: 0)

                if let score {
                    let scoreRing = ZStack {
                        ZStack {
                            Circle()
                                .trim(from: 0.15, to: 0.85)
                                .stroke(PopupVisualTheme.primaryText.opacity(0.12), lineWidth: 3.5)
                            Circle()
                                .trim(
                                    from: 0.15, to: 0.15 + 0.7 * min(1, max(0, Double(score) / 100))
                                )
                                .stroke(
                                    LinearGradient(
                                        colors: calendarScoreColors(score),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                                )
                        }
                        .rotationEffect(.degrees(180))

                        Text("\(score)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(
                                selected
                                    ? PopupVisualTheme.selectedControlText
                                    : PopupVisualTheme.primaryText
                            )
                    }
                    .frame(width: 25, height: 22)
                    .frame(maxWidth: .infinity)

                    if selected {
                        scoreRing
                            .matchedGeometryEffect(id: "stats-score-ring", in: calendarTransition)
                    } else {
                        scoreRing
                    }
                } else if isAway {
                    Text("Away")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green.opacity(0.9))
                        .frame(maxWidth: .infinity)
                } else if cached == nil && !isFuture && date != nil {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("—")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tileFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isToday
                                    ? PopupVisualTheme.highlightedBorder
                                    : PopupVisualTheme.primaryText.opacity(isFuture ? 0.05 : 0.08),
                                lineWidth: systemGlass.increaseContrast ? 2 : (isToday ? 1.3 : 1)
                            )
                    }
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PopupVisualTheme.selectedControlBackground.opacity(0.38))
                }
            }
            .opacity(isInDisplayedMonth ? (isFuture ? 0.35 : 1) : 0.28)
        }
        .buttonStyle(.plain)
        .disabled(date == nil || !isInDisplayedMonth || isFuture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            date.map {
                CalendarDayAccessibility.label(
                    date: calendarDateString(for: $0),
                    isAway: isAway,
                    isToday: isToday,
                    isSelected: selected,
                    score: score
                )
            } ?? "Empty calendar day"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private struct StatsDatePillSurfaceModifier: ViewModifier {
        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content
                    .background(Capsule().fill(.regularMaterial))
                    .overlay {
                        Capsule()
                            .strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.7)
                    }
            }
        }
    }

    private struct HistoricalAwayStatsView: View {
        let date: String

        var body: some View {
            VStack(spacing: StatsLayout.sectionSpacing) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.green.opacity(0.82))
                Text("Away Mode")
                    .font(.title3.weight(.bold))
                Text("You chose to rest and recover on \(displayDate).")
                    .font(.subheadline)
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 16)
            .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 24))
        }

        private var displayDate: String {
            CronaCalendarDate.localizedString(from: date) ?? date
        }
    }

    private var statsAnimation: Animation? {
        systemGlass.reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    private func calendarGridDays(containing date: Date) -> [Date?] {
        let calendar = calendarForLayout()
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
            let dayRange = calendar.range(of: .day, in: .month, for: date)
        else {
            return []
        }

        let firstOfMonth = monthInterval.start
        let leading =
            (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)

        for day in dayRange {
            days.append(calendar.date(bySetting: .day, value: day, of: firstOfMonth))
        }

        while days.count.isMultiple(of: 7) == false {
            days.append(nil)
        }

        return days
    }

    private func calendarWeekdaySymbols() -> [String] {
        let calendar = calendarForLayout()
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func calendarMonthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendarForLayout()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func calendarForLayout() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    private func calendarDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendarForLayout()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func calendarScoreColors(_ score: Int) -> [Color] {
        switch score {
        case 80...:
            return [.mint, .yellow]
        case 50..<80:
            return [.yellow, .orange]
        default:
            return [.orange, .pink]
        }
    }

    private func calendarHeatMapColors(_ score: Int) -> [Color] {
        calendarScoreColors(score).map { $0.opacity(0.12) }
    }

    private func scoreHero(
        score: CronaFocusScoreSummary,
        message: String
    ) -> some View {
        HStack(spacing: 12) {
            CompactScoreRing(score: score.score)
                .frame(width: StatsLayout.heroRingSize, height: StatsLayout.heroRingSize)
                .matchedGeometryEffect(id: "stats-score-ring", in: calendarTransition)

            VStack(alignment: .leading, spacing: 5) {
                Text(PopoverStatsService.title(for: score.reason))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .contentTransition(.numericText())

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(StatsLayout.cardPadding)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 26))
    }

    private func compactDuration(_ seconds: Int) -> String {
        MenuBarTextFormatter.formatCompactDuration(seconds: seconds)
    }

    private func statsTitle(for date: String) -> String {
        let today =
            appState.daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString()
            : appState.daemonConnection.currentDate
        let resolvedDate = date.isEmpty ? today : date
        let semanticDate: String
        if resolvedDate == today {
            semanticDate = "Today"
        } else if resolvedDate == CronaCalendarDate.adding(days: -1, to: today) {
            semanticDate = "Yesterday"
        } else if resolvedDate == CronaCalendarDate.adding(days: 1, to: today) {
            semanticDate = "Tomorrow"
        } else {
            semanticDate = formattedPopoverDate(resolvedDate, appState: appState)
        }
        return "\(semanticDate)'s Focus Score"
    }

    private var statsTodayDate: String {
        appState.daemonConnection.currentDate.isEmpty
            ? DailyFocusService.todayString()
            : appState.daemonConnection.currentDate
    }

    private func displayDate(_ date: String) -> String {
        formattedPopoverDate(date, appState: appState)
    }

    private func statsDateArrow(
        systemName: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(
                    isEnabled
                        ? PopupVisualTheme.primaryText
                        : PopupVisualTheme.primaryText.opacity(0.28)
                )
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(PopupVisualTheme.primaryText.opacity(isEnabled ? 0.06 : 0.02))
                }
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
                .stroke(PopupVisualTheme.primaryText.opacity(0.08), lineWidth: 9)

            Circle()
                .trim(from: 0, to: min(1, max(0, Double(score) / 100)))
                .stroke(
                    LinearGradient(
                        colors: [
                            PopupVisualTheme.primaryText.opacity(0.82), Color.yellow.opacity(0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("score")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.48))
            }
            .foregroundStyle(PopupVisualTheme.primaryText)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.58))
                Spacer()
            }

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(PopupVisualTheme.primaryText)
                .contentTransition(.numericText())
        }
        .padding(StatsLayout.tilePadding)
        .frame(maxWidth: .infinity, minHeight: StatsLayout.tileHeight, alignment: .leading)
        .background(subtleCardBackground(stroke: tint.opacity(0.14), cornerRadius: 16))
    }
}

private struct FocusRestBalanceView: View {
    let workedSeconds: Int
    let restSeconds: Int

    var body: some View {
        let total = max(1, workedSeconds + restSeconds)
        let focusFraction = Double(workedSeconds) / Double(total)

        VStack(spacing: 7) {
            HStack {
                Label("Focus balance", systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
                Spacer()
                Text("\(Int(focusFraction * 100))% focus")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PopupVisualTheme.primaryText)
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(Color.pink.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(PopupVisualTheme.primaryText.opacity(0.56))
                            .frame(width: geometry.size.width * focusFraction)
                    }
            }
            .frame(height: 6)
        }
        .padding(StatsLayout.cardPadding)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 16))
    }
}

private struct StatsOutcomeCard: View {
    let icon: String
    let tint: Color
    let title: String
    let values: [(String, Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(PopupVisualTheme.primaryText)

            HStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 4) {
                        Text("\(value.1)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(PopupVisualTheme.primaryText)
                            .contentTransition(.numericText())
                        Text(value.0)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity)

                    if index < values.count - 1 {
                        Divider()
                            .overlay(PopupVisualTheme.primaryText.opacity(0.08))
                            .frame(height: 30)
                    }
                }
            }
        }
        .padding(StatsLayout.cardPadding)
        .background(subtleCardBackground(stroke: tint.opacity(0.16), cornerRadius: 16))
    }
}
