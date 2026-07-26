import Combine
import Foundation

enum MenuBarDisplayMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case iconOnly
    case textOnly
    case iconAndText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconOnly:
            return "Icon"
        case .textOnly:
            return "Text"
        case .iconAndText:
            return "Icon + Text"
        }
    }

    var showsIcon: Bool { self != .textOnly }
    var showsText: Bool { self != .iconOnly }
}

enum MenuBarIdleTextMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case idle
    case focusToday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .focusToday:
            return "Focus Today"
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
    static let hardLimitWarningLeadTimeOptions = [10, 20, 30]

    var launchAtLogin = false
    var menuBarDisplayMode: MenuBarDisplayMode = .iconAndText
    var menuBarIdleTextMode: MenuBarIdleTextMode = .idle
    var menuBarTimeFormat: MenuBarTimeFormat = .clock
    var menuBarShowsSeconds = true
    var showHardLimitActionPopups = true
    var showHardLimitWarningIndicator = true
    var hardLimitWarningLeadSeconds = 10
    var pinPopover = false
    var runtimeDirectoryOverride: String?
    var tuiCommand = "crona"

    static func normalizedHardLimitWarningLeadSeconds(_ value: Int) -> Int {
        hardLimitWarningLeadTimeOptions.min {
            abs($0 - value) < abs($1 - value)
        } ?? 10
    }
}

extension CompanionPreferences {
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case menuBarDisplayMode
        case menuBarIdleTextMode
        case menuBarTimeFormat
        case menuBarShowsSeconds
        case showHardLimitActionPopups
        case showHardLimitWarningIndicator
        case hardLimitWarningLeadSeconds
        case pinPopover
        case runtimeDirectoryOverride
        case tuiCommand
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        menuBarDisplayMode =
            try values.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode)
            ?? .iconAndText
        menuBarIdleTextMode =
            try values.decodeIfPresent(MenuBarIdleTextMode.self, forKey: .menuBarIdleTextMode)
            ?? .idle
        menuBarTimeFormat =
            try values.decodeIfPresent(MenuBarTimeFormat.self, forKey: .menuBarTimeFormat)
            ?? .clock
        menuBarShowsSeconds =
            try values.decodeIfPresent(Bool.self, forKey: .menuBarShowsSeconds)
            ?? true
        showHardLimitActionPopups =
            try values.decodeIfPresent(Bool.self, forKey: .showHardLimitActionPopups)
            ?? true
        showHardLimitWarningIndicator =
            try values.decodeIfPresent(Bool.self, forKey: .showHardLimitWarningIndicator)
            ?? true
        hardLimitWarningLeadSeconds =
            try values.decodeIfPresent(Int.self, forKey: .hardLimitWarningLeadSeconds)
            ?? 10
        pinPopover = try values.decodeIfPresent(Bool.self, forKey: .pinPopover) ?? false
        runtimeDirectoryOverride =
            try values.decodeIfPresent(String.self, forKey: .runtimeDirectoryOverride)
        tuiCommand = try values.decodeIfPresent(String.self, forKey: .tuiCommand) ?? "crona"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(launchAtLogin, forKey: .launchAtLogin)
        try values.encode(menuBarDisplayMode, forKey: .menuBarDisplayMode)
        try values.encode(menuBarIdleTextMode, forKey: .menuBarIdleTextMode)
        try values.encode(menuBarTimeFormat, forKey: .menuBarTimeFormat)
        try values.encode(menuBarShowsSeconds, forKey: .menuBarShowsSeconds)
        try values.encode(showHardLimitActionPopups, forKey: .showHardLimitActionPopups)
        try values.encode(showHardLimitWarningIndicator, forKey: .showHardLimitWarningIndicator)
        try values.encode(hardLimitWarningLeadSeconds, forKey: .hardLimitWarningLeadSeconds)
        try values.encode(pinPopover, forKey: .pinPopover)
        try values.encodeIfPresent(runtimeDirectoryOverride, forKey: .runtimeDirectoryOverride)
        try values.encode(tuiCommand, forKey: .tuiCommand)
    }
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
            var normalized = decoded
            normalized.hardLimitWarningLeadSeconds =
                CompanionPreferences.normalizedHardLimitWarningLeadSeconds(
                    decoded.hardLimitWarningLeadSeconds
                )
            self.preferences = normalized
        } else {
            self.preferences = CompanionPreferences()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
