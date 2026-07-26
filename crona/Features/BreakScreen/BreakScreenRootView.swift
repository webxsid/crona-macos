import AppKit
import SwiftUI

struct BreakScreenRootView: View {
    @ObservedObject var appState: CompanionAppState
    let screen: NSScreen
    let isPrimary: Bool

    private var service: BreakScreenService { appState.breakScreenService }
    private var presentation: TimerPresentation {
        TimerPresentation.from(service.snapshot)
    }

    var body: some View {
        ZStack {
            BreakScreenBackgroundView(
                preferences: service.currentPreferences,
                screen: screen
            )

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: segment?.isBreak == true ? "cup.and.saucer.fill" : "sun.max.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 10) {
                    Text(segment == .longBreak ? "Long Break" : "Short Break")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(durationText(presentation.displaySeconds))
                        .font(.system(size: 86, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))

                    Text("Ends at \(endDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                progressBar
                    .frame(maxWidth: 460)

                contextBlock

                if isPrimary {
                    actionArea
                        .frame(maxWidth: 360)
                }

                Spacer()
            }
            .padding(48)
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }

    private var segment: TimerSegmentKind? {
        service.segment ?? TimerPresentation.activeSegment(for: service.snapshot)
    }

    private var endDate: Date {
        Date().addingTimeInterval(TimeInterval(max(0, presentation.displaySeconds)))
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let progress = max(0, min(1, presentation.progressFraction ?? 0))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(.white.opacity(0.46))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 5)
        .accessibilityValue("\(Int((presentation.progressFraction ?? 0) * 100)) percent remaining")
    }

    private var contextBlock: some View {
        let context = appState.contextService.snapshot
        return VStack(spacing: 8) {
            Text(context.issueTitle ?? "Step away for a moment")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 7) {
                if let repo = context.repoName {
                    Text(repo)
                }
                if context.repoName != nil, context.streamName != nil {
                    Text("•")
                }
                if let stream = context.streamName {
                    Text(stream)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private var actionArea: some View {
        if service.phase == .recovery {
            VStack(spacing: 12) {
                Text("Crona couldn’t continue the timer.")
                    .font(.subheadline.weight(.semibold))
                if let message = service.recoveryMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                }
                Button("Retry", action: service.retryTransition)
                    .buttonStyle(BreakScreenPrimaryButtonStyle())
                Button("Dismiss Screen", action: service.dismissRecovery)
                    .buttonStyle(BreakScreenSecondaryButtonStyle())
            }
        } else {
            switch service.currentPreferences.breakScreenMode {
            case .easy:
                Button("Skip Break", action: service.skipBreak)
                    .buttonStyle(BreakScreenPrimaryButtonStyle())
                    .disabled(!service.canSkip)
            case .strict:
                Button(
                    service.strictDelayRemaining > 0
                        ? "Skip in \(service.strictDelayRemaining)s"
                        : "Skip Break",
                    action: service.skipBreak
                )
                .buttonStyle(BreakScreenPrimaryButtonStyle())
                .disabled(!service.canSkip)
            case .hard:
                Label("Your break ends automatically", systemImage: "lock.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.vertical, 12)
            }
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let remainingSeconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

struct BreakScreenBackgroundView: View {
    let preferences: CompanionPreferences
    let screen: NSScreen?

    var body: some View {
        ZStack {
            switch preferences.breakScreenBackgroundStyle {
            case .systemWallpaper:
                wallpaper
            case .solidColor:
                Color(rgba: preferences.breakScreenSolidColor)
            case .gradient:
                presetGradient(preferences.breakScreenGradientPreset)
            }

            LinearGradient(
                colors: [.black.opacity(0.2), .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var wallpaper: some View {
        if
            let screen,
            let url = NSWorkspace.shared.desktopImageURL(for: screen),
            let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            presetGradient(.graphite)
        }
    }

    private func presetGradient(_ preset: BreakScreenGradientPreset) -> LinearGradient {
        let colors: [Color]
        switch preset {
        case .graphite:
            colors = [Color(red: 0.055, green: 0.07, blue: 0.1), Color(red: 0.16, green: 0.18, blue: 0.22)]
        case .ocean:
            colors = [Color(red: 0.04, green: 0.13, blue: 0.23), Color(red: 0.08, green: 0.35, blue: 0.44)]
        case .forest:
            colors = [Color(red: 0.04, green: 0.14, blue: 0.11), Color(red: 0.17, green: 0.34, blue: 0.27)]
        case .ember:
            colors = [Color(red: 0.2, green: 0.07, blue: 0.1), Color(red: 0.52, green: 0.2, blue: 0.15)]
        case .dawn:
            colors = [Color(red: 0.18, green: 0.11, blue: 0.24), Color(red: 0.58, green: 0.3, blue: 0.36)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct BreakScreenPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(.white.opacity(configuration.isPressed ? 0.72 : 0.9))
            .foregroundStyle(.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

private struct BreakScreenSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0.12))
            .foregroundStyle(.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

extension Color {
    init(rgba: CompanionRGBAColor) {
        self.init(
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            opacity: rgba.alpha
        )
    }
}

extension CompanionRGBAColor {
    init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.init(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent),
            alpha: Double(color.alphaComponent)
        )
    }
}
