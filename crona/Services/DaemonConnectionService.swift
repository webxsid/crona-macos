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
    private let daemonLaunchService: DaemonLaunchService
    private let clientFactory: (String) -> CronaDaemonClient
    private let reconnectInterval: Duration
    private let postLaunchRetryDelay: Duration
    private var connectionTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var isAttemptingConnection = false
    private var launchFailureLatched = false
    private var attemptedDaemonLaunchEndpoints: Set<String> = []
    private var lastDayBoundaryOccurrenceID: String?

    @Published var connectionState: CompanionConnectionState = .idle
    @Published var kernelInfo: CronaKernelInfo?
    @Published var health: CronaHealth?
    @Published var alertStatus: CronaAlertStatus?
    @Published private(set) var currentDate = ""
    @Published private(set) var timezone = ""
    @Published var lastReconnectAt: Date?
    @Published var lastErrorDescription: String?
    @Published var resolvedDiscovery: CronaResolvedKernelDiscovery?
    @Published private(set) var client: CronaDaemonClient?
    private let logger = Logger(subsystem: "com.crona.macos", category: "connection")

    init(
        kernelDiscovery: KernelDiscoveryService,
        daemonLaunchService: DaemonLaunchService? = nil,
        clientFactory: ((String) -> CronaDaemonClient)? = nil,
        reconnectInterval: Duration = .seconds(2),
        postLaunchRetryDelay: Duration = .milliseconds(350)
    ) {
        self.kernelDiscovery = kernelDiscovery
        self.daemonLaunchService = daemonLaunchService ?? DaemonLaunchService()
        self.clientFactory = clientFactory ?? { CronaDaemonClient(endpoint: $0) }
        self.reconnectInterval = reconnectInterval
        self.postLaunchRetryDelay = postLaunchRetryDelay
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
        stop()
        clearLatchedLaunchFailure()
        client = nil
        kernelInfo = nil
        health = nil
        alertStatus = nil
        currentDate = ""
        timezone = ""
        lastDayBoundaryOccurrenceID = nil
        lastErrorDescription = nil
        connectionState = .disconnected
        start()
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

    func applyDayBoundary(_ payload: CronaDayBoundaryEventPayload) -> Bool {
        guard payload.kind == "start", !payload.logicalDate.isEmpty else { return false }
        guard payload.occurrenceID != lastDayBoundaryOccurrenceID else { return false }
        lastDayBoundaryOccurrenceID = payload.occurrenceID
        currentDate = payload.logicalDate
        timezone = payload.timezone
        return true
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
        currentDate = ""
        timezone = ""
        lastDayBoundaryOccurrenceID = nil
        connectionState = .disconnected
        lastErrorDescription = nil
    }

    private func runConnectionLoop() async {
        defer { connectionTask = nil }
        while !Task.isCancelled {
            if launchFailureLatched {
                logger.debug("Connection loop stopped after daemon launch failure")
                return
            }

            if connectionState == .connected, eventTask != nil {
                try? await Task.sleep(for: reconnectInterval)
                continue
            }

            await connectOnce()
            if Task.isCancelled { break }
            if launchFailureLatched { return }
            try? await Task.sleep(for: reconnectInterval)
        }
    }

    private func connectOnce(force: Bool = false) async {
        guard !launchFailureLatched || force else { return }
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
            if await attemptDaemonLaunchIfNeeded(runtime: runtime, discovery: nil, after: nil) {
                return
            }
            client = nil
            connectionState = launchFailureLatched ? .error : .disconnected
            if !launchFailureLatched {
                lastErrorDescription = runtime.config.discoveryMissingMessage
                logger.error("Daemon discovery missing: \(runtime.config.discoveryMissingMessage, privacy: .public)")
            }
            return
        }

        guard discovery.transport.lowercased().contains("unix") else {
            client = nil
            connectionState = .error
            lastErrorDescription = CronaConnectionFailure.unsupportedTransport(discovery.transport).message
            logger.error("Unsupported daemon transport: \(discovery.transport, privacy: .public)")
            return
        }

        let client = clientFactory(discovery.endpoint)
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
            self.currentDate = health.currentDate ?? ""
            self.timezone = health.timezone ?? ""
            self.lastDayBoundaryOccurrenceID = nil
            self.kernelInfo = info
            self.alertStatus = try? await client.alertsStatusGet()
            self.connectionState = .connected
            self.lastReconnectAt = Date()
            self.lastErrorDescription = nil
            self.clearLatchedLaunchFailure()
            self.attemptedDaemonLaunchEndpoints.remove(discovery.endpoint)
            NotificationCenter.default.post(name: .cronaDaemonDidConnect, object: nil)
            await subscribeToEvents(using: client)
        } catch {
            if await attemptDaemonLaunchIfNeeded(
                runtime: runtime,
                discovery: discovery,
                after: error
            ) {
                return
            }
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
                    self.currentDate = ""
                    self.timezone = ""
                    self.lastDayBoundaryOccurrenceID = nil
                    self.connectionState = .disconnected
                    self.lastErrorDescription = error.localizedDescription
                    self.eventTask = nil
                    self.logger.error("Daemon event stream failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func attemptDaemonLaunchIfNeeded(
        runtime: LoadedCronaRuntime,
        discovery: CronaResolvedKernelDiscovery?,
        after error: Error?
    ) async -> Bool {
        guard connectionState == .connecting else { return false }
        let launchAttemptKey = discovery?.endpoint ?? "runtime:\(runtime.config.runtimeDirectoryPath)"
        guard attemptedDaemonLaunchEndpoints.insert(launchAttemptKey).inserted else { return false }

        do {
            try daemonLaunchService.launch(runtime: runtime, discovery: discovery)
            clearLatchedLaunchFailure()
            logger.log("Daemon recovery launched local daemon and will retry.")
            try? await Task.sleep(for: postLaunchRetryDelay)
            await connectOnce(force: true)
            return true
        } catch {
            latchLaunchFailure(message: error.localizedDescription)
            logger.error(
                "Daemon recovery launch failed. trigger_error=\(String(describing: error), privacy: .public) launch_error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func clearLatchedLaunchFailure() {
        launchFailureLatched = false
        attemptedDaemonLaunchEndpoints.removeAll()
    }

    private func latchLaunchFailure(message: String) {
        launchFailureLatched = true
        client = nil
        kernelInfo = nil
        health = nil
        alertStatus = nil
        currentDate = ""
        timezone = ""
        lastDayBoundaryOccurrenceID = nil
        connectionState = .error
        lastErrorDescription = message
    }
}

extension Notification.Name {
    static let cronaDaemonEventReceived = Notification.Name("crona.daemon.event.received")
    static let cronaDaemonDidConnect = Notification.Name("crona.daemon.didConnect")
}
