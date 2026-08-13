import Combine
import Foundation
import OSLog

struct IssueDestination: Equatable, Identifiable {
    let repoID: Int64
    let repoName: String
    let streamID: Int64
    let streamName: String

    var id: Int64 { streamID }
    var label: String { "\(repoName) / \(streamName)" }
}

@MainActor
final class IssueCreationService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let logger = Logger(subsystem: "com.crona.macos", category: "issueCreation")

    @Published private(set) var destinations: [IssueDestination] = []
    @Published private(set) var isLoadingDestinations = false
    @Published private(set) var isCreating = false
    @Published private(set) var lastErrorMessage: String?

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
    }

    func loadDestinations() async {
        guard !isLoadingDestinations else { return }
        isLoadingDestinations = true
        lastErrorMessage = nil
        defer { isLoadingDestinations = false }
        do {
            let repos = try await daemonConnection.withClient { try await $0.listRepos() }
            var loaded: [IssueDestination] = []
            for repo in repos {
                let streams = try await daemonConnection.withClient { try await $0.listStreams(repoID: repo.id) }
                loaded.append(contentsOf: streams.map {
                    IssueDestination(repoID: repo.id, repoName: repo.name, streamID: $0.id, streamName: $0.name)
                })
            }
            destinations = loaded.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        } catch {
            logger.error("Loading issue destinations failed: \(error.localizedDescription, privacy: .private)")
            lastErrorMessage = error.localizedDescription
        }
    }

    func create(_ request: CronaCreateIssueRequest) async -> CronaIssue? {
        guard !isCreating else { return nil }
        isCreating = true
        lastErrorMessage = nil
        defer { isCreating = false }
        do {
            return try await daemonConnection.withClient { try await $0.createIssue(request) }
        } catch {
            logger.error("Creating issue failed: \(error.localizedDescription, privacy: .private)")
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func clearError() { lastErrorMessage = nil }
}
