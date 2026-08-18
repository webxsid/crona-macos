import AppKit
import SwiftUI

struct HabitsTabView: View {
    @ObservedObject var appState: CompanionAppState
    @State private var loggingHabitID: Int64?
    @State private var logSeconds = 60

    var body: some View {
        let snapshot = appState.habitsService.snapshot

        ViewThatFits(in: .vertical) {
            habitsContent(snapshot: snapshot)

            ScrollView(.vertical) {
                habitsContent(snapshot: snapshot)
                    .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 480)
        }
    }

    @ViewBuilder
    private func habitsContent(snapshot: HabitsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(.green)
                    .frame(width: 22)
                Text(formattedPopoverDate(snapshot.date, appState: appState))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 13)

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
                            logSeconds: $logSeconds,
                            onComplete: { appState.completeHabit(habit) },
                            onBeginLog: {
                                logSeconds = max(60, (habit.targetMinutes ?? 1) * 60)
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    loggingHabitID = habit.id
                                }
                            },
                            onSubmitLog: {
                                appState.logHabit(
                                    habit,
                                    durationMinutes: max(
                                        1, Int((Double(logSeconds) / 60).rounded()))
                                )
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
                            onClear: { appState.clearHabitCompletion(habit) },
                            openDetails: {
                                appState.openHabitDetails(habit)
                            },
                            editHabit: { appState.presentHabitEditor(for: habit) },
                            deleteHabit: { appState.presentDeleteHabit(for: habit) }
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

struct HabitRow: View {
    let habit: HabitRowModel
    let isWorking: Bool
    let activeAction: String?
    let actionsDisabled: Bool
    let isLogging: Bool
    @Binding var logSeconds: Int
    let onComplete: () -> Void
    let onBeginLog: () -> Void
    let onSubmitLog: () -> Void
    let onCancelLog: () -> Void
    let onFail: () -> Void
    let onClear: () -> Void
    let openDetails: () -> Void
    let editHabit: () -> Void
    let deleteHabit: () -> Void

    var body: some View {
        VStack(spacing: isLogging ? 10 : 0) {
            HStack(spacing: 12) {
                statusBadge

                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundStyle(PopupVisualTheme.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        metaLabel(icon: "folder.fill", text: habit.repoName)
                        metaLabel(icon: "arrow.triangle.branch", text: habit.streamName)
                        if let detailText {
                            metaLabel(icon: "clock.fill", text: detailText)
                        }
                    }
                }
                .onTapGesture {
                    openDetails()
                }

                Spacer()

                Menu {
                    Button(action: openDetails) {
                        Label("View Details", systemImage: "info.circle")
                    }
                    Button(action: editHabit) {
                        Label("Edit Habit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: deleteHabit) {
                        Label("Delete Habit", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
                .help("Habit actions")

                if habit.supportsClearAction {
                    habitActionButton(
                        title: "Clear completion",
                        symbol: "arrow.uturn.backward",
                        tint: .white,
                        actionID: "clear",
                        action: onClear
                    )
                } else if !isLogging {
                    HStack(spacing: 7) {
                        habitActionButton(
                            title: "Mark failed",
                            symbol: "xmark",
                            tint: .red,
                            actionID: "failed",
                            action: onFail
                        )
                        habitActionButton(
                            title: usesDurationLogging ? "Log duration" : "Mark done",
                            symbol: "checkmark",
                            tint: .green,
                            actionID: "completed",
                            action: usesDurationLogging ? onBeginLog : onComplete
                        )
                    }
                }

            }

            if isLogging {
                InlineHabitLogEditor(
                    value: $logSeconds,
                    onCancel: onCancelLog,
                    onSubmit: onSubmitLog
                )
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(subtleCardBackground(stroke: statusColor.opacity(0.2), cornerRadius: 16))
        .contextMenu {
            Button(action: openDetails) {
                Label("View Details", systemImage: "info.circle")
            }
            Button(action: editHabit) {
                Label("Edit Habit", systemImage: "pencil")
            }
            Button(role: .destructive, action: deleteHabit) {
                Label("Delete Habit", systemImage: "trash")
            }
        }
    }

    private func habitActionButton(
        title: String,
        symbol: String?,
        tint: Color,
        actionID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isWorking && activeAction == actionID {
                    ProgressView()
                        .controlSize(.small)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(
                PopupVisualTheme.primaryText.opacity(actionsDisabled && !isWorking ? 0.42 : 0.9)
            )
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .background(
                Circle()
                    .fill(tint.opacity(0.10))
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(actionsDisabled)
        .help(title)
    }

    private var usesDurationLogging: Bool {
        (habit.targetMinutes ?? 0) > 0
    }

    private var detailText: String? {
        if let durationMinutes = habit.durationMinutes {
            return MenuBarTextFormatter.formatMinutes(durationMinutes)
        }
        if let targetMinutes = habit.targetMinutes {
            return MenuBarTextFormatter.formatMinutes(targetMinutes)
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
        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
    }
}

private struct InlineHabitLogEditor: View {
    @Binding var value: Int
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 4) {
            Text("Time logged")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 60, alignment: .leading)

            Spacer()

            HStack(spacing: 3) {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .focused($isFocused)
                    .frame(width: 96)
                    .onChange(of: draft) {
                        if let parsed = HabitDurationFormatter.seconds(from: draft) {
                            value = max(60, parsed)
                        }
                    }
                    .onSubmit(onSubmit)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(PopupVisualTheme.elevatedBackground)
                    .strokeBorder(
                        PopupVisualTheme.primaryText.opacity(isFocused ? 0.22 : 0.08), lineWidth: 1)
            )

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.58))
            .keyboardShortcut(.cancelAction)
            .menuBarIconHitTarget()

            Button(action: onSubmit) {
                Image(systemName: "checkmark")
                    .fontWeight(.bold)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.green.opacity(0.2)))
                    .menuBarIconHitTarget()
            }
            .buttonStyle(GlassPressButtonStyle())
            .foregroundStyle(PopupVisualTheme.primaryText)
            .keyboardShortcut(.defaultAction)
            .help("Log \(HabitDurationFormatter.string(from: value))")
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Divider()
                .overlay(PopupVisualTheme.primaryText.opacity(0.07))
        }
        .onAppear {
            draft = HabitDurationFormatter.string(from: value)
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: value) {
            if HabitDurationFormatter.seconds(from: draft) != value {
                draft = HabitDurationFormatter.string(from: value)
            }
        }
    }

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
                    .overlay(PopupVisualTheme.primaryText.opacity(0.08))
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
        .background(
            subtleCardBackground(
                stroke: PopupVisualTheme.primaryText.opacity(isExpanded ? 0.14 : 0.05),
                cornerRadius: 18
            )
        )
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
                    .overlay(PopupVisualTheme.primaryText.opacity(0.08))
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
        .background(
            subtleCardBackground(
                stroke: PopupVisualTheme.primaryText.opacity(isExpanded ? 0.14 : 0.05),
                cornerRadius: 18
            )
        )
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
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))

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
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PopupVisualTheme.elevatedBackground)
                    .strokeBorder(
                        PopupVisualTheme.primaryText.opacity(isFocused ? 0.24 : 0.08),
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
                .fill(PopupVisualTheme.primaryText.opacity(0.045))
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
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.82))
                .frame(width: 30, height: 30)
                .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.08)))
                .menuBarIconHitTarget()
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(systemName == "plus" ? "Add five minutes" : "Remove five minutes")
    }
}
