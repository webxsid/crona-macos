import AppKit
import SwiftUI

extension TimerHUDSize {
    var panelSize: CGSize {
        switch self {
        case .compact: CGSize(width: 220, height: 64)
        case .regular: CGSize(width: 264, height: 76)
        case .spacious: CGSize(width: 308, height: 88)
        }
    }

    var contentSize: CGSize {
        switch self {
        case .compact: CGSize(width: 204, height: 48)
        case .regular: CGSize(width: 248, height: 60)
        case .spacious: CGSize(width: 292, height: 72)
        }
    }

    var clockFontSize: CGFloat {
        switch self {
        case .compact: 18
        case .regular: 20
        case .spacious: 23
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 10
        case .regular: 12
        case .spacious: 15
        }
    }
}

struct TimerHUDRootView: View {
    @ObservedObject var appState: CompanionAppState
    var size: TimerHUDSize = .spacious
    var isPreview = false
    @State private var isHovered = false
    @State private var dragGrabOffset: CGPoint?
    @State private var isDragging = false
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
            HStack(spacing: size == .compact ? 8 : 12) {
                Image(systemName: presentation.phaseSymbolName)
                    .font(.system(size: size == .compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(presentation.mode == .stopwatch ? .yellow : .pink)

                VStack(alignment: .leading, spacing: 2) {
                    Text(MenuBarTextFormatter.formatClock(seconds: presentation.displaySeconds))
                        .font(.system(size: size.clockFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: presentation.mode != .stopwatch))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: presentation.displaySeconds)
                    if size != .compact {
                        Text(appState.contextService.snapshot.issueTitle ?? presentation.phaseTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: size == .compact ? 0 : 4)
                if isHovered || size != .compact { hudActions(for: presentation) }
            }
            .padding(.horizontal, size.horizontalPadding)
            .frame(width: size.contentSize.width, height: size.contentSize.height)
            .background(PopoverGlassBackground(cornerRadius: 20, showsShadow: false))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.14))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onHover { hovered in
                guard !isDragging else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    isHovered = hovered
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { _ in
                        guard !isPreview,
                              let panel = timerHUDPanel
                        else { return }
                        if dragGrabOffset == nil {
                            let mouseLocation = NSEvent.mouseLocation
                            dragGrabOffset = CGPoint(
                                x: mouseLocation.x - panel.frame.origin.x,
                                y: mouseLocation.y - panel.frame.origin.y
                            )
                        }
                        isDragging = true
                        guard let dragGrabOffset else { return }
                        let mouseLocation = NSEvent.mouseLocation
                        panel.setFrameOrigin(
                            NSPoint(
                                x: mouseLocation.x - dragGrabOffset.x,
                                y: mouseLocation.y - dragGrabOffset.y
                            )
                        )
                    }
                    .onEnded { _ in
                        dragGrabOffset = nil
                        isDragging = false
                    }
            )
            .allowsHitTesting(!isPreview)
        }
    }

    private var timerHUDPanel: NSPanel? {
        NSApp.windows.first {
            $0.identifier?.rawValue == "com.crona.timer-hud" && $0.isVisible
        } as? NSPanel
    }

    @ViewBuilder
    private func hudActions(for presentation: TimerPresentation) -> some View {
        if isHovered || isPreview {
            HStack(spacing: size == .compact ? 2 : 5) {
                if presentation.canAdvance { hudButton(presentation.advanceTitle ?? "Advance", symbol: "forward.fill", action: appState.advanceTimer) }
                if presentation.canPause { hudButton("Pause", symbol: "pause.fill", action: appState.pauseTimer) }
                if presentation.canResume { hudButton("Resume", symbol: "play.fill", action: appState.resumeTimer) }
                if presentation.canEnd { hudButton("End", symbol: "stop.fill", action: appState.endTimerFromHUD) }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var commitView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(.green.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish session")
                        .font(.title3.weight(.semibold))
                Text(appState.contextService.snapshot.issueTitle ?? "Add a short note about what you completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
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
                .popupInputSurface(cornerRadius: 12)
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
        .background(PopoverGlassBackground(cornerRadius: 22, showsShadow: false))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
    }

    private func hudButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size == .compact ? 9 : 11, weight: .bold))
                .frame(width: size == .compact ? 22 : 27, height: size == .compact ? 22 : 27)
                .background(Circle().fill(.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
