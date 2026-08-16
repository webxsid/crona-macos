import SwiftUI

private enum HoverDismissPopupMetrics {
    static let leadingInset: CGFloat = 12
    static let topInset: CGFloat = 10
    static let buttonOffsetX: CGFloat = 4
    static let buttonOffsetY: CGFloat = 4
    static let compactDiameter: CGFloat = 22
}

enum HardLimitPopupSizing {
    static let contentWidth: CGFloat = 392
    static let panelWidth: CGFloat = 408
    static func panelHeight(for phase: HardLimitPopupPhase?) -> CGFloat {
        switch phase {
        case .decision: 434
        case .endSession: 382
        case .extend: 480
        case .success: 268
        case nil: 434
        }
    }
}

struct HardLimitPopupRootView: View {
    @ObservedObject var appState: CompanionAppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let phase = appState.hardLimitPopupPhase {
                HoverDismissPopupChrome(
                    cornerRadius: 28,
                    showsDismissControl: phase != .endSession,
                    dismissLabel: "End Session",
                    onClose: appState.handleHardLimitPopupClose
                ) {
                    VStack(spacing: 0) {
                        content(for: phase)
                    }
                    .padding(8)
                }
                .frame(width: HardLimitPopupSizing.contentWidth)
                .opacity(appState.isHardLimitPopupAnimatingIn ? 1 : 0)
                .blur(radius: reduceMotion || appState.isHardLimitPopupAnimatingIn ? 0 : 28)
                .scaleEffect(reduceMotion || appState.isHardLimitPopupAnimatingIn ? 1 : 0.97)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.24),
                    value: appState.isHardLimitPopupAnimatingIn)
            }
        }
        .frame(
            width: HardLimitPopupSizing.panelWidth,
            height: HardLimitPopupSizing.panelHeight(for: appState.hardLimitPopupPhase),
            alignment: .center
        )
        .companionAppearance(appState)
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

struct InactivityPopupRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        if let phase = appState.inactivityPopupPhase {
            HoverDismissPopupChrome(
                cornerRadius: 24,
                showsDismissControl: phase != .endSession,
                dismissLabel: "Keep Running",
                onClose: appState.dismissInactivityPopup
            ) {
                VStack(spacing: 0) {
                    switch phase {
                    case .decision:
                        InactivityDecisionView(appState: appState)
                    case .endSession:
                        InactivityEndSessionView(appState: appState)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(width: 372)
            .companionAppearance(appState)
        }
    }
}

struct SmartPauseResumeNoticeRootView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        if appState.smartPauseResumeNotice != nil {
            HoverDismissPopupChrome(
                cornerRadius: 24,
                showsDismissControl: true,
                dismissLabel: "Dismiss",
                onClose: appState.dismissSmartPauseResumeNoticeNow
            ) {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Focus resumed")
                            .font(.subheadline.weight(.semibold))
                        Text("Crona resumed your stopwatch when you returned.")
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .frame(width: 272, height: 82)
            .companionAppearance(appState)
        }
    }
}

private struct HoverDismissPopupChrome<Content: View>: View {
    let cornerRadius: CGFloat
    let showsDismissControl: Bool
    let dismissLabel: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isShellHovered = false
    @State private var isButtonHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack(alignment: .topLeading) {
            ZStack {
                PopoverGlassBackground(cornerRadius: cornerRadius)

                content()
            }
            .contentShape(shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.7)
            }
            .padding(.leading, HoverDismissPopupMetrics.leadingInset)
            .padding(.top, HoverDismissPopupMetrics.topInset)
            .onHover { isShellHovered = $0 }

            if showsDismissControl && (isShellHovered || isButtonHovered) {
                hoverCloseButton
                    .padding(.leading, HoverDismissPopupMetrics.buttonOffsetX)
                    .padding(.top, HoverDismissPopupMetrics.buttonOffsetY)
                    .zIndex(2)
            }
        }
        .onExitCommand {
            if showsDismissControl {
                onClose()
            }
        }
    }

    private var hoverCloseButton: some View {
        Button(action: onClose) {
            HStack(spacing: isButtonHovered ? 7 : 0) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)

                if isButtonHovered {
                    Text(dismissLabel)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.78))
            .padding(.leading, isButtonHovered ? 7 : 0)
            .padding(.trailing, isButtonHovered ? 10 : 0)
            .frame(
                width: isButtonHovered ? nil : HoverDismissPopupMetrics.compactDiameter,
                height: HoverDismissPopupMetrics.compactDiameter
            )
            .background(
                Capsule(style: .continuous)
                    .fill(PopupVisualTheme.controlBackground)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(PopupVisualTheme.border, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .contentShape(Capsule(style: .continuous))
        .help(dismissLabel)
        .onHover { isButtonHovered = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.16), value: isButtonHovered)
        .animation(.easeOut(duration: 0.14), value: isShellHovered)
    }
}

private struct InactivityDecisionView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var countdown: HardLimitCountdownService
    @FocusState private var focusedAction: DecisionAction?

    init(appState: CompanionAppState) {
        self.appState = appState
        self.countdown = appState.inactivityPopupCountdownService
    }

    var body: some View {
        VStack(spacing: 6) {
            summaryRow

            HStack(spacing: 8) {
                Button {
                    appState.chooseInactivityPopupEnd()
                } label: {
                    popupCompactButtonLabel(title: "End Session", shortcut: "E")
                }
                .buttonStyle(InactivityPopupButtonStyle())
                .frame(maxWidth: .infinity)
                .keyboardShortcut("e", modifiers: [])
                .focused($focusedAction, equals: .end)
                .onHover {
                    countdown.setPaused($0, reason: .hoverEnd)
                }

                Button {
                    appState.dismissInactivityPopup()
                } label: {
                    popupCompactButtonLabel(
                        title: "Keep Running",
                        detail: "\(countdown.state.displayedSeconds)s",
                        shortcut: "esc"
                    )
                }
                .buttonStyle(
                    InactivityPopupButtonStyle(
                        progress: countdown.state.progress
                    )
                )
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.cancelAction)
                .focused($focusedAction, equals: .dismiss)
                .onHover {
                    countdown.setPaused($0, reason: .hoverExtend)
                }
            }
        }
        .padding(.vertical, 1)
        .onChange(of: focusedAction) { _, newAction in
            countdown.setPaused(newAction != nil, reason: .keyboardFocus)
        }
        .onDisappear {
            countdown.clearPauseReasons()
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "timer.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.64))

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    appState.inactivityPopupDelivery?.alert.title
                        ?? "Still focusing?"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)
                .lineLimit(1)

                HStack(spacing: 10) {
                    meta(icon: "timer", text: elapsedText)
                    if let repo = appState.contextService.snapshot.repoName {
                        meta(icon: "folder.fill", text: repo)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
    }

    private var elapsedText: String {
        MenuBarTextFormatter.formatClock(
            seconds: TimerPresentation.projectedDisplaySeconds(
                for: appState.timerService.snapshot,
                at: Date()
            )
        )
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
    }

    private enum DecisionAction: Hashable {
        case end
        case dismiss
    }
}

private struct InactivityEndSessionView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        PopupEndSessionForm(
            appState: appState,
            subtitle: "Add a short note for this focus session.",
            onBack: { appState.returnToInactivityDecision() }
        )
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
        let title = "Focus time is up"
        let subtitle = "Your planned focus limit has been reached. What would you like to do next?"

        VStack(spacing: 12) {
            header(symbol: "hourglass.circle.fill", title: title, subtitle: subtitle)

            Text(MenuBarTextFormatter.formatClock(seconds: presentation.displaySeconds))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PopupVisualTheme.primaryText)

            contextCard

            VStack(spacing: 8) {
                Button {
                    appState.chooseHardLimitEnd()
                } label: {
                    popupButtonLabel(
                        title: "Finish Session",
                        detail: "Save what you completed and close the session · in \(countdown.state.displayedSeconds)s",
                        shortcut: "E"
                    )
                }
                .buttonStyle(
                    PopupFullWidthButtonStyle(style: .primary, progress: countdown.state.progress)
                )
                .keyboardShortcut("e", modifiers: [])
                .focused($focusedAction, equals: .end)
                .onHover {
                    countdown.setPaused($0, reason: .hoverEnd)
                }

                Button {
                    appState.chooseHardLimitExtend()
                } label: {
                    popupButtonLabel(
                        title: "Keep Working",
                        detail: "Add time and continue this session",
                        shortcut: "X"
                    )
                }
                .buttonStyle(PopupFullWidthButtonStyle(style: .secondary))
                .keyboardShortcut("x", modifiers: [])
                .focused($focusedAction, equals: .extend)
                .onHover {
                    countdown.setPaused($0, reason: .hoverExtend)
                }
            }
        }
        .padding(10)
        .onChange(of: focusedAction) { _, newAction in
            countdown.setPaused(newAction != nil, reason: .keyboardFocus)
        }
        .onDisappear {
            countdown.clearPauseReasons()
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let issue = appState.contextService.snapshot.issueTitle {
                Label(issue, systemImage: "record.circle.fill")
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText)
            }

            HStack(spacing: 14) {
                if let repo = appState.contextService.snapshot.repoName {
                    meta(icon: "folder.fill", text: repo)
                }
                if let stream = appState.contextService.snapshot.streamName {
                    meta(icon: "arrow.triangle.branch", text: stream)
                }
            }

            Text("Choose how to continue: add time to keep working, or finish and save the session.")
                .font(.footnote)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.66))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 14))
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
    }

    private enum DecisionAction: Hashable {
        case extend
        case end
    }
}

private struct HardLimitEndSessionView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        PopupEndSessionForm(
            appState: appState,
            subtitle: "What did you complete? Add a short note before closing the session.",
            onBack: { appState.returnToHardLimitDecision() }
        )
    }
}

private struct PopupEndSessionForm: View {
    @ObservedObject var appState: CompanionAppState
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(symbol: "checkmark.circle", title: "End Session", subtitle: subtitle)

            VStack(alignment: .leading, spacing: 10) {
                Text("What did you complete?")
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText)

                StableMultilineTextField(
                    text: $appState.endSessionCommitMessage,
                    placeholder: "e.g. Updated the install docs and verified the Linux steps",
                    isEnabled: !appState.isSubmittingEndSession,
                    focusRequest: appState.endSessionFocusRequest
                )
                .frame(height: 104)
                .popupInputSurface(cornerRadius: 12)

                if let error = appState.endSessionErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.92))
                }
            }

            VStack(spacing: 8) {
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
                    onBack()
                } label: {
                    popupButtonLabel(title: "Back", shortcut: "esc")
                }
                .buttonStyle(PopupFullWidthButtonStyle(style: .secondary))
                .keyboardShortcut(.cancelAction)
                .disabled(appState.isSubmittingEndSession)
            }
        }
        .padding(10)
    }
}

private struct HardLimitExtendView: View {
    @ObservedObject var appState: CompanionAppState

    var body: some View {
        let mode = TimerPresentation.from(appState.timerService.snapshot).mode
        let title = "How much longer do you need?"
        let subtitle =
            mode == .timer
            ? "Choose a focused extension and keep working on the current task."
            : "Choose how many additional focus sessions you need."

        VStack(alignment: .leading, spacing: 12) {
            header(symbol: "plus.circle", title: title, subtitle: subtitle)

            VStack(spacing: 10) {
                ForEach(Array(choices(for: mode).enumerated()), id: \.element.id) { index, choice in
                    Button {
                        appState.hardLimitPopupExtendChoice = choice
                    } label: {
                        HStack {
                            Text(choice.title)
                                .font(.headline)
                                .foregroundStyle(PopupVisualTheme.primaryText)
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
                                .fill(
                                    PopupVisualTheme.primaryText.opacity(
                                        appState.hardLimitPopupExtendChoice == choice ? 0.1 : 0.05)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(PopupVisualTheme.border, lineWidth: 1)
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
        .padding(10)
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
            header(
                symbol: "checkmark.circle.fill", title: "Session Extended",
                subtitle: "The daemon accepted the extension and refreshed the timer.")

            VStack(spacing: 12) {
                successRow(title: "Time Remaining", value: success?.remainingTimeText ?? "—")
                successRow(title: "New End Time", value: success?.endTimeText ?? "—")
            }
            .padding(16)
            .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 14))

            Text("This popup will close automatically.")
                .font(.footnote)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
        }
        .padding(8)
    }

    private func successRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundStyle(PopupVisualTheme.primaryText)
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PopupVisualTheme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                ZStack(alignment: .leading) {
                    background(configuration.isPressed)
                    if let progress {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(PopupVisualTheme.primaryText.opacity(0.12))
                                .frame(width: geometry.size.width * min(1, max(0, progress)))
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(PopupVisualTheme.border, lineWidth: 0.8)
            )
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }

    private func background(_ isPressed: Bool) -> some View {
        let baseOpacity: Double
        switch style {
        case .primary:
            baseOpacity = isPressed ? 0.18 : 0.14
        case .secondary:
            baseOpacity = isPressed ? 0.11 : 0.08
        }

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(PopupVisualTheme.controlBackground.opacity(baseOpacity >= 0.14 ? 1 : 0.92))
    }
}

private struct InactivityPopupButtonStyle: ButtonStyle {
    var progress: Double? = nil

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

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
            .overlay(
                shape.strokeBorder(PopupVisualTheme.highlightedBorder, lineWidth: 0.8)
            )
            .clipShape(shape)
            .contentShape(shape)
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
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
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

private func popupCompactButtonLabel(
    title: String,
    detail: String? = nil,
    shortcut: String
) -> some View {
    ZStack {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            if let detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.48))
                    .lineLimit(1)
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

private func shortcutHint(_ shortcut: String) -> some View {
    Text(shortcut)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.5))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PopupVisualTheme.elevatedBackground)
        )
}

private func header(symbol: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
        Text(title)
            .font(.title2.weight(.semibold))
            .foregroundStyle(PopupVisualTheme.primaryText)
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.66))
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
}
