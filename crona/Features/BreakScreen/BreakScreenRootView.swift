import AppKit
import SwiftUI

struct BreakScreenRootView: View {
    @ObservedObject var appState: CompanionAppState
    let screen: NSScreen
    let isPrimary: Bool

    private var service: BreakScreenService { appState.breakScreenService }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(at: timeline.date)
        }
    }

    private func content(at now: Date) -> some View {
        let presentation = TimerPresentation.from(service.snapshot, at: now)
        return ZStack {
            BreakScreenBackgroundView(
                preferences: service.currentPreferences,
                screen: screen,
                date: now
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

                    Text("Ends at \(endDate(presentation: presentation, now: now).formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                progressBar(presentation: presentation)
                    .frame(maxWidth: 460)

                contextBlock

                if isPrimary {
                    actionArea(now: now)
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

    private func endDate(presentation: TimerPresentation, now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(max(0, presentation.displaySeconds)))
    }

    private func progressBar(presentation: TimerPresentation) -> some View {
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
    private func actionArea(now: Date) -> some View {
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
                let remaining = service.strictDelayRemaining(at: now)
                Button(
                    remaining > 0
                        ? "Skip in \(remaining)s"
                        : "Skip Break",
                    action: service.skipBreak
                )
                .buttonStyle(BreakScreenPrimaryButtonStyle())
                .disabled(!service.canSkip(at: now))
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
    let date: Date

    var body: some View {
        ZStack {
            switch preferences.breakScreenBackgroundStyle {
            case .systemWallpaper:
                wallpaper
            case .solidColor:
                Color(rgba: preferences.breakScreenSolidColor)
            case .gradient:
                animatedAbstractBackground(preferences.breakScreenGradientPreset, at: date)
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
            animatedAbstractBackground(.graphite, at: date)
        }
    }

    private func animatedAbstractBackground(_ preset: BreakScreenGradientPreset, at date: Date) -> some View {
        GeometryReader { proxy in
            let theme = theme(for: preset)
            let phase = date.timeIntervalSinceReferenceDate / 10.5

            ZStack {
                LinearGradient(
                    colors: theme.background,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ForEach(Array(theme.blobs.enumerated()), id: \.offset) { _, blob in
                    let flowPhase = phase * blob.speed + blob.phase
                    let secondaryPhase = phase * (blob.speed * 0.78) + blob.phase * 1.18
                    let x = proxy.size.width * blob.anchorX
                        + cos(flowPhase) * blob.driftX
                    let y = proxy.size.height * blob.anchorY
                        + sin(secondaryPhase) * blob.driftY
                    let stretchX = 1 + sin(phase * (blob.speed * 0.42) + blob.phase * 1.24) * 0.09
                    let stretchY = 1 + cos(phase * (blob.speed * 0.35) + blob.phase * 1.64) * 0.07
                    let trailX = cos(flowPhase + 0.8) * blob.driftX * 0.35
                    let trailY = sin(secondaryPhase + 1.1) * blob.driftY * 0.28

                    ZStack {
                        Ellipse()
                            .fill(blob.color.opacity(0.34))
                            .frame(width: blob.size.width * 1.16, height: blob.size.height * 1.16)
                            .blur(radius: blob.blur * 1.18)
                            .scaleEffect(x: stretchX * 1.05, y: stretchY * 1.03)
                            .offset(x: trailX, y: trailY)

                        Ellipse()
                            .fill(blob.color)
                            .frame(width: blob.size.width, height: blob.size.height)
                            .blur(radius: blob.blur)
                            .scaleEffect(x: stretchX, y: stretchY)
                    }
                    .rotationEffect(.degrees(blob.rotationDegrees + phase * blob.spin))
                    .blendMode(blob.blendMode)
                    .position(x: x, y: y)
                }

                LinearGradient(
                    colors: [
                        .white.opacity(0.08),
                        .clear,
                        .black.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [.clear, .black.opacity(0.22)],
                    center: .center,
                    startRadius: max(proxy.size.width, proxy.size.height) * 0.05,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.92
                )
            }
            .compositingGroup()
        }
    }

    private func theme(for preset: BreakScreenGradientPreset) -> BreakScreenGradientTheme {
        switch preset {
        case .graphite:
            return .graphite
        case .ocean:
            return .ocean
        case .forest:
            return .forest
        case .ember:
            return .ember
        case .dawn:
            return .dawn
        }
    }
}

#if DEBUG
struct DeveloperBreakScreenRootView: View {
    @ObservedObject var appState: CompanionAppState
    let screen: NSScreen

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ZStack {
                BreakScreenBackgroundView(
                    preferences: appState.preferences.preferences,
                    screen: screen,
                    date: timeline.date
                )

                VStack(spacing: 28) {
                    Spacer()

                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))

                    VStack(spacing: 10) {
                        Text("Short Break")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                        Text("05:00")
                            .font(.system(size: 86, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("Ends at \(timeline.date.addingTimeInterval(300).formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    Capsule()
                        .fill(.white.opacity(0.46))
                        .frame(width: 460, height: 5)

                    VStack(spacing: 8) {
                        Text("Developer preview")
                            .font(.title3.weight(.semibold))
                        Text("Crona • Focus")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.54))
                    }

                    Button("Dismiss Preview") {
                        appState.dismissDeveloperPreviews()
                    }
                    .buttonStyle(BreakScreenSecondaryButtonStyle())

                    Spacer()
                }
                .padding(48)
                .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
    }
}
#endif

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

private struct BreakScreenGradientTheme {
    let background: [Color]
    let blobs: [BreakScreenGradientBlob]

    static let graphite = BreakScreenGradientTheme(
        background: [
            Color(red: 0.045, green: 0.055, blue: 0.08),
            Color(red: 0.08, green: 0.095, blue: 0.13),
            Color(red: 0.16, green: 0.18, blue: 0.22)
        ],
        blobs: [
            .init(color: Color(red: 0.42, green: 0.47, blue: 0.62, opacity: 0.42), anchorX: 0.2, anchorY: 0.18, size: CGSize(width: 610, height: 220), blur: 92, driftX: 64, driftY: 30, rotation: -16, spin: 9, phase: 0.2, cornerRadius: 180, blendMode: .screen, speed: 0.72),
            .init(color: Color(red: 0.18, green: 0.22, blue: 0.32, opacity: 0.5), anchorX: 0.76, anchorY: 0.7, size: CGSize(width: 520, height: 210), blur: 104, driftX: 52, driftY: 28, rotation: 24, spin: -7, phase: 1.45, cornerRadius: 170, blendMode: .plusLighter, speed: 0.58)
        ]
    )

    static let ocean = BreakScreenGradientTheme(
        background: [
            Color(red: 0.025, green: 0.09, blue: 0.16),
            Color(red: 0.04, green: 0.18, blue: 0.28),
            Color(red: 0.08, green: 0.35, blue: 0.44)
        ],
        blobs: [
            .init(color: Color(red: 0.15, green: 0.78, blue: 0.92, opacity: 0.38), anchorX: 0.16, anchorY: 0.18, size: CGSize(width: 640, height: 210), blur: 96, driftX: 66, driftY: 30, rotation: -10, spin: 8, phase: 0.4, cornerRadius: 180, blendMode: .screen, speed: 0.68),
            .init(color: Color(red: 0.05, green: 0.9, blue: 0.66, opacity: 0.24), anchorX: 0.76, anchorY: 0.7, size: CGSize(width: 540, height: 200), blur: 102, driftX: 48, driftY: 26, rotation: 18, spin: -9, phase: 1.65, cornerRadius: 168, blendMode: .plusLighter, speed: 0.82)
        ]
    )

    static let forest = BreakScreenGradientTheme(
        background: [
            Color(red: 0.03, green: 0.09, blue: 0.08),
            Color(red: 0.05, green: 0.16, blue: 0.12),
            Color(red: 0.17, green: 0.34, blue: 0.27)
        ],
        blobs: [
            .init(color: Color(red: 0.18, green: 0.62, blue: 0.35, opacity: 0.34), anchorX: 0.18, anchorY: 0.18, size: CGSize(width: 620, height: 220), blur: 94, driftX: 58, driftY: 32, rotation: -18, spin: 9, phase: 0.7, cornerRadius: 176, blendMode: .screen, speed: 0.7),
            .init(color: Color(red: 0.3, green: 0.8, blue: 0.48, opacity: 0.2), anchorX: 0.74, anchorY: 0.72, size: CGSize(width: 520, height: 190), blur: 98, driftX: 42, driftY: 24, rotation: 14, spin: -7, phase: 1.85, cornerRadius: 162, blendMode: .plusLighter, speed: 0.84)
        ]
    )

    static let ember = BreakScreenGradientTheme(
        background: [
            Color(red: 0.12, green: 0.03, blue: 0.06),
            Color(red: 0.2, green: 0.07, blue: 0.1),
            Color(red: 0.52, green: 0.2, blue: 0.15)
        ],
        blobs: [
            .init(color: Color(red: 0.98, green: 0.36, blue: 0.12, opacity: 0.38), anchorX: 0.18, anchorY: 0.2, size: CGSize(width: 620, height: 220), blur: 92, driftX: 60, driftY: 30, rotation: -14, spin: 10, phase: 0.3, cornerRadius: 176, blendMode: .screen, speed: 0.76),
            .init(color: Color(red: 1.0, green: 0.74, blue: 0.34, opacity: 0.18), anchorX: 0.76, anchorY: 0.72, size: CGSize(width: 540, height: 190), blur: 100, driftX: 44, driftY: 24, rotation: 20, spin: -8, phase: 1.55, cornerRadius: 164, blendMode: .plusLighter, speed: 0.88)
        ]
    )

    static let dawn = BreakScreenGradientTheme(
        background: [
            Color(red: 0.08, green: 0.06, blue: 0.16),
            Color(red: 0.18, green: 0.11, blue: 0.24),
            Color(red: 0.58, green: 0.3, blue: 0.36)
        ],
        blobs: [
            .init(color: Color(red: 0.9, green: 0.45, blue: 0.88, opacity: 0.3), anchorX: 0.18, anchorY: 0.2, size: CGSize(width: 630, height: 220), blur: 94, driftX: 60, driftY: 30, rotation: -12, spin: 8, phase: 0.5, cornerRadius: 178, blendMode: .screen, speed: 0.78),
            .init(color: Color(red: 0.98, green: 0.72, blue: 0.45, opacity: 0.22), anchorX: 0.76, anchorY: 0.72, size: CGSize(width: 540, height: 190), blur: 100, driftX: 44, driftY: 24, rotation: 18, spin: -9, phase: 1.72, cornerRadius: 164, blendMode: .plusLighter, speed: 0.86)
        ]
    )
}

private struct BreakScreenGradientBlob {
    let color: Color
    let anchorX: CGFloat
    let anchorY: CGFloat
    let size: CGSize
    let blur: CGFloat
    let driftX: CGFloat
    let driftY: CGFloat
    let rotationDegrees: Double
    let spin: Double
    let phase: Double
    let cornerRadius: CGFloat
    let blendMode: BlendMode
    let speed: Double

    init(
        color: Color,
        anchorX: CGFloat,
        anchorY: CGFloat,
        size: CGSize,
        blur: CGFloat,
        driftX: CGFloat,
        driftY: CGFloat,
        rotation: Double,
        spin: Double,
        phase: Double,
        cornerRadius: CGFloat,
        blendMode: BlendMode,
        speed: Double
    ) {
        self.color = color
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.size = size
        self.blur = blur
        self.driftX = driftX
        self.driftY = driftY
        self.rotationDegrees = rotation
        self.spin = spin
        self.phase = phase
        self.cornerRadius = cornerRadius
        self.blendMode = blendMode
        self.speed = speed
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
