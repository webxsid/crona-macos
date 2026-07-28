//
//  CronaConfig.swift
//  crona
//
//  Created by Siddharth Mittal on 16/05/26.
//

import Foundation

struct CronaConfig {
    let environment: CronaEnv
    let daemonLabel: String
    let postHogApiKey: String?
    let discoveryFilePath: String
    let runtimeDirectoryPath: String
    let defaultSocketPath: String
    let defaultKernelExecutable: String
    let defaultDevKernelExecutable: String

    static let placeholder = CronaConfig(
        environment: .development,
        daemonLabel: "crona",
        postHogApiKey: nil,
        discoveryFilePath: "",
        runtimeDirectoryPath: "",
        defaultSocketPath: "",
        defaultKernelExecutable: "crona-daemon",
        defaultDevKernelExecutable: "crona-daemon-dev"
    )

    var discoveryMissingMessage: String {
        "Discovery file missing at \(discoveryFilePath)"
    }
}
