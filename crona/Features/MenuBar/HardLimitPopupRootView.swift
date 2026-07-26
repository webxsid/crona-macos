import SwiftUI

struct HardLimitPopupRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        if let phase = appState.hardLimitPopupPhase {
            let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)

            ZStack {
                PopoverGlassBackground()

                VStack(spacing: 0) {
                    content(for: phase)
                }
                .padding(18)
            }
            .frame(width: 392)
            .contentShape(shape)
            .clipShape(shape)
            .opacity(appState.isHardLimitPopupAnimatingIn ? 1 : 0.02)
            .blur(radius: appState.isHardLimitPopupAnimatingIn ? 0 : 18)
            .scaleEffect(appState.isHardLimitPopupAnimatingIn ? 1 : 0.96)
            .animation(.easeOut(duration: 0.18), value: appState.isHardLimitPopupAnimatingIn)
        }
    }

    @ViewBuilder
    private func content(for phase: HardLimitPopupPhase) -> some View {
        switch phase {
        case .decision:
            HardLimitDecisionView(appState: appState)
        case .endSession:
            HardLimitEndSessionView(appState: appState)
        case .extend:
            HardLimitExtendView(appState: appState)
        case .success:
            HardLimitExtendSuccessView(appState: appState)
        }
    }
}

private struct HardLimitDecisionView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var countdown: HardLimitCountdownService
    @FocusState private var focusedAction: DecisionAction?

    init(appState: CompanionAppState) {
        self.appState = appState
        self.countdown = appState.hardLimitCountdownService
    }

    var body: some View {
        let presentation = TimerPresentation.from(appState.timerService.snapshot)
        let title = presentation.mode == .timer
            ? "Timer Session Complete"
            : "Pomodoro Session Complete"
        let subtitle = presentation.mode == .timer
            ? "Choose how to finish this timer session."
            : "Choose how to finish this Pomodoro session."

        VStack(spacing: 16) {
            header(symbol: "hourglass.circle.fill", title: title, subtitle: subtitle)

            Text(MenuBarTextFormatter.formatElapsed(
                seconds: presentation.displaySeconds,
                format: appState.preferences.preferences.menuBarTimeFormat,
                showsSeconds: appState.preferences.preferences.menuBarShowsSeconds
            ))
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)

            contextCard

            VStack(spacing: 10) {
                Button {
                    appState.chooseHardLimitExtend()
                } label: {
                    popupButtonLabel(title: "Extend", shortcut: "X")
                }
                .buttonStyle(PopupFullWidthButtonStyle(style: .primary))
                .keyboardShortcut("x", modifiers: [])
                .focused($focusedAction, equals: .extend)
                .onHover {
                    countdown.setPaused($0, reason: .hoverExtend)
                }

                Button {
                    appState.chooseHardLimitEnd()
                } label: {
                    popupButtonLabel(
                        title: "End",
                        detail: "\(countdown.state.displayedSeconds)s",
                        shortcut: "E"
                    )
                }
                .buttonStyle(
                    PopupFullWidthButtonStyle(
                        style: .secondary,
                        progress: countdown.state.progress
                    )
                )
                .keyboardShortcut("e", modifiers: [])
                .focused($focusedAction, equals: .end)
                .onHover {
                    countdown.setPaused($0, reason: .hoverEnd)
                }
            }
        }
        .padding(8)
        .onChange(of: focusedAction) { _, newAction in
            countdown.setPaused(newAction != nil, reason: .keyboardFocus)
        }
        .onDisappear {
            countdown.clearPauseReasons()
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let issue = appState.contextService.snapshot.issueTitle {
                Label(issue, systemImage: "record.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            HStack(spacing: 14) {
                if let repo = appState.contextService.snapshot.repoName {
                    meta(icon: "folder.fill", text: repo)
                }
                if let stream = appState.contextService.snapshot.streamName {
                    meta(icon: "arrow.triangle.branch", text: stream)
                }
            }

            Text("Choose whether to extend this session or commit it now.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground(stroke: Color.white.opacity(0.08)))
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.72))
    }

    private enum DecisionAction: Hashable {
        case extend
        case end
    }
}

private struct HardLimitEndSessionView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "checkmark.circle", title: "End Session", subtitle: "Add the commit message that will be stored with this session.")

            VStack(alignment: .leading, spacing: 10) {
                Text("Commit Message")
                    .font(.headline)
                    .foregroundStyle(.white)

                StableMultilineTextField(
                    text: $appState.endSessionCommitMessage,
                    placeholder: "Describe what you completed",
                    isEnabled: !appState.isSubmittingEndSession,
                    focusRequest: appState.endSessionFocusRequest
                )
                .frame(height: 110)
                .background(cardBackground(stroke: Color.white.opacity(0.08)))

                if let error = appState.endSessionErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.92))
                }
            }

            VStack(spacing: 10) {
                Button {
                    appState.confirmEndSession()
                } label: {
                    popupButtonLabel(
                        title: appState.isSubmittingEndSession ? "Ending Session" : "End Session",
                        shortcut: "⌘↩",
                        isLoading: appState.isSubmittingEndSession
                    )
                }
                .buttonStyle(PopupFullWidthButtonStyle(style: .primary))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(appState.isSubmittingEndSession)

                Button {
                    appState.returnToHardLimitDecision()
                } label: {
                    popupButtonLabel(title: "Back", shortcut: "esc")
                }
                .buttonStyle(PopupFullWidthButtonStyle(style: .secondary))
                .keyboardShortcut(.cancelAction)
                .disabled(appState.isSubmittingEndSession)
            }
        }
        .padding(8)
    }
}

private struct HardLimitExtendView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        let mode = TimerPresentation.from(appState.timerService.snapshot).mode
        let title = mode == .timer ? "Extend Timer Session" : "Extend Pomodoro Session"
        let subtitle = mode == .timer
            ? "Add time to the current countdown. No breaks or cycles."
            : "Choose how many Pomodoro sessions to add using the current cadence."

        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "plus.circle", title: title, subtitle: subtitle)

            VStack(spacing: 10) {
                ForEach(Array(choices(for: mode).enumerated()), id: \.element.id) { index, choice in
                    Button {
                        appState.hardLimitPopupExtendChoice = choice
                    } label: {
                        HStack {
                            Text(choice.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            if appState.hardLimitPopupExtendChoice == choice {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            shortcutHint("\(index + 1)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(appState.hardLimitPopupExtendChoice == choice ? 0.1 : 0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                }
            }

            if let endDate = appState.hardLimitExtensionEndDate {
                EndsAtRow(date: endDate)
            }

            if let error = appState.hardLimitPopupErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.92))
            }

            VStack(spacing: 10) {
                Button {
                    appState.confirmHardLimitExtend()
                } label: {
                    popupButtonLabel(
                        title: appState.isSubmittingHardLimitAction ? "Extending" : "Extend",
                        shortcut: "↩",
                        isLoading: appState.isSubmittingHardLimitAction
                    )
                }
                .buttonStyle(PopupFullWidthButtonStyle(style: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isSubmittingHardLimitAction)

                Button {
                    appState.returnToHardLimitDecision()
                } label: {
                    popupButtonLabel(title: "Back", shortcut: "esc")
                }
                .buttonStyle(PopupFullWidthButtonStyle(style: .secondary))
                .keyboardShortcut(.cancelAction)
                .disabled(appState.isSubmittingHardLimitAction)
            }
        }
        .padding(8)
    }

    private func choices(for mode: FocusTimerMode) -> [HardLimitExtendChoice] {
        switch mode {
        case .pomodoro:
            return [.session1, .session2]
        case .stopwatch, .timer:
            return [.minutes1, .minutes5, .minutes15]
        }
    }
}

private struct HardLimitExtendSuccessView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        let success = appState.hardLimitPopupSuccessModel

        VStack(spacing: 18) {
            header(symbol: "checkmark.circle.fill", title: "Session Extended", subtitle: "The daemon accepted the extension and refreshed the timer.")

            VStack(spacing: 12) {
                successRow(title: "Time Remaining", value: success?.remainingTimeText ?? "—")
                successRow(title: "New End Time", value: success?.endTimeText ?? "—")
            }
            .padding(16)
            .background(cardBackground(stroke: Color.white.opacity(0.08)))

            Text("This popup will close automatically.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(8)
    }

    private func successRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}

private enum PopupActionVisualStyle {
    case primary
    case secondary
}

private struct PopupFullWidthButtonStyle: ButtonStyle {
    let style: PopupActionVisualStyle
    var progress: Double? = nil

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                ZStack(alignment: .leading) {
                    background(configuration.isPressed)
                    if let progress {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: geometry.size.width * min(1, max(0, progress)))
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }

    private func background(_ isPressed: Bool) -> some View {
        let baseOpacity: Double
        switch style {
        case .primary:
            baseOpacity = isPressed ? 0.26 : 0.20
        case .secondary:
            baseOpacity = isPressed ? 0.14 : 0.10
        }

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(baseOpacity))
    }
}

private func popupButtonLabel(
    title: String,
    detail: String? = nil,
    shortcut: String,
    isLoading: Bool = false
) -> some View {
    ZStack {
        HStack(spacing: 7) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
            if let detail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.62))
            }
        }

        HStack {
            Spacer()
            shortcutHint(shortcut)
        }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity)
}

private func shortcutHint(_ shortcut: String) -> some View {
    Text(shortcut)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.16))
        )
}

private func header(symbol: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
        Text(title)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.66))
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
}
