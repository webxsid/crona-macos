import Foundation
import OSLog

struct DaemonLaunchRequest: Equatable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let currentDirectoryURL: URL?
}

struct DaemonLaunchService {
    private let logger = Logger(subsystem: "com.crona.macos", category: "daemon-launch")
    private let processFactory: () -> Process
    private let launchHandler: ((DaemonLaunchRequest) throws -> Void)?

    init(
        processFactory: @escaping () -> Process = { Process() },
        launchHandler: ((DaemonLaunchRequest) throws -> Void)? = nil
    ) {
        self.processFactory = processFactory
        self.launchHandler = launchHandler
    }

    func launch(
        runtime: LoadedCronaRuntime,
        discovery: CronaResolvedKernelDiscovery? = nil
    ) throws {
        let request = try makeRequest(runtime: runtime, discovery: discovery)
        if let launchHandler {
            try launchHandler(request)
            logger.log(
                "Launched daemon executable: \(request.executableURL.path, privacy: .public)"
            )
            return
        }
        let process = processFactory()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.currentDirectoryURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        logger.log(
            "Launched daemon executable: \(request.executableURL.path, privacy: .public)"
        )
    }

    func makeRequest(
        runtime: LoadedCronaRuntime,
        discovery: CronaResolvedKernelDiscovery? = nil
    ) throws -> DaemonLaunchRequest {
        let configuredPath = discovery?.executablePath ?? defaultExecutableName(for: runtime.config)
        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw CronaConnectionFailure.transport("No daemon executable is configured.")
        }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        let launchTarget = try resolveLaunchTarget(for: expandedPath)

        var environment = ProcessInfo.processInfo.environment
        environment["CRONA_HOME"] = runtime.config.runtimeDirectoryPath

        return DaemonLaunchRequest(
            executableURL: launchTarget.executableURL,
            arguments: launchTarget.arguments,
            environment: environment,
            currentDirectoryURL: launchTarget.currentDirectoryURL
        )
    }

    private func defaultExecutableName(for config: CronaConfig) -> String {
        switch config.environment {
        case .production:
            return config.defaultKernelExecutable
        case .development:
            return config.defaultDevKernelExecutable
        }
    }

    private struct ResolvedLaunchTarget {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL?
    }

    private func resolveLaunchTarget(for pathOrName: String) throws -> ResolvedLaunchTarget {
        if pathOrName.hasPrefix("/") {
            guard FileManager.default.isExecutableFile(atPath: pathOrName) else {
                throw CronaConnectionFailure.transport(
                    "The daemon executable is not executable at \(pathOrName)."
                )
            }
            return ResolvedLaunchTarget(
                executableURL: URL(fileURLWithPath: pathOrName),
                arguments: [],
                currentDirectoryURL: nil
            )
        }

        let fileManager = FileManager.default
        for candidate in launchCandidates(named: pathOrName, fileManager: fileManager) {
            if fileManager.isExecutableFile(atPath: candidate.executableURL.path) {
                return candidate
            }
        }

        throw CronaConnectionFailure.transport(
            "The daemon executable \(pathOrName) could not be found on the system."
        )
    }

    private func launchCandidates(named binaryName: String, fileManager: FileManager) -> [ResolvedLaunchTarget] {
        var candidates: [ResolvedLaunchTarget] = []
        var seen = Set<String>()

        func add(_ target: ResolvedLaunchTarget) {
            let key = [
                target.executableURL.path,
                target.arguments.joined(separator: "\0"),
                target.currentDirectoryURL?.path ?? ""
            ].joined(separator: "\u{1F}")
            guard seen.insert(key).inserted else { return }
            candidates.append(target)
        }

        if let appExecutablePath = Bundle.main.executableURL?.path {
            let siblingPath = URL(fileURLWithPath: appExecutablePath)
                .deletingLastPathComponent()
                .appendingPathComponent(binaryName)
                .path
            add(
                ResolvedLaunchTarget(
                    executableURL: URL(fileURLWithPath: siblingPath),
                    arguments: [],
                    currentDirectoryURL: nil
                )
            )
        }

        if let pathResolved = resolveFromPath(binaryName) {
            add(
                ResolvedLaunchTarget(
                    executableURL: URL(fileURLWithPath: pathResolved),
                    arguments: [],
                    currentDirectoryURL: nil
                )
            )
        }

        if let repoRoot = findRepoRoot(fileManager: fileManager) {
            let repoBinPath = repoRoot.appendingPathComponent("bin").appendingPathComponent(binaryName).path
            add(
                ResolvedLaunchTarget(
                    executableURL: URL(fileURLWithPath: repoBinPath),
                    arguments: [],
                    currentDirectoryURL: nil
                )
            )

            let goEntrypoint = repoRoot.appendingPathComponent("kernel/cmd/crona-kernel").path
            if fileManager.fileExists(atPath: goEntrypoint),
               let goBinary = resolveFromPath("go") {
                add(
                    ResolvedLaunchTarget(
                        executableURL: URL(fileURLWithPath: goBinary),
                        arguments: ["run", "./kernel/cmd/crona-kernel"],
                        currentDirectoryURL: repoRoot
                    )
                )
            }
        }

        return candidates
    }

    private func resolveFromPath(_ binaryName: String) -> String? {
        let fileManager = FileManager.default
        var searchDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        searchDirectories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ])

        for directory in Array(NSOrderedSet(array: searchDirectories)) {
            guard let directory = directory as? String, !directory.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(binaryName).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func findRepoRoot(fileManager: FileManager) -> URL? {
        var starts: [URL] = []
        starts.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))
        if let executableURL = Bundle.main.executableURL {
            starts.append(executableURL.deletingLastPathComponent())
        }

        var seen = Set<String>()
        for start in starts {
            var current = start
            while seen.insert(current.path).inserted {
                let goWork = current.appendingPathComponent("go.work").path
                let kernelEntrypoint = current.appendingPathComponent("kernel/cmd/crona-kernel").path
                if fileManager.fileExists(atPath: goWork), fileManager.fileExists(atPath: kernelEntrypoint) {
                    return current
                }

                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }
        return nil
    }
}
