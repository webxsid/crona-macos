//
//  CronaKernelDiscovery.swift
//  crona
//
//  Created by Siddharth Mittal on 16/05/26.
//

import Foundation

struct CronaKernelDiscovery: Codable {
    let pid: Int?
    let transport: String?
    let endpoint: String?
    let socketPath: String?
    let protocolVersion: String?
    let token: String?
    let startedAt: String?
    let scratchDir: String?
    let env: String?
    let executablePath: String?
    let runningChannel: String?
    let runningIsBeta: Bool?

    var resolvedTransport: String {
        let trimmed = transport?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.defaultTransport : trimmed
    }

    var resolvedEndpoint: String? {
        let endpointValue = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let endpointValue, !endpointValue.isEmpty {
            return endpointValue
        }

        let socketPathValue = socketPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let socketPathValue, !socketPathValue.isEmpty {
            return socketPathValue
        }

        return nil
    }

    var resolvedProtocolVersion: CronaProtocolVersion {
        guard let protocolVersion else {
            return CronaProtocolVersion.current
        }

        let trimmed = protocolVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? CronaProtocolVersion.current : CronaProtocolVersion(rawValue: trimmed)
    }

    var resolvedEnvironment: CronaEnv {
        guard let env else {
            return .development
        }

        return CronaEnv(rawValue: env.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .development
    }

    var resolvedRunningChannel: String {
        let trimmed = runningChannel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    var resolvedRunningIsBeta: Bool {
        runningIsBeta ?? false
    }

    func resolved(using config: CronaConfig) -> CronaResolvedKernelDiscovery? {
        guard let endpoint = resolvedEndpoint else {
            return nil
        }

        return CronaResolvedKernelDiscovery(
            pid: pid,
            transport: resolvedTransport,
            endpoint: endpoint,
            socketPath: socketPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            protocolVersion: resolvedProtocolVersion,
            token: token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            startedAt: startedAt?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            scratchDir: scratchDir?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            env: resolvedEnvironment,
            executablePath: executablePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            runningChannel: resolvedRunningChannel,
            runningIsBeta: resolvedRunningIsBeta,
            defaultSocketPath: config.defaultSocketPath
        )
    }

    private static var defaultTransport: String {
        #if os(Windows)
        return "named_pipe"
        #else
        return "unix"
        #endif
    }
}

struct CronaResolvedKernelDiscovery: Equatable {
    let pid: Int?
    let transport: String
    let endpoint: String
    let socketPath: String?
    let protocolVersion: CronaProtocolVersion
    let token: String?
    let startedAt: String?
    let scratchDir: String?
    let env: CronaEnv
    let executablePath: String?
    let runningChannel: String
    let runningIsBeta: Bool
    let defaultSocketPath: String

    var effectiveSocketPath: String {
        socketPath ?? defaultSocketPath
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
