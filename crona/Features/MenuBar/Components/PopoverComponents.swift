import AppKit
import SwiftUI

struct GlassCapsuleBackground: View {
    let emphasis: Double
    @ObservedObject private var systemGlass = SystemGlassSettings.shared

    var body: some View {
        let shape = Capsule()

        Group {
            if systemGlass.reduceTransparency {
                shape
                    .fill(PopupVisualTheme.controlBackground)
                    .overlay(
                        shape
                            .strokeBorder(
                                PopupVisualTheme.primaryText.opacity(0.08), lineWidth: 0.5)
                    )
            } else if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        .clear.tint(
                            PopupVisualTheme.selectedControlBackground.opacity(max(0.08, emphasis))),
                        in: shape
                    )
            } else {
                VisualEffectView(material: .menu, blendingMode: .withinWindow, emphasized: false)
                    .clipShape(shape)
            }
        }
    }
}

struct SheetGlassBackground: View {
    var body: some View {
        PopoverDialogBackground(cornerRadius: 28)
    }
}

struct PopoverModalScrim: View {
    let onDismiss: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(.black.opacity(0.56))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(PopupVisualTheme.primaryText.opacity(0.015))
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }
}

struct PopoverGlassBackground: View {
    var cornerRadius: CGFloat = 28
    var showsShadow = true
    @ObservedObject private var systemGlass = SystemGlassSettings.shared

    var body: some View {
        let shellShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if systemGlass.reduceTransparency {
                shellShape.fill(PopupVisualTheme.popoverBackground)

                shellShape
                    .strokeBorder(PopupVisualTheme.border, lineWidth: 0.6)
            } else if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.interactive(false), in: shellShape)
            } else {
                VisualEffectView(
                    material: .hudWindow, blendingMode: .behindWindow, emphasized: false
                )
                .clipShape(shellShape)
            }
        }
        .shadow(
            color: showsShadow ? PopupVisualTheme.shadow : .clear,
            radius: showsShadow ? 14 : 0,
            y: showsShadow ? 7 : 0
        )
    }
}

struct PopoverDialogBackground: View {
    let cornerRadius: CGFloat
    @ObservedObject private var systemGlass = SystemGlassSettings.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if systemGlass.reduceTransparency {
                shape.fill(PopupVisualTheme.elevatedBackground)

                shape
                    .strokeBorder(PopupVisualTheme.border, lineWidth: 0.6)
            } else if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.interactive(false), in: shape)
            } else {
                VisualEffectView(material: .popover, blendingMode: .withinWindow, emphasized: true)
                    .clipShape(shape)
            }
        }
        .clipShape(shape)
    }
}

struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct OptionalKeyboardShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}

enum FocusConfigControl {
    case focus
    case shortBreak
    case longBreak
    case cycles
    case longBreakAfter
    case countdown
}

enum StatsLayout {
    static let sectionSpacing: CGFloat = 8
    static let gridSpacing: CGFloat = 8
    static let cardPadding: CGFloat = 11
    static let tilePadding: CGFloat = 10
    static let tileHeight: CGFloat = 64
    static let heroRingSize: CGFloat = 82
}

enum HabitDurationFormatter {
    static func string(from seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let remainingSeconds = clamped % 60
        return "\(hours)h\(minutes)m\(remainingSeconds)s"
    }

    static func seconds(from raw: String) -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        if value.contains(":") {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3,
                let hours = Int(parts[0]),
                let minutes = Int(parts[1]),
                let seconds = Int(parts[2]),
                (0...59).contains(minutes),
                (0...59).contains(seconds),
                hours >= 0
            else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        }

        let pattern = #"^\s*(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?\s*(?:(\d+)\s*s)?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            )
        else { return nil }

        let number: (Int) -> Int? = { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                let swiftRange = Range(range, in: value)
            else { return nil }
            return Int(value[swiftRange])
        }
        guard number(1) != nil || number(2) != nil || number(3) != nil else { return nil }
        let hours = number(1) ?? 0
        let minutes = number(2) ?? 0
        let seconds = number(3) ?? 0
        guard minutes <= 59, seconds <= 59 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
