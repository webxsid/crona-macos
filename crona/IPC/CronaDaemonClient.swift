import Foundation
import OSLog

#if os(macOS)
import Darwin
#endif

protocol CronaDaemonTransport {
    func send(_ request: Data) async throws -> Data
    func openEventStream(with request: Data) async throws -> AsyncThrowingStream<CronaProtocolEvent, Error>
}

private let ipcLogger = Logger(subsystem: "com.crona.macos", category: "ipc")

struct CronaUnixDomainSocketTransport: CronaDaemonTransport {
    let endpoint: String

    func send(_ request: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try sendOverUnixSocket(request, endpoint: endpoint))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func openEventStream(with request: Data) async throws -> AsyncThrowingStream<CronaProtocolEvent, Error> {
        AsyncThrowingStream { continuation in
            let endpoint = endpoint
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    ipcLogger.debug("Opening daemon event stream for endpoint: \(endpoint, privacy: .public)")
                    let descriptor = try connectSocket(endpoint: endpoint)
                    try writeAll(descriptor, requestWithNewline(request))
                    var pending = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)

                    while true {
                        let bytesRead = read(descriptor, &buffer, buffer.count)
                        guard bytesRead >= 0 else {
                            let error = CronaConnectionFailure.transport("Failed to read from the daemon socket.")
                            ipcLogger.error("Daemon event stream read failed for endpoint: \(endpoint, privacy: .public)")
                            close(descriptor)
                            continuation.finish(throwing: error)
                            return
                        }

                        guard bytesRead > 0 else {
                            ipcLogger.debug("Daemon event stream closed by peer for endpoint: \(endpoint, privacy: .public)")
                            close(descriptor)
                            continuation.finish()
                            return
                        }

                        pending.append(buffer, count: bytesRead)

                        while let newlineIndex = pending.firstIndex(of: 0x0A) {
                            let line = pending.prefix(upTo: newlineIndex)
                            pending.removeSubrange(...newlineIndex)

                            guard !line.isEmpty else {
                                continue
                            }

                            do {
                                let event = try JSONDecoder.crona.decode(CronaProtocolEvent.self, from: Data(line))
                                ipcLogger.debug("Received daemon event: \(event.type, privacy: .public)")
                                continuation.yield(event)
                            } catch {
                                let rawLine = String(data: Data(line), encoding: .utf8) ?? "<non-utf8>"
                                ipcLogger.error("Failed to decode daemon event frame: \(rawLine, privacy: .public)")
                                continue
                            }
                        }
                    }
                } catch {
                    ipcLogger.error("Failed to open daemon event stream for endpoint: \(endpoint, privacy: .public), error: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

final class CronaDaemonClient {
    private let transport: CronaDaemonTransport

    init(transport: CronaDaemonTransport) {
        self.transport = transport
    }

    convenience init(endpoint: String) {
        self.init(transport: CronaUnixDomainSocketTransport(endpoint: endpoint))
    }

    func healthGet() async throws -> CronaHealth {
        try await request(method: "health.get")
    }

    func kernelInfoGet() async throws -> CronaKernelInfo {
        try await request(method: "kernel.info.get")
    }

    func contextGet() async throws -> CronaActiveContext {
        try await request(method: "context.get")
    }

    func optionalContextGet() async throws -> CronaActiveContext? {
        try await request(method: "context.get")
    }

    func timerGetState() async throws -> CronaTimerState {
        try await request(method: "timer.get_state")
    }

    func timerStart(_ input: CronaTimerStartRequest) async throws -> CronaTimerState {
        try await request(method: "timer.start", params: AnyEncodable(input))
    }

    func timerPause() async throws -> CronaTimerState {
        try await request(method: "timer.pause")
    }

    func timerResume() async throws -> CronaTimerState {
        try await request(method: "timer.resume")
    }

    func timerExtend(_ input: CronaTimerExtendRequest) async throws -> CronaTimerState {
        try await request(method: "timer.extend", params: AnyEncodable(input))
    }

    func timerEnd(commitMessage: String) async throws -> CronaOKResponse {
        try await request(method: "timer.end", params: AnyEncodable(CronaEndSessionRequest(commitMessage: commitMessage)))
    }

    func issueTodaySummary() async throws -> CronaDailyIssueSummary {
        try await request(method: "issue.today_summary")
    }

    func dailyPlanGet(date: String) async throws -> CronaDailyPlan {
        try await request(method: "daily_plan.get", params: AnyEncodable(CronaDailyPlanQuery(date: date)))
    }

    func listDueHabits(date: String) async throws -> [CronaHabitDailyItem] {
        try await request(method: "habit.list_due", params: AnyEncodable(CronaListHabitsDueQuery(date: date)))
    }

    func completeHabit(
        habitID: Int64,
        date: String,
        status: String = "completed",
        durationMinutes: Int? = nil,
        notes: String? = nil
    ) async throws -> CronaHabitCompletion {
        try await request(
            method: "habit.complete",
            params: AnyEncodable(
                CronaHabitCompletionUpsertRequest(
                    habitID: habitID,
                    date: date,
                    status: status,
                    durationMinutes: durationMinutes,
                    notes: notes
                )
            )
        )
    }

    func uncompleteHabit(habitID: Int64, date: String) async throws -> CronaOKResponse {
        try await request(
            method: "habit.uncomplete",
            params: AnyEncodable(
                CronaHabitCompletionUpsertRequest(
                    habitID: habitID,
                    date: date,
                    status: nil,
                    durationMinutes: nil,
                    notes: nil
                )
            )
        )
    }

    func metricsRange(start: String, end: String) async throws -> [CronaDailyMetricsDay] {
        try await request(method: "metrics.range", params: AnyEncodable(CronaDateRangeQuery(start: start, end: end)))
    }

    func dashboardFocusScore(start: String, end: String) async throws -> CronaFocusScoreSummary {
        try await request(method: "dashboard.focus_score", params: AnyEncodable(CronaDashboardSummaryQuery(start: start, end: end, groupBy: nil, repoID: nil, streamID: nil, issueID: nil)))
    }

    func alertsStatusGet() async throws -> CronaAlertStatus {
        try await request(method: "alerts.status.get")
    }

    func alertsTestNotification() async throws -> CronaOKResponse {
        try await request(method: "alerts.test_notification")
    }

    func subscribeToEvents() async throws -> AsyncThrowingStream<CronaProtocolEvent, Error> {
        let envelope = CronaKernelRequestEnvelope(id: UUID().uuidString, method: "events.subscribe", params: nil)
        let requestData = try JSONEncoder.crona.encode(envelope)
        ipcLogger.debug("Sending events.subscribe request")
        return try await transport.openEventStream(with: requestData)
    }

    func request<Response: Decodable>(method: String, params: AnyEncodable? = nil) async throws -> Response {
        let envelope = CronaKernelRequestEnvelope(id: UUID().uuidString, method: method, params: params)
        let requestData = try JSONEncoder.crona.encode(envelope)
        let responseData = try await transport.send(requestData)
        let decoded = try JSONDecoder.crona.decode(CronaKernelResponseEnvelope<Response>.self, from: responseData)

        if let error = decoded.error {
            throw error
        }

        guard let result = decoded.result else {
            throw CronaConnectionFailure.malformedResponse
        }

        return result
    }
}

struct CronaDailyPlanQuery: Codable { let date: String }

private func requestWithNewline(_ request: Data) -> Data {
    var payload = Data(request)
    payload.append(0x0A)
    return payload
}

#if os(macOS)
private func sendOverUnixSocket(_ request: Data, endpoint: String) throws -> Data {
    let descriptor = try connectSocket(endpoint: endpoint)
    defer { close(descriptor) }
    try writeAll(descriptor, requestWithNewline(request))
    return try readLine(descriptor)
}

private func connectSocket(endpoint: String) throws -> Int32 {
    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
        throw CronaConnectionFailure.transport("Failed to create socket.")
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let socketPathBytes = endpoint.utf8CString
    let pathLengthLimit = withUnsafeBytes(of: &address.sun_path) { $0.count }
    guard socketPathBytes.count <= pathLengthLimit else {
        close(fileDescriptor)
        throw CronaConnectionFailure.transport("The socket path is too long.")
    }

    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.initializeMemory(as: CChar.self, repeating: 0)
        socketPathBytes.withUnsafeBytes { bytes in
            buffer.copyBytes(from: bytes)
        }
    }

    let connectResult = withUnsafePointer(to: &address) { pointer -> Int32 in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            connect(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        close(fileDescriptor)
        throw CronaConnectionFailure.transport("Failed to connect to the daemon socket.")
    }

    return fileDescriptor
}

private func writeAll(_ fileDescriptor: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
            throw CronaConnectionFailure.transport("Failed to encode daemon request.")
        }

        var bytesRemaining = data.count
        var cursor = baseAddress

        while bytesRemaining > 0 {
            let bytesWritten = write(fileDescriptor, cursor, bytesRemaining)
            guard bytesWritten >= 0 else {
                throw CronaConnectionFailure.transport("Failed to write to the daemon socket.")
            }
            bytesRemaining -= bytesWritten
            cursor += bytesWritten
        }
    }
}

private func readLine(_ fileDescriptor: Int32) throws -> Data {
    var buffer = [UInt8](repeating: 0, count: 4096)
    var data = Data()

    while true {
        let bytesRead = read(fileDescriptor, &buffer, buffer.count)
        guard bytesRead >= 0 else {
            throw CronaConnectionFailure.transport("Failed to read from the daemon socket.")
        }
        guard bytesRead > 0 else {
            break
        }

        if let newline = buffer[..<bytesRead].firstIndex(of: 0x0A) {
            data.append(buffer, count: newline)
            break
        }

        data.append(buffer, count: bytesRead)
    }

    return data
}
#endif

private extension JSONDecoder {
    static var crona: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}

private extension JSONEncoder {
    static var crona: JSONEncoder {
        let encoder = JSONEncoder()
        return encoder
    }
}
