import Combine
import Foundation
import OSLog

enum CompanionConnectionState: String, Equatable {
    case idle
    case connecting
    case connected
    case disconnected
    case incompatible
    case error
}

@MainActor
final class DaemonConnectionService: ObservableObject {
    private let kernelDiscovery: KernelDiscoveryService
    private var connectionTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var isAttemptingConnection = false

    @Published var connectionState: CompanionConnectionState = .idle
    @Published var kernelInfo: CronaKernelInfo?
    @Published var health: CronaHealth?
    @Published var alertStatus: CronaAlertStatus?
    @Published var lastReconnectAt: Date?
    @Published var lastErrorDescription: String?
    @Published var resolvedDiscovery: CronaResolvedKernelDiscovery?
    @Published private(set) var client: CronaDaemonClient?
    private let logger = Logger(subsystem: "com.crona.macos", category: "connection")

    init(kernelDiscovery: KernelDiscoveryService) {
        self.kernelDiscovery = kernelDiscovery
    }

    func start() {
        guard connectionTask == nil else { return }
        connectionTask = Task { await runConnectionLoop() }
    }

    func stop() {
        connectionTask?.cancel()
        eventTask?.cancel()
        connectionTask = nil
        eventTask = nil
        isAttemptingConnection = false
    }

    func manualReconnect() {
        eventTask?.cancel()
        client = nil
        connectionState = .disconnected
        Task { await connectOnce(force: true) }
    }

    func sendTestNotification() async {
        guard let client else { return }
        do {
            _ = try await client.alertsTestNotification()
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }

    func withClient<T>(_ body: @escaping (CronaDaemonClient) async throws -> T) async throws -> T {
        guard let client else {
            throw CronaConnectionFailure.transport("The daemon client is unavailable.")
        }
        return try await body(client)
    }

    func shutdownAndWait(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(100)
    ) async throws {
        guard let shutdownClient = client else {
            stop()
            markDaemonStopped()
            return
        }

        stop()
        do {
            _ = try await shutdownClient.kernelShutdown()
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)

            while clock.now < deadline {
                do {
                    _ = try await shutdownClient.healthGet()
                } catch {
                    markDaemonStopped()
                    return
                }
                try await Task.sleep(for: pollInterval)
            }

            do {
                _ = try await shutdownClient.healthGet()
            } catch {
                markDaemonStopped()
                return
            }

            throw CronaConnectionFailure.transport(
                "Crona did not stop within five seconds."
            )
        } catch {
            client = nil
            connectionState = .disconnected
            lastErrorDescription = error.localizedDescription
            start()
            throw error
        }
    }

    private func markDaemonStopped() {
        client = nil
        kernelInfo = nil
        health = nil
        alertStatus = nil
        connectionState = .disconnected
        lastErrorDescription = nil
    }

    private func runConnectionLoop() async {
        while !Task.isCancelled {
            if connectionState == .connected, eventTask != nil {
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            await connectOnce()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func connectOnce(force: Bool = false) async {
        guard force || (!isAttemptingConnection && connectionState != .connected) else {
            return
        }

        isAttemptingConnection = true
        defer { isAttemptingConnection = false }
        connectionState = .connecting
        let runtime = kernelDiscovery.reload()
        resolvedDiscovery = runtime.resolvedDiscovery
        logger.debug("Connecting to daemon. force=\(force, privacy: .public)")

        guard let discovery = runtime.resolvedDiscovery else {
            client = nil
            connectionState = .disconnected
            lastErrorDescription = runtime.config.discoveryMissingMessage
            logger.error("Daemon discovery missing: \(runtime.config.discoveryMissingMessage, privacy: .public)")
            return
        }

        guard discovery.transport.lowercased().contains("unix") else {
            client = nil
            connectionState = .error
            lastErrorDescription = CronaConnectionFailure.unsupportedTransport(discovery.transport).message
            logger.error("Unsupported daemon transport: \(discovery.transport, privacy: .public)")
            return
        }

        let client = CronaDaemonClient(endpoint: discovery.endpoint)
        do {
            let health = try await client.healthGet()
            let info = try await client.kernelInfoGet()
            logger.debug("Daemon handshake succeeded. endpoint=\(discovery.endpoint, privacy: .public) protocol=\(info.protocolVersion, privacy: .public)")

            guard info.protocolVersion == CronaProtocolVersion.current.rawValue else {
                self.client = nil
                self.kernelInfo = info
                connectionState = .incompatible
                lastErrorDescription = CronaConnectionFailure.incompatibleProtocol(
                    expected: CronaProtocolVersion.current.rawValue,
                    actual: info.protocolVersion
                ).message
                logger.error("Daemon protocol mismatch. expected=\(CronaProtocolVersion.current.rawValue, privacy: .public) actual=\(info.protocolVersion, privacy: .public)")
                return
            }

            self.client = client
            self.health = health
            self.kernelInfo = info
            self.alertStatus = try? await client.alertsStatusGet()
            self.connectionState = .connected
            self.lastReconnectAt = Date()
            self.lastErrorDescription = nil
            NotificationCenter.default.post(name: .cronaDaemonDidConnect, object: nil)
            await subscribeToEvents(using: client)
        } catch {
            self.client = nil
            self.connectionState = .disconnected
            self.lastErrorDescription = error.localizedDescription
            logger.error("Daemon connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func subscribeToEvents(using client: CronaDaemonClient) async {
        eventTask?.cancel()
        eventTask = Task {
            do {
                logger.debug("Starting daemon event stream consumer")
                let stream = try await client.subscribeToEvents()
                for try await event in stream {
                    if Task.isCancelled { break }
                    logger.debug("Posting daemon event notification: \(event.type, privacy: .public)")
                    NotificationCenter.default.post(name: .cronaDaemonEventReceived, object: event)
                }
                await MainActor.run {
                    self.logger.debug("Daemon event stream ended without error")
                    self.eventTask = nil
                }
            } catch {
                await MainActor.run {
                    self.client = nil
                    self.connectionState = .disconnected
                    self.lastErrorDescription = error.localizedDescription
                    self.eventTask = nil
                    self.logger.error("Daemon event stream failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

extension Notification.Name {
    static let cronaDaemonEventReceived = Notification.Name("crona.daemon.event.received")
    static let cronaDaemonDidConnect = Notification.Name("crona.daemon.didConnect")
}
