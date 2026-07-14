import Combine
import Foundation

enum MenuBarDisplayMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case iconOnly
    case iconAndText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly:
            return "Icon Only"
        case .iconAndText:
            return "Icon + Text"
        }
    }
}

enum MenuBarTimeFormat: String, Codable, Equatable, CaseIterable, Identifiable {
    case clock
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock:
            return "HH:MM:SS"
        case .expanded:
            return "HhMmSs"
        }
    }
}

struct CompanionPreferences: Codable, Equatable {
    var launchAtLogin = false
    var menuBarDisplayMode: MenuBarDisplayMode = .iconAndText
    var menuBarTimeFormat: MenuBarTimeFormat = .clock
    var menuBarShowsSeconds = true
    var pinPopover = false
    var runtimeDirectoryOverride: String?
    var tuiCommand = "crona"
}

@MainActor
final class PreferencesService: ObservableObject {
    private let defaults: UserDefaults
    private let key = "companion.preferences"

    @Published var preferences: CompanionPreferences {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(CompanionPreferences.self, from: data)
        {
            self.preferences = decoded
        } else {
            self.preferences = CompanionPreferences()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
