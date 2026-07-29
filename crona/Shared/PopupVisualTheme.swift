import AppKit
import SwiftUI

enum PopupVisualTheme {
    static var windowBackground: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1),
            dark: NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.12, alpha: 1)
        )
    }

    static var sidebarBackground: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.91, green: 0.91, blue: 0.93, alpha: 1),
            dark: NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        )
    }

    static var popoverBackground: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.98, alpha: 1),
            dark: NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        )
    }

    static var cardBackground: Color {
        dynamic(
            light: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            dark: NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.19, alpha: 1)
        )
    }

    static var elevatedBackground: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.985, green: 0.985, blue: 0.99, alpha: 1),
            dark: NSColor(calibratedRed: 0.205, green: 0.205, blue: 0.225, alpha: 1)
        )
    }

    static var controlBackground: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.91, green: 0.91, blue: 0.93, alpha: 1),
            dark: NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.245, alpha: 1)
        )
    }

    static var selectedControlBackground: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.15, green: 0.43, blue: 0.92, alpha: 1),
            dark: NSColor(calibratedRed: 0.22, green: 0.46, blue: 0.92, alpha: 1)
        )
    }

    static var selectedControlText: Color {
        NSColor.white.swiftUIColor
    }

    static var border: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.78, green: 0.78, blue: 0.82, alpha: 1),
            dark: NSColor(calibratedRed: 0.30, green: 0.30, blue: 0.34, alpha: 1)
        )
    }

    static var highlightedBorder: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.62, green: 0.62, blue: 0.68, alpha: 1),
            dark: NSColor(calibratedRed: 0.42, green: 0.42, blue: 0.48, alpha: 1)
        )
    }

    static var divider: Color {
        dynamic(
            light: NSColor(calibratedRed: 0.78, green: 0.78, blue: 0.82, alpha: 0.8),
            dark: NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.28, alpha: 0.9)
        )
    }

    static var shadow: Color {
        dynamic(
            light: NSColor(calibratedWhite: 0.0, alpha: 0.16),
            dark: NSColor(calibratedWhite: 0.0, alpha: 0.42)
        )
    }

    static var primaryText: Color {
        dynamic(light: NSColor(calibratedWhite: 0.10, alpha: 1), dark: NSColor(calibratedWhite: 0.96, alpha: 1))
    }

    static var secondaryText: Color {
        dynamic(light: NSColor(calibratedWhite: 0.32, alpha: 1), dark: NSColor(calibratedWhite: 0.72, alpha: 1))
    }

    static var tertiaryText: Color {
        dynamic(light: NSColor(calibratedWhite: 0.47, alpha: 1), dark: NSColor(calibratedWhite: 0.52, alpha: 1))
    }

    static var surfaceFill: Color {
        dynamic(light: NSColor(calibratedWhite: 0.0, alpha: 0.055), dark: NSColor(calibratedWhite: 1.0, alpha: 0.08))
    }

    static var emphasizedSurfaceFill: Color {
        dynamic(light: NSColor(calibratedWhite: 0.0, alpha: 0.10), dark: NSColor(calibratedWhite: 1.0, alpha: 0.14))
    }

    static var surfaceStroke: Color {
        dynamic(light: NSColor(calibratedWhite: 0.0, alpha: 0.16), dark: NSColor(calibratedWhite: 1.0, alpha: 0.18))
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    var swiftUIColor: Color { Color(nsColor: self) }
}

struct CompanionAppearanceModifier: ViewModifier {
    @ObservedObject var appState: CompanionAppState
    @Environment(\.colorScheme) private var systemColorScheme

    func body(content: Content) -> some View {
        content.environment(
            \.colorScheme,
            appState.preferences.preferences.appearance.resolvedColorScheme(using: systemColorScheme)
        )
    }
}

extension View {
    func companionAppearance(_ appState: CompanionAppState) -> some View {
        modifier(CompanionAppearanceModifier(appState: appState))
    }
}
