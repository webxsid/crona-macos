import Combine
import Foundation

struct WellbeingSnapshot: Equatable {
    var date = ""
    var checkIn: CronaDailyCheckIn?
    var isLoading = false
    var isSaving = false
    var lastErrorDescription: String?
}

@MainActor
final class WellbeingService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    @Published private(set) var snapshot = WellbeingSnapshot()

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
    }

    func refresh(date requestedDate: String? = nil) async {
        let date = requestedDate ?? daemonConnection.currentDate
        let resolvedDate = date.isEmpty ? DailyFocusService.todayString() : date
        snapshot.date = resolvedDate
        snapshot.isLoading = true
        snapshot.lastErrorDescription = nil
        defer { snapshot.isLoading = false }
        do {
            snapshot.checkIn = try await daemonConnection.withClient {
                try await $0.checkInGet(date: resolvedDate)
            }
        } catch {
            snapshot.lastErrorDescription = error.localizedDescription
        }
    }

    @discardableResult
    func save(_ request: CronaDailyCheckInUpsertRequest) async -> Bool {
        snapshot.isSaving = true
        snapshot.lastErrorDescription = nil
        defer { snapshot.isSaving = false }
        do {
            snapshot.checkIn = try await daemonConnection.withClient {
                try await $0.checkInUpsert(request)
            }
            return true
        } catch {
            snapshot.lastErrorDescription = error.localizedDescription
            return false
        }
    }
}
