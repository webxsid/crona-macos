import SwiftUI

struct TimerHUDRootView: View {
    @ObservedObject var appState: CompanionAppState
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if appState.endSessionPresentationSource == .timerHUD {
                commitView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                timerView
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: appState.endSessionPresentationSource)
        .padding(8)
        .companionAppearance(appState)
    }

    private var timerView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentation = TimerPresentation.from(appState.timerService.snapshot, at: timeline.date)
            HStack(spacing: 12) {
                Image(systemName: presentation.phaseSymbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(presentation.mode == .stopwatch ? .yellow : .pink)

                VStack(alignment: .leading, spacing: 2) {
                    Text(MenuBarTextFormatter.formatClock(seconds: presentation.displaySeconds))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: presentation.mode != .stopwatch))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: presentation.displaySeconds)
                    Text(appState.contextService.snapshot.issueTitle ?? presentation.phaseTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isHovered {
                    HStack(spacing: 5) {
                        if presentation.canAdvance {
                            hudButton(presentation.advanceTitle ?? "Advance", symbol: "forward.fill", action: appState.advanceTimer)
                        }
                        if presentation.canPause {
                            hudButton("Pause", symbol: "pause.fill", action: appState.pauseTimer)
                        }
                        if presentation.canResume {
                            hudButton("Resume", symbol: "play.fill", action: appState.resumeTimer)
                        }
                        if presentation.canEnd {
                            hudButton("End", symbol: "stop.fill", action: appState.endTimerFromHUD)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, 15)
            .frame(width: 292, height: 72)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14)))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onHover { hovered in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { isHovered = hovered }
            }
        }
    }

    private var commitView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Finish session", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                Text(appState.contextService.snapshot.issueTitle ?? "Add a short note about what you completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit message")
                    .font(.subheadline.weight(.semibold))
                StableMultilineTextField(
                    text: $appState.endSessionCommitMessage,
                    placeholder: "Describe what you completed",
                    isEnabled: !appState.isSubmittingEndSession,
                    focusRequest: appState.endSessionFocusRequest
                )
                .frame(height: 116)
                .background(cardBackground(stroke: PopupVisualTheme.border, cornerRadius: 12))
            }

            if let error = appState.endSessionErrorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { appState.cancelEndSession() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(appState.isSubmittingEndSession)
                Spacer()
                Button {
                    appState.confirmEndSession()
                } label: {
                    if appState.isSubmittingEndSession {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("End Session")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(appState.isSubmittingEndSession)
            }
        }
        .padding(20)
        .frame(width: 380, height: 322, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.14)))
    }

    private func hudButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 27, height: 27)
                .background(Circle().fill(.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
