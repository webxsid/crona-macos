import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class UserActivityMonitor: ObservableObject {
    private(set) var lastInteractionAt: Date?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isRecentlyActive: Bool {
        guard let lastInteractionAt else { return false }
        return Date().timeIntervalSince(lastInteractionAt) <= 2
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.markInteraction() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.markInteraction()
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        lastInteractionAt = nil
    }

    func markInteraction(at date: Date = Date()) {
        lastInteractionAt = date
        objectWillChange.send()
    }

    func fallbackRecentlyActive() -> Bool {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!
        ) <= 2
    }
}
