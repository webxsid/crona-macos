import SwiftUI

enum CronaIssueStatusColor: String, Equatable {
    case subtle, blue, cyan, yellow, red, magenta, green

    var color: Color {
        switch self {
        case .subtle: return PopupVisualTheme.secondaryText
        case .blue: return .blue
        case .cyan: return .cyan
        case .yellow: return .yellow
        case .red: return .red
        case .magenta: return .purple
        case .green: return .green
        }
    }
}

enum CronaIssueStatusPresentation {
    static func status(for rawValue: String) -> CronaIssueStatus? {
        switch rawValue {
        case "todo": return .backlog
        case "active": return .inProgress
        default: return CronaIssueStatus(rawValue: rawValue)
        }
    }

    static func icon(for rawValue: String) -> String {
        status(for: rawValue)?.systemImage ?? "circle"
    }

    static func colorKey(for rawValue: String) -> CronaIssueStatusColor {
        switch status(for: rawValue) {
        case .backlog, nil: return .subtle
        case .planned: return .blue
        case .ready: return .cyan
        case .inProgress: return .yellow
        case .blocked, .abandoned: return .red
        case .inReview: return .magenta
        case .done: return .green
        }
    }

    static func color(for rawValue: String) -> Color {
        colorKey(for: rawValue).color
    }
}
