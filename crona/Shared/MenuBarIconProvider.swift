import AppKit
import CoreGraphics

enum MenuBarIconState: Equatable {
    case idle
    case focus(progress: Double)
    case paused(progress: Double)
    case breakTime(progress: Double?)
    case connecting
    case offline
    case error
    case completed

    static func resolve(
        connectionState: CompanionConnectionState,
        timerSnapshot: TimerSnapshot,
        now: Date = Date(),
        includeCompletion: Bool = true
    ) -> Self {
        switch connectionState {
        case .error, .incompatible:
            return .error
        case .disconnected:
            return .offline
        case .idle, .connecting:
            return .connecting
        case .connected:
            break
        }

        guard timerSnapshot.sessionID != nil else { return .idle }
        if timerSnapshot.hardLimitExpired {
            return includeCompletion ? .completed : .idle
        }

        let presentation = TimerPresentation.from(timerSnapshot, at: now)
        let progress = progress(for: timerSnapshot, presentation: presentation, at: now)

        if timerSnapshot.state == "paused" {
            return .paused(progress: progress)
        }
        if TimerSegmentKind(rawValue: timerSnapshot.segmentType)?.isBreak == true {
            return .breakTime(progress: presentation.progressFraction)
        }
        return .focus(progress: progress)
    }

    var isProgressState: Bool {
        switch self {
        case .focus, .paused, .breakTime:
            return true
        case .idle, .connecting, .offline, .error, .completed:
            return false
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .idle:
            return "Crona - Idle"
        case .focus:
            return "Crona - Focus session"
        case .paused:
            return "Crona - Session paused"
        case .breakTime:
            return "Crona - Break in progress"
        case .connecting:
            return "Crona - Connecting"
        case .offline:
            return "Crona - Kernel offline"
        case .error:
            return "Crona - Error"
        case .completed:
            return "Crona - Session completed"
        }
    }

    func accessibilityDescription(for snapshot: TimerSnapshot, at now: Date = Date()) -> String {
        switch self {
        case .focus:
            let seconds = TimerPresentation.projectedDisplaySeconds(for: snapshot, at: now)
            let qualifier = snapshot.hardLimitActive ? "remaining" : "elapsed"
            return "Crona - Focus session, \(MenuBarTextFormatter.formatAdaptive(seconds: seconds)) \(qualifier)"
        case .paused:
            return "Crona - Session paused"
        default:
            return accessibilityDescription
        }
    }

    private static func progress(
        for snapshot: TimerSnapshot,
        presentation: TimerPresentation,
        at now: Date
    ) -> Double {
        if let progress = presentation.progressFraction {
            return clamp(progress)
        }

        let elapsed = TimerPresentation.projectedDisplaySeconds(for: snapshot, at: now)
        return Double(max(0, elapsed) % 60) / 60
    }

    static func clamp(_ progress: Double) -> Double {
        min(1, max(0, progress.isFinite ? progress : 0))
    }
}

struct CronaMenuBarIconRenderer {
    private static let canvasSize = CGSize(width: 18, height: 18)
    private static let center = CGPoint(x: 9, y: 9)
    private static let radius: CGFloat = 5.7
    private static let strokeWidth: CGFloat = 2.25
    private static let arcLength = CGFloat.pi * 1.5 * radius

    private let cache = NSCache<NSString, NSImage>()

    func image(for state: MenuBarIconState, connectingPhase: Double = 0) -> NSImage {
        let key = cacheKey(for: state, connectingPhase: connectingPhase) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = render(state: state, connectingPhase: connectingPhase)
        cache.setObject(image, forKey: key)
        return image
    }

    private func render(state: MenuBarIconState, connectingPhase: Double) -> NSImage {
        let image = NSImage(size: Self.canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else { return image }
        context.saveGState()
        defer { context.restoreGState() }

        let path = Self.cPath()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch state {
        case .idle:
            stroke(context, path: path, width: Self.strokeWidth, alpha: 1)
        case .focus(let progress):
            drawProgress(context, path: path, progress: progress)
        case .paused(let progress):
            drawProgress(context, path: path, progress: progress)
            drawPauseGlyph(context)
        case .breakTime(let progress):
            drawBreak(context, path: path, progress: progress)
        case .connecting:
            stroke(context, path: path, width: Self.strokeWidth, alpha: 0.25)
            let phase = Self.arcLength * Self.normalizedPhase(connectingPhase)
            context.setLineDash(
                phase: phase,
                lengths: [Self.arcLength * 0.28, Self.arcLength * 0.72]
            )
            stroke(context, path: path, width: Self.strokeWidth, alpha: 1)
        case .offline:
            stroke(context, path: path, width: Self.strokeWidth, alpha: 1)
            drawSlash(context)
        case .error:
            stroke(context, path: path, width: Self.strokeWidth, alpha: 1)
            drawErrorGlyph(context)
        case .completed:
            stroke(context, path: path, width: 3.1, alpha: 1)
            drawCompletionGlyph(context)
        }

        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }

    private func drawProgress(_ context: CGContext, path: CGPath, progress: Double) {
        let clamped = MenuBarIconState.clamp(progress)
        stroke(context, path: path, width: Self.strokeWidth, alpha: 0.22)
        guard clamped > 0 else { return }
        context.setLineDash(
            phase: 0,
            lengths: [Self.arcLength * clamped, Self.arcLength * 2]
        )
        stroke(context, path: path, width: Self.strokeWidth, alpha: 1)
    }

    private func drawBreak(_ context: CGContext, path: CGPath, progress: Double?) {
        stroke(context, path: path, width: Self.strokeWidth, alpha: 0.38)
        guard let progress else { return }
        let clamped = MenuBarIconState.clamp(progress)
        context.setLineDash(
            phase: 0,
            lengths: [Self.arcLength * clamped, Self.arcLength * 2]
        )
        stroke(context, path: path, width: Self.strokeWidth, alpha: 0.75)
    }

    private func stroke(_ context: CGContext, path: CGPath, width: CGFloat, alpha: CGFloat) {
        context.saveGState()
        context.setLineWidth(width)
        context.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private func drawPauseGlyph(_ context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 7.35, y: 6.25, width: 1.15, height: 5.5))
        context.fill(CGRect(x: 9.5, y: 6.25, width: 1.15, height: 5.5))
        context.restoreGState()
    }

    private func drawErrorGlyph(_ context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.35)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 9, y: 6.1))
        context.addLine(to: CGPoint(x: 9, y: 10.4))
        context.strokePath()
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: CGRect(x: 8.35, y: 4.25, width: 1.3, height: 1.3))
        context.restoreGState()
    }

    private func drawSlash(_ context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.35)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 4.5, y: 4.5))
        context.addLine(to: CGPoint(x: 13.5, y: 13.5))
        context.strokePath()
        context.restoreGState()
    }

    private func drawCompletionGlyph(_ context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.35)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: 6.65, y: 9))
        context.addLine(to: CGPoint(x: 8.35, y: 7.35))
        context.addLine(to: CGPoint(x: 11.6, y: 10.65))
        context.strokePath()
        context.restoreGState()
    }

    private static func cPath() -> CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .pi / 4,
            endAngle: .pi * 7 / 4,
            clockwise: false
        )
        return path
    }

    private func cacheKey(for state: MenuBarIconState, connectingPhase: Double) -> String {
        switch state {
        case .focus(let progress):
            return "focus-\(quantized(progress))"
        case .paused(let progress):
            return "paused-\(quantized(progress))"
        case .breakTime(let progress):
            let progressKey = progress.map(quantized) ?? "none"
            return "break-\(progressKey)"
        case .connecting:
            return "connecting-\(quantizedPhase(connectingPhase))"
        case .idle:
            return "idle"
        case .offline:
            return "offline"
        case .error:
            return "error"
        case .completed:
            return "completed"
        }
    }

    private func quantized(_ value: Double) -> String {
        String(format: "%.2f", MenuBarIconState.clamp(value))
    }

    private func quantizedPhase(_ value: Double) -> String {
        String(format: "%.2f", Self.normalizedPhase(value))
    }

    private static func normalizedPhase(_ value: Double) -> Double {
        let phase = value.truncatingRemainder(dividingBy: 1)
        return phase >= 0 ? phase : phase + 1
    }
}

enum MenuBarIconProvider {
    private static let renderer = CronaMenuBarIconRenderer()

    static func image(for state: MenuBarIconState, connectingPhase: Double = 0) -> NSImage {
        renderer.image(for: state, connectingPhase: connectingPhase)
    }
}
