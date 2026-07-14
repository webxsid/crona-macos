import Foundation

struct CronaKernelInfo: Codable, Equatable {
    let pid: Int
    let port: Int?
    let transport: String?
    let endpoint: String?
    let socketPath: String?
    let protocolVersion: String
    let token: String?
    let startedAt: String?
    let scratchDir: String?
    let env: String?
    let executablePath: String?
    let runningChannel: String?
    let runningIsBeta: Bool?
}

struct CronaHealth: Codable, Equatable {
    let status: String
    let db: Bool
    let ok: Int
    let uptime: Double
}

struct CronaAlertStatus: Codable, Equatable {
    let notificationsAvailable: Bool
    let soundAvailable: Bool
    let notificationBackend: String?
    let soundBackend: String?
    let notificationOptions: [String]
    let soundOptions: [String]
    let subtitleSupported: Bool
    let urgencySupported: Bool
    let iconSupported: Bool
    let bundledSoundSupported: Bool
    let iconPath: String?
    let availableSoundPresets: [String]
}

struct CronaActiveContext: Codable, Equatable {
    let userID: String
    let deviceID: String
    let repoID: Int64?
    let repoName: String?
    let streamID: Int64?
    let streamName: String?
    let issueID: Int64?
    let issueTitle: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case deviceID = "deviceId"
        case repoID = "repoId"
        case repoName = "repoName"
        case streamID = "streamId"
        case streamName = "streamName"
        case issueID = "issueId"
        case issueTitle = "issueTitle"
        case updatedAt = "updatedAt"
    }
}

struct CronaTimerState: Codable, Equatable {
    let state: String
    let sessionID: String?
    let sessionStartTime: String?
    let issueID: Int64?
    let segmentType: String?
    let segmentStartTime: String?
    let segmentElapsedOffsetSeconds: Int?
    let readySegmentType: String?
    let nextSegmentType: String?
    let elapsedSeconds: Int?
    let hardLimitActive: Bool?
    let hardLimitExpired: Bool?
    let hardLimitTotalSeconds: Int?
    let hardLimitRemainingSeconds: Int?
    let hardLimitWorkSeconds: Int?
    let hardLimitBreakSeconds: Int?
    let hardLimitLongBreakSeconds: Int?
    let hardLimitCyclesBeforeLongBreak: Int?

    enum CodingKeys: String, CodingKey {
        case state = "state"
        case sessionID = "sessionId"
        case sessionStartTime = "sessionStartTime"
        case issueID = "issueId"
        case segmentType = "segmentType"
        case segmentStartTime = "segmentStartTime"
        case segmentElapsedOffsetSeconds = "segmentElapsedOffsetSeconds"
        case readySegmentType = "readySegmentType"
        case nextSegmentType = "nextSegmentType"
        case elapsedSeconds = "elapsedSeconds"
        case hardLimitActive = "hardLimitActive"
        case hardLimitExpired = "hardLimitExpired"
        case hardLimitTotalSeconds = "hardLimitTotalSeconds"
        case hardLimitRemainingSeconds = "hardLimitRemainingSeconds"
        case hardLimitWorkSeconds = "hardLimitWorkSeconds"
        case hardLimitBreakSeconds = "hardLimitBreakSeconds"
        case hardLimitLongBreakSeconds = "hardLimitLongBreakSeconds"
        case hardLimitCyclesBeforeLongBreak = "hardLimitCyclesBeforeLongBreak"
    }
}

struct CronaIssue: Codable, Equatable, Identifiable {
    let id: Int64
    let streamID: Int64
    let title: String
    let status: String
    let estimateMinutes: Int?
    let workedSeconds: Int
    let pinnedDaily: Bool
    let todoForDate: String?
    let completedAt: String?
    let abandonedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case streamID = "streamId"
        case title = "title"
        case status = "status"
        case estimateMinutes = "estimateMinutes"
        case workedSeconds = "workedSeconds"
        case pinnedDaily = "pinnedDaily"
        case todoForDate = "todoForDate"
        case completedAt = "completedAt"
        case abandonedAt = "abandonedAt"
    }
}

struct CronaDailyIssueSummary: Codable, Equatable {
    let date: String
    let totalIssues: Int
    let issues: [CronaIssue]
    let totalEstimatedMinutes: Int
    let completedIssues: Int
    let abandonedIssues: Int
    let workedSeconds: Int
}

struct CronaDailyPlanEntry: Codable, Equatable, Identifiable {
    let id: String
    let date: String
    let issueID: Int64
    let source: String
    let status: String
    let committedAt: String
    let baselineDate: String
    let currentPlannedDate: String
    let postponeCount: Int
    let currentDelayedDays: Int
    let maxDelayedDays: Int
    let failScore: Double

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case date = "date"
        case issueID = "issueId"
        case source = "source"
        case status = "status"
        case committedAt = "committedAt"
        case baselineDate = "baselineDate"
        case currentPlannedDate = "currentPlannedDate"
        case postponeCount = "postponeCount"
        case currentDelayedDays = "currentDelayedDays"
        case maxDelayedDays = "maxDelayedDays"
        case failScore = "failScore"
    }
}

struct CronaDailyPlan: Codable, Equatable {
    let id: String
    let date: String
    let createdAt: String
    let updatedAt: String
    let entries: [CronaDailyPlanEntry]
}

struct CronaHabitWithMeta: Decodable, Equatable, Identifiable {
    let id: Int64
    let streamID: Int64
    let name: String
    let description: String?
    let scheduleType: String
    let weekdays: [Int]
    let targetMinutes: Int?
    let active: Bool
    let repoID: Int64
    let repoName: String
    let streamName: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case streamID = "streamId"
        case name = "name"
        case description = "description"
        case scheduleType = "scheduleType"
        case weekdays = "weekdays"
        case targetMinutes = "targetMinutes"
        case active = "active"
        case repoID = "repoId"
        case repoName = "repoName"
        case streamName = "streamName"
    }
}

struct CronaHabitDailyItem: Decodable, Equatable, Identifiable {
    let habit: CronaHabitWithMeta
    let status: String
    let completed: Bool
    let completionID: Int64?
    let completionDate: String?
    let durationMinutes: Int?
    let notes: String?

    var id: Int64 { habit.id }
    var name: String { habit.name }
    var repoName: String { habit.repoName }
    var streamName: String { habit.streamName }
    var targetMinutes: Int? { habit.targetMinutes }

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case streamID = "streamId"
        case name = "name"
        case description = "description"
        case scheduleType = "scheduleType"
        case weekdays = "weekdays"
        case targetMinutes = "targetMinutes"
        case active = "active"
        case repoID = "repoId"
        case repoName = "repoName"
        case streamName = "streamName"
        case status = "status"
        case completed = "completed"
        case completionID = "completionId"
        case completionDate = "completionDate"
        case durationMinutes = "durationMinutes"
        case notes = "notes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let habit = CronaHabitWithMeta(
            id: try container.decode(Int64.self, forKey: .id),
            streamID: try container.decode(Int64.self, forKey: .streamID),
            name: try container.decode(String.self, forKey: .name),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            scheduleType: try container.decode(String.self, forKey: .scheduleType),
            weekdays: try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? [],
            targetMinutes: try container.decodeIfPresent(Int.self, forKey: .targetMinutes),
            active: try container.decode(Bool.self, forKey: .active),
            repoID: try container.decode(Int64.self, forKey: .repoID),
            repoName: try container.decode(String.self, forKey: .repoName),
            streamName: try container.decode(String.self, forKey: .streamName)
        )
        self.habit = habit
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "completed"
        self.completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? (status == "completed")
        self.completionID = try container.decodeIfPresent(Int64.self, forKey: .completionID)
        self.completionDate = try container.decodeIfPresent(String.self, forKey: .completionDate)
        self.durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct CronaHabitCompletion: Decodable, Equatable, Identifiable {
    let id: Int64
    let habitID: Int64
    let date: String
    let status: String
    let durationMinutes: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case habitID = "habitId"
        case date = "date"
        case status = "status"
        case durationMinutes = "durationMinutes"
        case notes = "notes"
    }
}

struct CronaDateRangeQuery: Codable, Equatable {
    let start: String
    let end: String
}

struct CronaDashboardSummaryQuery: Codable, Equatable {
    let start: String
    let end: String
    let groupBy: String?
    let repoID: Int64?
    let streamID: Int64?
    let issueID: Int64?

    enum CodingKeys: String, CodingKey {
        case start = "start"
        case end = "end"
        case groupBy = "groupBy"
        case repoID = "repoId"
        case streamID = "streamId"
        case issueID = "issueId"
    }
}

struct CronaDailyMetricsDay: Codable, Equatable {
    let date: String
    let workedSeconds: Int
    let restSeconds: Int
    let sessionCount: Int
    let totalIssues: Int
    let completedIssues: Int
    let abandonedIssues: Int
    let totalEstimatedMinutes: Int
    let habitDueCount: Int
    let habitCompletedCount: Int
    let habitFailedCount: Int
}

struct CronaFocusScoreSummary: Codable, Equatable {
    let startDate: String
    let endDate: String
    let score: Int
    let level: String
    let workedSeconds: Int
    let restSeconds: Int
    let sessionCount: Int
    let focusDays: Int
    let days: Int
    let targetWorkedSeconds: Int
}

struct CronaTimerStartRequest: Codable, Equatable {
    let repoID: Int64?
    let streamID: Int64?
    let issueID: Int64?
    let hardLimitTotalSeconds: Int?
    let hardLimitWorkSeconds: Int?
    let hardLimitBreakSeconds: Int?
    let hardLimitLongBreakSeconds: Int?
    let hardLimitCyclesBeforeLongBreak: Int?

    enum CodingKeys: String, CodingKey {
        case repoID = "repoId"
        case streamID = "streamId"
        case issueID = "issueId"
        case hardLimitTotalSeconds = "hardLimitTotalSeconds"
        case hardLimitWorkSeconds = "hardLimitWorkSeconds"
        case hardLimitBreakSeconds = "hardLimitBreakSeconds"
        case hardLimitLongBreakSeconds = "hardLimitLongBreakSeconds"
        case hardLimitCyclesBeforeLongBreak = "hardLimitCyclesBeforeLongBreak"
    }
}

struct CronaTimerExtendRequest: Codable, Equatable {
    let additionalSeconds: Int
    let additionalSessions: Int
    let hardLimitTotalSeconds: Int?
    let hardLimitWorkSeconds: Int?
    let hardLimitBreakSeconds: Int?
    let hardLimitLongBreakSeconds: Int?
    let hardLimitCyclesBeforeLongBreak: Int?

    enum CodingKeys: String, CodingKey {
        case additionalSeconds = "additionalSeconds"
        case additionalSessions = "additionalSessions"
        case hardLimitTotalSeconds = "hardLimitTotalSeconds"
        case hardLimitWorkSeconds = "hardLimitWorkSeconds"
        case hardLimitBreakSeconds = "hardLimitBreakSeconds"
        case hardLimitLongBreakSeconds = "hardLimitLongBreakSeconds"
        case hardLimitCyclesBeforeLongBreak = "hardLimitCyclesBeforeLongBreak"
    }
}

struct CronaEndSessionRequest: Codable, Equatable {
    let commitMessage: String

    enum CodingKeys: String, CodingKey {
        case commitMessage = "commitMessage"
    }
}

struct CronaListHabitsDueQuery: Codable, Equatable {
    let date: String
}

struct CronaHabitCompletionUpsertRequest: Codable, Equatable {
    let habitID: Int64
    let date: String
    let status: String?
    let durationMinutes: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case habitID = "habitId"
        case date = "date"
        case status = "status"
        case durationMinutes = "durationMinutes"
        case notes = "notes"
    }
}

struct CronaOKResponse: Codable, Equatable {
    let ok: Bool
}

nonisolated struct CronaProtocolEvent: Decodable, Equatable {
    let type: String
    let payload: JSONValue?

    var sessionID: String? {
        guard case let .object(object) = payload else { return nil }
        return object["sessionId"]?.stringValue
    }
}

nonisolated enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON payload"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum CronaConnectionFailure: Error, Equatable, LocalizedError {
    case missingDiscovery
    case missingEndpoint
    case incompatibleProtocol(expected: String, actual: String)
    case unsupportedTransport(String)
    case transport(String)
    case malformedResponse

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .missingDiscovery:
            return "No kernel discovery file was found."
        case .missingEndpoint:
            return "The kernel discovery file did not include an endpoint."
        case let .incompatibleProtocol(expected, actual):
            return "Protocol mismatch. Expected \(expected), received \(actual)."
        case let .unsupportedTransport(transport):
            return "Unsupported transport: \(transport)."
        case let .transport(message):
            return message
        case .malformedResponse:
            return "The daemon returned an invalid response."
        }
    }
}

struct CronaRPCError: Codable, Error, Equatable, LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? {
        "\(code): \(message)"
    }
}

struct CronaKernelRequestEnvelope: Encodable {
    let id: String
    let method: String
    let params: AnyEncodable?

    enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
    }
}

struct CronaKernelResponseEnvelope<Result: Decodable>: Decodable {
    let id: String?
    let result: Result?
    let error: CronaRPCError?
}

struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeClosure = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
