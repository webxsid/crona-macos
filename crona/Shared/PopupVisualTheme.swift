import AppKit
import SwiftUI

enum PopupVisualTheme {
    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var sidebarBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    static var popoverBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var elevatedBackground: Color {
        Color.primary.opacity(0.08)
    }

    static var controlBackground: Color {
        Color.primary.opacity(0.08)
    }

    static var selectedControlBackground: Color {
        Color.accentColor.opacity(0.82)
    }

    static var selectedControlText: Color {
        NSColor.white.swiftUIColor
    }

    static var border: Color {
        Color.primary.opacity(0.16)
    }

    static var highlightedBorder: Color {
        Color.primary.opacity(0.28)
    }

    static var divider: Color {
        Color(nsColor: .separatorColor)
    }

    static var shadow: Color {
        Color.black.opacity(0.22)
    }

    static var primaryText: Color {
        .primary
    }

    static var secondaryText: Color {
        .secondary
    }

    static var tertiaryText: Color {
        Color.secondary.opacity(0.72)
    }

    static var surfaceFill: Color {
        Color.primary.opacity(0.055)
    }

    static var emphasizedSurfaceFill: Color {
        Color.primary.opacity(0.10)
    }

    static var surfaceStroke: Color {
        Color.primary.opacity(0.18)
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
