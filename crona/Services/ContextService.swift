import Combine
import Foundation
import OSLog

struct ContextSnapshot: Equatable {
    var repoName: String?
    var streamName: String?
    var issueTitle: String?
    var isConnected = false
}

@MainActor
final class ContextService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.crona.macos", category: "context")

    @Published var snapshot = ContextSnapshot()

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
        eventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent else { return }
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
        connectObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.debug("Context refresh triggered by daemon connect")
            Task { await self?.refresh() }
        }

        Task { await refresh() }
    }

    isolated deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
    }

    func refresh() async {
        do {
            logger.debug("Refreshing active context")
            let context = try await daemonConnection.withClient { try await $0.optionalContextGet() }
            guard let context else {
                snapshot = ContextSnapshot()
                logger.debug("Applied active context: none")
                return
            }
            snapshot = ContextSnapshot(
                repoName: context.repoName,
                streamName: context.streamName,
                issueTitle: context.issueTitle,
                isConnected: true
            )
            logger.debug("Applied active context: repo=\(context.repoName ?? "nil", privacy: .private) stream=\(context.streamName ?? "nil", privacy: .private) issue=\(context.issueTitle ?? "nil", privacy: .private)")
        } catch {
            logger.error("Context refresh failed: \(error.localizedDescription, privacy: .private)")
            snapshot = ContextSnapshot()
        }
    }

    static func shouldRefresh(for eventType: String) -> Bool {
        switch eventType {
        case "context.repo.changed", "context.stream.changed", "context.issue.changed", "context.cleared", "timer.state", "session.started", "session.stopped", "session.ended", "timer.extended":
            return true
        default:
            return false
        }
    }

    private func handle(event: CronaProtocolEvent) {
        switch event.type {
        case _ where Self.shouldRefresh(for: event.type):
            logger.debug("Context refresh triggered by event: \(event.type, privacy: .public)")
            Task { await refresh() }
        default:
            break
        }
    }
}
