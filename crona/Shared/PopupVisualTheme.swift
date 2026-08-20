import AppKit
import SwiftUI

enum PopupVisualTheme {
    enum SemanticColor {
        case focus
        case breakTime
        case success
        case warning
        case error
        case info
        case planned
        case inProgress
        case review
        case away
        case mood
        case energy
        case stats
    }

    static func semantic(_ role: SemanticColor) -> Color {
        let color: NSColor
        switch role {
        case .focus, .warning, .inProgress, .energy:
            color = .systemYellow
        case .breakTime, .mood:
            color = .systemPink
        case .success, .away:
            color = .systemGreen
        case .error:
            color = .systemRed
        case .info, .planned:
            color = .systemBlue
        case .review, .stats:
            color = .systemPurple
        }
        return Color(nsColor: color)
    }

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
        Color(nsColor: .alternateSelectedControlTextColor)
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
        Color(nsColor: .shadowColor).opacity(0.42)
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

    static var modalScrim: Color {
        Color.black.opacity(0.56)
    }

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
