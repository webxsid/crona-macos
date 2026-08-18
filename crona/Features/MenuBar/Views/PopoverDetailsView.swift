import SwiftUI

struct PopoverDetailView: View {
    @ObservedObject var appState: CompanionAppState
    let route: PopoverDetailRoute

    var body: some View {
        Group {
            switch route {
            case .issueDetails(let issueID):
                if let issue = appState.dailyFocusService.snapshot.issues.first(where: { $0.id == issueID }) {
                    IssueDetailView(appState: appState, issue: issue)
                } else {
                    missingDetail(title: "Issue unavailable")
                }
            case .habitDetails(let habitID):
                if let habit = appState.habitsService.snapshot.items.first(where: { $0.id == habitID }) {
                    HabitDetailView(appState: appState, habit: habit)
                } else {
                    missingDetail(title: "Habit unavailable")
                }
            }
        }
    }

    private func missingDetail(title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.title2)
                .foregroundStyle(PopupVisualTheme.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(PopupVisualTheme.primaryText)
            Button("Back") { appState.dismissDetails() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct IssueDetailView: View {
    @ObservedObject var appState: CompanionAppState
    let issue: DailyFocusIssue

    var body: some View {
        detailScroll {
            DetailHeader(
                title: issue.title,
                subtitle: "Issue",
                icon: CronaIssueStatusPresentation.icon(for: issue.status),
                tint: CronaIssueStatusPresentation.color(for: issue.status),
                onBack: appState.dismissDetails
            ) {
                Menu {
                    Button {
                        appState.dismissDetails()
                        appState.presentIssueEditor(for: issue)
                    } label: {
                        Label("Edit Issue", systemImage: "pencil")
                    }
                    Button {
                        appState.dismissDetails()
                        appState.presentManualSession(for: issue)
                    } label: {
                        Label("Log Session…", systemImage: "clock.fill")
                    }
                    Menu("Change Status") {
                        ForEach(CronaIssueStatus.allCases) { status in
                            Button {
                                appState.dismissDetails()
                                appState.requestIssueStatusChange(issue: issue, status: status)
                            } label: {
                                Label(status.title, systemImage: status.systemImage)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        appState.dismissDetails()
                        appState.presentDeleteIssue(for: issue)
                    } label: {
                        Label("Delete Issue", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }

            DetailSection(title: "Status", icon: CronaIssueStatusPresentation.icon(for: issue.status)) {
                DetailStatusRow(
                    title: CronaIssueStatusPresentation.status(for: issue.status)?.title
                        ?? issue.status.replacingOccurrences(of: "_", with: " ").capitalized,
                    tint: CronaIssueStatusPresentation.color(for: issue.status)
                )
            }

            if let description = nonEmpty(issue.description) {
                DetailSection(title: "Description", icon: "text.alignleft") {
                    DetailBodyText(description)
                }
            }

            if let notes = nonEmpty(issue.notes) {
                DetailSection(title: "Notes", icon: "note.text") {
                    DetailBodyText(notes)
                }
            }

            DetailSection(title: "Planning", icon: "slider.horizontal.3") {
                DetailMetadataGrid(rows: [
                    ("Repository", issue.repoName ?? "—"),
                    ("Worked", MenuBarTextFormatter.formatCompactDuration(seconds: issue.workedSeconds)),
                    ("Estimate", issue.estimateMinutes.map(MenuBarTextFormatter.formatMinutes) ?? "—"),
                    ("Due", issue.todoForDate.map { formattedPopoverDate($0, appState: appState) } ?? "—"),
                    ("Pinned", issue.pinnedDaily == true ? "Daily" : "No")
                ])
            }

            Button {
                appState.dismissDetails()
                appState.selectFocusIssue(issue)
            } label: {
                Label("Start Focus", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct HabitDetailView: View {
    @ObservedObject var appState: CompanionAppState
    let habit: HabitRowModel
    @State private var isLoggingDuration = false
    @State private var durationDraft = ""
    @State private var durationError: String?
    @FocusState private var durationFieldFocused: Bool

    var body: some View {
        detailScroll {
            DetailHeader(
                title: habit.name,
                subtitle: "Habit",
                icon: "checklist.checked",
                tint: habitTint,
                onBack: appState.dismissDetails
            ) {
                Menu {
                    Button {
                        appState.dismissDetails()
                        appState.presentHabitEditor(for: habit)
                    } label: {
                        Label("Edit Habit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        appState.dismissDetails()
                        appState.presentDeleteHabit(for: habit)
                    } label: {
                        Label("Delete Habit", systemImage: "trash")
                    }
                    Divider()
                    Button {
                        appState.dismissDetails()
                        if habit.completed || habit.status == "failed" {
                            appState.clearHabitCompletion(habit)
                        } else {
                            appState.completeHabit(habit)
                        }
                    } label: {
                        Label(
                            habit.completed || habit.status == "failed" ? "Clear Completion" : "Mark Done",
                            systemImage: habit.completed || habit.status == "failed"
                                ? "arrow.uturn.backward" : "checkmark"
                        )
                    }
                    if !habit.completed {
                        Button {
                            appState.dismissDetails()
                            appState.failHabit(habit)
                        } label: {
                            Label("Mark Failed", systemImage: "xmark")
                        }
                    }
                    Button {
                        let targetSeconds = max(60, (habit.targetMinutes ?? 1) * 60)
                        durationDraft = HabitDurationFormatter.string(from: targetSeconds)
                        durationError = nil
                        isLoggingDuration = true
                        DispatchQueue.main.async {
                            durationFieldFocused = true
                        }
                    } label: {
                        Label("Log Duration…", systemImage: "clock.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }

            DetailSection(title: "Today", icon: habitStatusIcon) {
                DetailStatusRow(title: habitStatusTitle, tint: habitTint)
            }

            if let description = nonEmpty(habit.description) {
                DetailSection(title: "Description", icon: "text.alignleft") {
                    DetailBodyText(description)
                }
            }

            DetailSection(title: "Schedule", icon: "calendar") {
                DetailMetadataGrid(rows: [
                    ("Repository", habit.repoName),
                    ("Stream", habit.streamName),
                    ("Schedule", scheduleText),
                    ("Target", habit.targetMinutes.map(MenuBarTextFormatter.formatMinutes) ?? "No target"),
                    ("Logged", habit.durationMinutes.map(MenuBarTextFormatter.formatMinutes) ?? "—"),
                    ("Date", habit.completionDate.map { formattedPopoverDate($0, appState: appState) } ?? "—")
                ])
            }

            if isLoggingDuration {
                DetailSection(title: "Log Duration", icon: "clock.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("0h0m0s", text: $durationDraft)
                                .textFieldStyle(.plain)
                                .popupInputSurface()
                                .padding(.horizontal, 9)
                                .frame(height: 30)
                                .focused($durationFieldFocused)
                                .onSubmit(submitDuration)
                                .onChange(of: durationDraft) {
                                    durationError = nil
                                }

                            Button("Cancel") {
                                isLoggingDuration = false
                                durationFieldFocused = false
                            }
                            .buttonStyle(.bordered)

                            Button("Save", action: submitDuration)
                                .buttonStyle(.borderedProminent)
                                .disabled(parsedDuration == nil || parsedDuration == 0)
                        }

                        Text("Use HhMmSs, for example 1h20m30s or 01:20:30")
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.secondaryText)

                        if let durationError {
                            Text(durationError)
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.9))
                        }
                    }
                }
            }

            if let notes = nonEmpty(habit.notes) {
                DetailSection(title: "Notes", icon: "note.text") {
                    DetailBodyText(notes)
                }
            }

            if !habit.completed && habit.status != "failed" {
                HStack(spacing: 10) {
                    Button {
                        appState.failHabit(habit)
                    } label: {
                        Label("Fail", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appState.completeHabit(habit)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var habitStatusTitle: String {
        switch habit.status {
        case "completed": return "Done"
        case "failed": return "Failed"
        default: return "Due"
        }
    }

    private var habitStatusIcon: String {
        switch habit.status {
        case "completed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    private var parsedDuration: Int? {
        guard let seconds = HabitDurationFormatter.seconds(from: durationDraft), seconds > 0 else {
            return nil
        }
        return seconds
    }

    private func submitDuration() {
        guard let seconds = parsedDuration else {
            durationError = "Enter a duration greater than zero."
            durationFieldFocused = true
            return
        }

        appState.logHabit(
            habit,
            durationMinutes: max(1, Int((Double(seconds) / 60).rounded()))
        )
        durationFieldFocused = false
        isLoggingDuration = false
    }

    private var habitTint: Color {
        switch habit.status {
        case "completed": return .green
        case "failed": return .red
        default: return .yellow
        }
    }

    private var scheduleText: String {
        switch habit.scheduleType {
        case "weekdays":
            return habit.weekdays.map(String.init).joined(separator: ", ")
        case "weekly": return "Weekly"
        default: return "Daily"
        }
    }
}

private struct DetailHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let onBack: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .lineLimit(1)
                    .help(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
            }

            Spacer(minLength: 4)
            actions()
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.secondaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(subtleCardBackground(stroke: PopupVisualTheme.surfaceStroke, cornerRadius: 14))
    }
}

private struct DetailStatusRow: View {
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)
        }
    }
}

private struct DetailMetadataGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                    Spacer(minLength: 8)
                    Text(row.1)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PopupVisualTheme.primaryText)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct DetailBodyText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.84))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func detailScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
    .scrollIndicators(.hidden)
    .frame(maxHeight: 480)
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}
