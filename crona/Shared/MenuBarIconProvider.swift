import AppKit

enum MenuBarIconState: String, CaseIterable {
    case idle
    case focus
    case paused
    case breakTime
    case attention
    case offline

    static func resolve(
        connectionState: CompanionConnectionState,
        timerSnapshot: TimerSnapshot
    ) -> Self {
        switch connectionState {
        case .disconnected, .incompatible, .error:
            return .offline
        case .idle, .connecting, .connected:
            break
        }

        guard timerSnapshot.sessionID != nil else { return .idle }
        if timerSnapshot.hardLimitExpired { return .attention }
        if timerSnapshot.state == "paused" { return .paused }
        if TimerSegmentKind(rawValue: timerSnapshot.segmentType)?.isBreak == true {
            return .breakTime
        }
        return .focus
    }

    var assetName: String {
        switch self {
        case .idle:
            return "menu-icon-idle"
        case .focus:
            return "menu-icon-focus"
        case .paused:
            return "menu-icon-paused"
        case .breakTime:
            return "menu-icon-break-time"
        case .attention:
            return "menu-icon-attention"
        case .offline:
            return "menu-icon-offline"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .idle:
            return "Crona: ready"
        case .focus:
            return "Crona: focus timer running"
        case .paused:
            return "Crona: timer paused"
        case .breakTime:
            return "Crona: break in progress"
        case .attention:
            return "Crona: timer action needed"
        case .offline:
            return "Crona: disconnected"
        }
    }
}

enum MenuBarIconProvider {
    private static let images = NSCache<NSString, NSImage>()

    static func image(for state: MenuBarIconState) -> NSImage? {
        let key = state.rawValue as NSString
        if let cachedImage = images.object(forKey: key) {
            return cachedImage
        }

        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        guard let url = bundles.lazy.compactMap({ bundle in
            bundle.url(forResource: state.assetName, withExtension: "svg")
        }).first,
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        images.setObject(image, forKey: key)
        return image
    }
}
