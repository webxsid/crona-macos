import Combine
import Foundation
import SwiftUI

enum AppReleaseChannel: String, Codable, Equatable, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static func inferred(from version: String) -> Self {
        version.lowercased().contains("-beta") ? .beta : .stable
    }

    static func resolved(configuredValue: String?, version: String) -> Self {
        configuredValue.flatMap(Self.init(rawValue:)) ?? inferred(from: version)
    }
}

enum CompanionAppearance: String, Codable, Equatable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    func resolvedColorScheme(using systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum BreakScreenMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case easy
    case strict
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Easy"
        case .strict: return "Strict"
        case .hard: return "Hard"
        }
    }
}

enum BreakScreenActivityDeferral: String, Codable, Equatable, CaseIterable, Identifiable {
    case off
    case easyAndStrict
    case allModes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .easyAndStrict: return "Easy and Strict"
        case .allModes: return "All modes"
        }
    }
}

enum BreakScreenBackgroundStyle: String, Codable, Equatable, CaseIterable, Identifiable {
    case systemWallpaper
    case solidColor
    case gradient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemWallpaper: return "Wallpaper"
        case .solidColor: return "Color"
        case .gradient: return "Gradient"
        }
    }
}

enum BreakScreenGradientPreset: String, Codable, Equatable, CaseIterable, Identifiable {
    case graphite
    case ocean
    case forest
    case ember
    case dawn

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CompanionPopupPosition: String, Codable, Equatable, CaseIterable, Identifiable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.topLeft.rawValue, "left": self = .topLeft
        case Self.topCenter.rawValue, "top", "center": self = .topCenter
        case Self.topRight.rawValue, "right": self = .topRight
        case Self.bottomLeft.rawValue: self = .bottomLeft
        case Self.bottomCenter.rawValue, "bottom": self = .bottomCenter
        case Self.bottomRight.rawValue: self = .bottomRight
        default: self = .topCenter
        }
    }
}

struct CompanionRGBAColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let breakScreenDefault = CompanionRGBAColor(
        red: 0.055,
        green: 0.075,
        blue: 0.11,
        alpha: 1
    )
}

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
    case adaptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock:
            return "Clock"
        case .adaptive:
            return "Adaptive"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.clock.rawValue:
            self = .clock
        case Self.adaptive.rawValue, "expanded":
            self = .adaptive
        default:
            self = .clock
        }
    }
}

struct CompanionPreferences: Codable, Equatable {
    static let hardLimitWarningLeadTimeOptions = [10, 20, 30]
    static let breakScreenStrictDelayOptions = [5, 10, 15, 30, 60]
    static let breakScreenActivityExtensionOptions = [30, 60, 120]
    static let breakScreenActivityCapOptions = [120, 300, 600]
    static let smartPauseIdleOptions = [30, 60, 120, 300, 600]

    var launchAtLogin = false
    var hideDockIconWhenNoWindowsOpen = true
    var appearance: CompanionAppearance = .system
    var menuBarDisplayMode: MenuBarDisplayMode = .iconAndText
    var menuBarIdleTextMode: MenuBarIdleTextMode = .idle
    var menuBarTimeFormat: MenuBarTimeFormat = .clock
    var smartPauseEnabled = false
    var smartPauseOnLock = true
    var smartPauseOnDisplaySleep = true
    var smartPauseOnInactivity = true
    var smartPauseIdleSeconds = 120
    var showHardLimitActionPopups = true
    var showHardLimitWarningIndicator = true
    var hardLimitWarningLeadSeconds = 10
    var showInactivityActionPopups = true
    var inactivityPopupPosition: CompanionPopupPosition = .topCenter
    var breakScreenEnabled = false
    var breakScreenMode: BreakScreenMode = .easy
    var breakScreenStrictDelaySeconds = 15
    var breakScreenActivityDeferral: BreakScreenActivityDeferral = .allModes
    var breakScreenActivityExtensionSeconds = 60
    var breakScreenActivityDeferralCapSeconds = 300
    var breakScreenBackgroundStyle: BreakScreenBackgroundStyle = .systemWallpaper
    var breakScreenSolidColor = CompanionRGBAColor.breakScreenDefault
    var breakScreenGradientPreset: BreakScreenGradientPreset = .graphite
    var pinPopover = false
    var runtimeDirectoryOverride: String?
    var tuiCommand = "crona"
    var appUpdateChannel: AppReleaseChannel?

    static func normalizedHardLimitWarningLeadSeconds(_ value: Int) -> Int {
        hardLimitWarningLeadTimeOptions.min {
            abs($0 - value) < abs($1 - value)
        } ?? 10
    }

    static func normalizedBreakScreenStrictDelaySeconds(_ value: Int) -> Int {
        breakScreenStrictDelayOptions.min {
            abs($0 - value) < abs($1 - value)
        } ?? 15
    }

    static func normalizedSmartPauseIdleSeconds(_ value: Int) -> Int {
        smartPauseIdleOptions.min {
            abs($0 - value) < abs($1 - value)
        } ?? 120
    }
}

extension CompanionPreferences {
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case hideDockIconWhenNoWindowsOpen
        case appearance
        case menuBarDisplayMode
        case menuBarIdleTextMode
        case menuBarTimeFormat
        case smartPauseEnabled
        case smartPauseOnLock
        case smartPauseOnDisplaySleep
        case smartPauseOnInactivity
        case smartPauseIdleSeconds
        case showHardLimitActionPopups
        case showHardLimitWarningIndicator
        case hardLimitWarningLeadSeconds
        case showInactivityActionPopups
        case inactivityPopupPosition
        case breakScreenEnabled
        case breakScreenMode
        case breakScreenStrictDelaySeconds
        case breakScreenActivityDeferral
        case breakScreenActivityExtensionSeconds
        case breakScreenActivityDeferralCapSeconds
        case breakScreenBackgroundStyle
        case breakScreenSolidColor
        case breakScreenGradientPreset
        case pinPopover
        case runtimeDirectoryOverride
        case tuiCommand
        case appUpdateChannel
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hideDockIconWhenNoWindowsOpen =
            try values.decodeIfPresent(Bool.self, forKey: .hideDockIconWhenNoWindowsOpen) ?? true
        appearance =
            try values.decodeIfPresent(CompanionAppearance.self, forKey: .appearance) ?? .system
        menuBarDisplayMode =
            try values.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode)
            ?? .iconAndText
        menuBarIdleTextMode =
            try values.decodeIfPresent(MenuBarIdleTextMode.self, forKey: .menuBarIdleTextMode)
            ?? .idle
        menuBarTimeFormat =
            try values.decodeIfPresent(MenuBarTimeFormat.self, forKey: .menuBarTimeFormat)
            ?? .clock
        smartPauseEnabled =
            try values.decodeIfPresent(Bool.self, forKey: .smartPauseEnabled)
            ?? false
        smartPauseOnLock =
            try values.decodeIfPresent(Bool.self, forKey: .smartPauseOnLock)
            ?? true
        smartPauseOnDisplaySleep =
            try values.decodeIfPresent(Bool.self, forKey: .smartPauseOnDisplaySleep)
            ?? true
        smartPauseOnInactivity =
            try values.decodeIfPresent(Bool.self, forKey: .smartPauseOnInactivity)
            ?? true
        smartPauseIdleSeconds =
            try values.decodeIfPresent(Int.self, forKey: .smartPauseIdleSeconds)
            ?? 120
        showHardLimitActionPopups =
            try values.decodeIfPresent(Bool.self, forKey: .showHardLimitActionPopups)
            ?? true
        showHardLimitWarningIndicator =
            try values.decodeIfPresent(Bool.self, forKey: .showHardLimitWarningIndicator)
            ?? true
        hardLimitWarningLeadSeconds =
            try values.decodeIfPresent(Int.self, forKey: .hardLimitWarningLeadSeconds)
            ?? 10
        showInactivityActionPopups =
            try values.decodeIfPresent(Bool.self, forKey: .showInactivityActionPopups)
            ?? true
        inactivityPopupPosition =
            try values.decodeIfPresent(CompanionPopupPosition.self, forKey: .inactivityPopupPosition)
            ?? .topCenter
        breakScreenEnabled =
            try values.decodeIfPresent(Bool.self, forKey: .breakScreenEnabled)
            ?? false
        breakScreenMode =
            try values.decodeIfPresent(BreakScreenMode.self, forKey: .breakScreenMode)
            ?? .easy
        breakScreenStrictDelaySeconds =
            try values.decodeIfPresent(Int.self, forKey: .breakScreenStrictDelaySeconds)
            ?? 15
        breakScreenActivityDeferral =
            try values.decodeIfPresent(BreakScreenActivityDeferral.self, forKey: .breakScreenActivityDeferral)
            ?? .allModes
        breakScreenActivityExtensionSeconds =
            try values.decodeIfPresent(Int.self, forKey: .breakScreenActivityExtensionSeconds) ?? 60
        breakScreenActivityDeferralCapSeconds =
            try values.decodeIfPresent(Int.self, forKey: .breakScreenActivityDeferralCapSeconds) ?? 300
        breakScreenBackgroundStyle =
            try values.decodeIfPresent(BreakScreenBackgroundStyle.self, forKey: .breakScreenBackgroundStyle)
            ?? .systemWallpaper
        breakScreenSolidColor =
            try values.decodeIfPresent(CompanionRGBAColor.self, forKey: .breakScreenSolidColor)
            ?? .breakScreenDefault
        breakScreenGradientPreset =
            try values.decodeIfPresent(BreakScreenGradientPreset.self, forKey: .breakScreenGradientPreset)
            ?? .graphite
        pinPopover = try values.decodeIfPresent(Bool.self, forKey: .pinPopover) ?? false
        runtimeDirectoryOverride =
            try values.decodeIfPresent(String.self, forKey: .runtimeDirectoryOverride)
        tuiCommand = try values.decodeIfPresent(String.self, forKey: .tuiCommand) ?? "crona"
        appUpdateChannel = try values.decodeIfPresent(AppReleaseChannel.self, forKey: .appUpdateChannel)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(launchAtLogin, forKey: .launchAtLogin)
        try values.encode(hideDockIconWhenNoWindowsOpen, forKey: .hideDockIconWhenNoWindowsOpen)
        try values.encode(appearance, forKey: .appearance)
        try values.encode(menuBarDisplayMode, forKey: .menuBarDisplayMode)
        try values.encode(menuBarIdleTextMode, forKey: .menuBarIdleTextMode)
        try values.encode(menuBarTimeFormat, forKey: .menuBarTimeFormat)
        try values.encode(smartPauseEnabled, forKey: .smartPauseEnabled)
        try values.encode(smartPauseOnLock, forKey: .smartPauseOnLock)
        try values.encode(smartPauseOnDisplaySleep, forKey: .smartPauseOnDisplaySleep)
        try values.encode(smartPauseOnInactivity, forKey: .smartPauseOnInactivity)
        try values.encode(smartPauseIdleSeconds, forKey: .smartPauseIdleSeconds)
        try values.encode(showHardLimitActionPopups, forKey: .showHardLimitActionPopups)
        try values.encode(showHardLimitWarningIndicator, forKey: .showHardLimitWarningIndicator)
        try values.encode(hardLimitWarningLeadSeconds, forKey: .hardLimitWarningLeadSeconds)
        try values.encode(showInactivityActionPopups, forKey: .showInactivityActionPopups)
        try values.encode(inactivityPopupPosition, forKey: .inactivityPopupPosition)
        try values.encode(breakScreenEnabled, forKey: .breakScreenEnabled)
        try values.encode(breakScreenMode, forKey: .breakScreenMode)
        try values.encode(breakScreenStrictDelaySeconds, forKey: .breakScreenStrictDelaySeconds)
        try values.encode(breakScreenActivityDeferral, forKey: .breakScreenActivityDeferral)
        try values.encode(breakScreenActivityExtensionSeconds, forKey: .breakScreenActivityExtensionSeconds)
        try values.encode(breakScreenActivityDeferralCapSeconds, forKey: .breakScreenActivityDeferralCapSeconds)
        try values.encode(breakScreenBackgroundStyle, forKey: .breakScreenBackgroundStyle)
        try values.encode(breakScreenSolidColor, forKey: .breakScreenSolidColor)
        try values.encode(breakScreenGradientPreset, forKey: .breakScreenGradientPreset)
        try values.encode(pinPopover, forKey: .pinPopover)
        try values.encodeIfPresent(runtimeDirectoryOverride, forKey: .runtimeDirectoryOverride)
        try values.encode(tuiCommand, forKey: .tuiCommand)
        try values.encodeIfPresent(appUpdateChannel, forKey: .appUpdateChannel)
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
            normalized.breakScreenStrictDelaySeconds =
                CompanionPreferences.normalizedBreakScreenStrictDelaySeconds(
                    decoded.breakScreenStrictDelaySeconds
                )
            normalized.smartPauseIdleSeconds =
                CompanionPreferences.normalizedSmartPauseIdleSeconds(
                    decoded.smartPauseIdleSeconds
                )
            normalized.breakScreenActivityExtensionSeconds =
                CompanionPreferences.breakScreenActivityExtensionOptions.min {
                    abs($0 - decoded.breakScreenActivityExtensionSeconds) < abs($1 - decoded.breakScreenActivityExtensionSeconds)
                } ?? 60
            normalized.breakScreenActivityDeferralCapSeconds =
                CompanionPreferences.breakScreenActivityCapOptions.min {
                    abs($0 - decoded.breakScreenActivityDeferralCapSeconds) < abs($1 - decoded.breakScreenActivityDeferralCapSeconds)
                } ?? 300
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
