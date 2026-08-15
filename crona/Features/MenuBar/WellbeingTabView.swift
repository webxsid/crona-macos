import SwiftUI

struct WellbeingTabView: View {
    private enum SaveFeedback: Equatable {
        case success
        case error(String)
    }

    @ObservedObject var appState: CompanionAppState
    @State private var mood = 0
    @State private var energy = 0
    @State private var hasSleepDuration = false
    @State private var sleepHours = 8
    @State private var sleepMinutes = 0
    @State private var hasSleepScore = false
    @State private var sleepScore = 80
    @State private var hasScreenTime = false
    @State private var screenHours = 2
    @State private var screenMinutes = 0
    @State private var notes = ""
    @State private var validationError: String?
    @State private var loadedEntry: CronaDailyCheckIn?
    @State private var baselineRequest: CronaDailyCheckInUpsertRequest?
    @State private var saveFeedback: SaveFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var suppressServiceError = false

    private let minuteOptions = [0, 15, 30, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            ratingRow("Mood", symbol: "face.smiling", value: $mood, tint: .pink)
            ratingRow("Energy", symbol: "bolt.fill", value: $energy, tint: .yellow)

            VStack(spacing: 0) {
                durationInput(
                    title: "Sleep duration",
                    subtitle: "Time asleep last night",
                    symbol: "moon.zzz.fill",
                    isIncluded: $hasSleepDuration,
                    hours: $sleepHours,
                    minutes: $sleepMinutes
                )
                Divider().padding(.leading, 42)
                scoreInput
                Divider().padding(.leading, 42)
                durationInput(
                    title: "Screen time",
                    subtitle: "Total device time today",
                    symbol: "display",
                    isIncluded: $hasScreenTime,
                    hours: $screenHours,
                    minutes: $screenMinutes
                )
            }
            .background(cardBackground(stroke: PopupVisualTheme.border, cornerRadius: 14))

            VStack(alignment: .leading, spacing: 7) {
                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                StableMultilineTextField(text: $notes, placeholder: "Anything else worth remembering? (optional)")
                    .frame(height: 64)
                    .popupInputSurface(cornerRadius: 12)
            }

            feedbackView

            Button(action: save) {
                if appState.wellbeingService.snapshot.isSaving {
                    ProgressView().controlSize(.small)
                } else if saveFeedback == .success {
                    Label("Check-In Updated", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                } else {
                    Text(appState.wellbeingService.snapshot.checkIn == nil ? "Save Check-In" : "Update Check-In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
        }
        .fixedSize(horizontal: false, vertical: true)
        .task { await appState.wellbeingService.refresh() }
        .onChange(of: appState.wellbeingService.snapshot.checkIn) { _, entry in load(entry) }
        .onChange(of: currentRequest) { _, _ in
            guard saveFeedback != nil else { return }
            feedbackDismissTask?.cancel()
            saveFeedback = nil
        }
        .onAppear { load(appState.wellbeingService.snapshot.checkIn) }
        .onDisappear { feedbackDismissTask?.cancel() }
    }

    private var canSave: Bool {
        mood > 0
            && energy > 0
            && !appState.wellbeingService.snapshot.isSaving
            && currentRequest != baselineRequest
    }

    @ViewBuilder
    private var feedbackView: some View {
        Group {
            switch saveFeedback {
            case .success:
                Label("Check-in updated", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .error(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
            case nil:
                if let error = validationError
                    ?? (suppressServiceError ? nil : appState.wellbeingService.snapshot.lastErrorDescription) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(2)
                } else {
                    Color.clear
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .contentTransition(.opacity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Wellbeing")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                Text(appState.wellbeingService.snapshot.checkIn == nil ? "How are you feeling today?" : "Today’s check-in")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
            }
            Spacer()
            if appState.wellbeingService.snapshot.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func ratingRow(_ title: String, symbol: String, value: Binding<Int>, tint: Color) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)
                .frame(width: 84, alignment: .leading)
            ForEach(1...5, id: \.self) { rating in
                Button { value.wrappedValue = rating } label: {
                    Text("\(rating)")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 30)
                        .background(Capsule().fill(value.wrappedValue == rating ? tint.opacity(0.82) : PopupVisualTheme.primaryText.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(rating) of 5")
            }
        }
    }

    private func durationInput(
        title: String,
        subtitle: String,
        symbol: String,
        isIncluded: Binding<Bool>,
        hours: Binding<Int>,
        minutes: Binding<Int>
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(PopupVisualTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if isIncluded.wrappedValue {
                Picker("Hours", selection: hours) {
                    ForEach(0...24, id: \.self) { Text("\($0) hr").tag($0) }
                }
                .labelsHidden().frame(width: 72)
                Picker("Minutes", selection: minutes) {
                    ForEach(minuteOptions, id: \.self) { Text("\($0) min").tag($0) }
                }
                .labelsHidden().frame(width: 78)
                clearButton { isIncluded.wrappedValue = false }
            } else {
                addButton { isIncluded.wrappedValue = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private var scoreInput: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep score").font(.subheadline.weight(.semibold))
                Text("Recovery quality, from 0 to 100").font(.caption2).foregroundStyle(PopupVisualTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if hasSleepScore {
                Stepper(value: $sleepScore, in: 0...100) {
                    Text("\(sleepScore)")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .fixedSize()
                clearButton { hasSleepScore = false }
            } else {
                addButton { hasSleepScore = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button("Add", action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear value")
    }

    private func load(_ entry: CronaDailyCheckIn?) {
        guard loadedEntry != entry else { return }
        loadedEntry = entry
        suppressServiceError = false
        mood = entry?.mood ?? 0
        energy = entry?.energy ?? 0
        hasSleepDuration = entry?.sleepHours != nil
        if let value = entry?.sleepHours {
            (sleepHours, sleepMinutes) = splitMinutes(Int((value * 60).rounded()))
        }
        hasSleepScore = entry?.sleepScore != nil
        sleepScore = entry?.sleepScore ?? 80
        hasScreenTime = entry?.screenTimeMinutes != nil
        if let value = entry?.screenTimeMinutes {
            (screenHours, screenMinutes) = splitMinutes(value)
        }
        notes = entry?.notes ?? ""
        baselineRequest = request(
            mood: mood,
            energy: energy,
            sleepHours: hasSleepDuration ? Double(sleepHours) + Double(sleepMinutes) / 60 : nil,
            sleepScore: hasSleepScore ? sleepScore : nil,
            screenTimeMinutes: hasScreenTime ? screenHours * 60 + screenMinutes : nil,
            notes: notes
        )
    }

    private func splitMinutes(_ total: Int) -> (Int, Int) {
        let rounded = max(0, Int((Double(total) / 15).rounded()) * 15)
        return (min(24, rounded / 60), rounded % 60)
    }

    private func save() {
        validationError = nil
        suppressServiceError = true
        feedbackDismissTask?.cancel()
        saveFeedback = nil
        let request = currentRequest
        Task {
            if await appState.wellbeingService.save(request) {
                baselineRequest = request
                showFeedback(.success)
                await appState.popoverStatsService.refresh()
                await appState.popoverStatsService.refreshTodayMetrics()
            } else {
                showFeedback(.error(
                    appState.wellbeingService.snapshot.lastErrorDescription
                        ?? "Couldn’t update the check-in. Try again."
                ))
            }
        }
    }

    private var currentRequest: CronaDailyCheckInUpsertRequest {
        request(
            mood: mood,
            energy: energy,
            sleepHours: hasSleepDuration ? Double(sleepHours) + Double(sleepMinutes) / 60 : nil,
            sleepScore: hasSleepScore ? sleepScore : nil,
            screenTimeMinutes: hasScreenTime ? screenHours * 60 + screenMinutes : nil,
            notes: notes
        )
    }

    private func request(
        mood: Int,
        energy: Int,
        sleepHours: Double?,
        sleepScore: Int?,
        screenTimeMinutes: Int?,
        notes: String
    ) -> CronaDailyCheckInUpsertRequest {
        CronaDailyCheckInUpsertRequest(
            date: DailyFocusService.todayString(),
            mood: mood,
            energy: energy,
            sleepHours: sleepHours,
            sleepScore: sleepScore,
            screenTimeMinutes: screenTimeMinutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func showFeedback(_ feedback: SaveFeedback) {
        feedbackDismissTask?.cancel()
        saveFeedback = feedback
        feedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            saveFeedback = nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
