//
//  CronaConfigLoader.swift
//  crona
//
//  Created by Siddharth Mittal on 16/05/26.
//

import Foundation

final class CronaConfigLoader {
    private let bundle: Bundle
    private let environmentProvider: () -> [String: String]

    init(
        bundle: Bundle = .main,
        environmentProvider: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.bundle = bundle
        self.environmentProvider = environmentProvider
    }

    func load() -> LoadedCronaRuntime {
        let environmentValues = environmentProvider()
        let configuredRuntimeDirectory = Self.requiredBundleValue(bundle, key: "CRONA_RUNTIME_DIR")
        let runtimeDirectory = Self.optionalEnv(environmentValues, key: "CRONA_HOME") ?? configuredRuntimeDirectory
        let config = CronaConfig(
            environment: Self.requiredBundleValue(bundle, key: "CRONA_APP_ENV").cronaEnv,
            daemonLabel: Self.requiredBundleValue(bundle, key: "CRONA_DAEMON_LABEL"),
            postHogApiKey: Self.bundleValue(bundle, key: "CRONA_POSTHOG_API_KEY"),
            discoveryFilePath: "\(runtimeDirectory)/kernel.json",
            runtimeDirectoryPath: runtimeDirectory,
            defaultSocketPath: "\(runtimeDirectory)/kernel.sock",
            defaultKernelExecutable: Self.requiredBundleValue(bundle, key: "CRONA_KERNEL_EXECUTABLE"),
            defaultDevKernelExecutable: Self.requiredBundleValue(bundle, key: "CRONA_KERNEL_DEV_EXECUTABLE")
        )

        let discovery = Self.loadDiscovery(from: config.discoveryFilePath)

        return LoadedCronaRuntime(config: config, discovery: discovery)
    }

    private static func loadDiscovery(from path: String) -> CronaKernelDiscovery? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(CronaKernelDiscovery.self, from: data)
    }

    private static func optionalEnv(_ values: [String: String], key: String) -> String? {
        values[key]
    }

    private static func requiredBundleValue(_ bundle: Bundle, key: String) -> String {
        guard let value = bundleValue(bundle, key: key) else {
            preconditionFailure("Missing required bundle config value for \(key)")
        }
        return value
    }

    private static func bundleValue(_ bundle: Bundle, key: String) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension String {
    fileprivate var cronEnvNormalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    fileprivate var cronaEnv: CronaEnv {
        CronaEnv(rawValue: cronEnvNormalized) ?? .development
    }
}
