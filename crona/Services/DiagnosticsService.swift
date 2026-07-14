import AppKit
import Combine
import Foundation

struct DiagnosticsSnapshot: Equatable {
    var connectionState: String = "Idle"
    var protocolVersion: String = CronaProtocolVersion.current.rawValue
    var kernelVersion: String = "Unknown"
    var runtimeDirectory: String = "Unknown"
    var healthSummary: String = "Unavailable"
    var lastReconnect: String = "Never"
    var endpoint: String = "Unknown"
    var transport: String = "Unknown"
    var alertBackend: String = "Unknown"
    var lastError: String?

    var text: String {
        [
            "Connection State: \(connectionState)",
            "Protocol Version: \(protocolVersion)",
            "Kernel Version: \(kernelVersion)",
            "Runtime Directory: \(runtimeDirectory)",
            "Health: \(healthSummary)",
            "Last Reconnect: \(lastReconnect)",
            "Endpoint: \(endpoint)",
            "Transport: \(transport)",
            "Alert Backend: \(alertBackend)",
            "Last Error: \(lastError ?? "None")"
        ].joined(separator: "\n")
    }
}

@MainActor
final class DiagnosticsService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let kernelDiscovery: KernelDiscoveryService

    @Published var snapshot = DiagnosticsSnapshot()

    init(daemonConnection: DaemonConnectionService, kernelDiscovery: KernelDiscoveryService) {
        self.daemonConnection = daemonConnection
        self.kernelDiscovery = kernelDiscovery
        Task { await refresh() }
    }

    func refresh() async {
        let runtime = kernelDiscovery.loadedRuntime
        let kernelInfo = daemonConnection.kernelInfo
        let health = daemonConnection.health
        let alertStatus = daemonConnection.alertStatus

        snapshot = DiagnosticsSnapshot(
            connectionState: daemonConnection.connectionState.rawValue.capitalized,
            protocolVersion: kernelInfo?.protocolVersion ?? CronaProtocolVersion.current.rawValue,
            kernelVersion: kernelInfo?.runningChannel ?? "Unknown",
            runtimeDirectory: runtime.config.runtimeDirectoryPath,
            healthSummary: health.map { "\($0.status) | db=\($0.db) | uptime=\(Int($0.uptime))s" } ?? "Unavailable",
            lastReconnect: daemonConnection.lastReconnectAt?.formatted(date: .abbreviated, time: .standard) ?? "Never",
            endpoint: kernelInfo?.endpoint ?? runtime.resolvedDiscovery?.endpoint ?? "Unknown",
            transport: kernelInfo?.transport ?? runtime.resolvedDiscovery?.transport ?? "Unknown",
            alertBackend: alertStatus?.notificationBackend ?? "Unknown",
            lastError: daemonConnection.lastErrorDescription
        )
    }

    func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snapshot.text, forType: .string)
    }
}
