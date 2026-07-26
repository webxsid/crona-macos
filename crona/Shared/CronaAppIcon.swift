import AppKit

enum CronaAppIcon {
    static let image: NSImage = {
        if
            let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }

        if let image = NSImage(named: NSImage.Name("AppIcon")) {
            return image
        }

        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }()
}
