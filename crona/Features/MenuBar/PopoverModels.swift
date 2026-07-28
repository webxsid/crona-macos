import Foundation

enum PopoverScreen: Equatable {
    case active(ActiveTimerPopoverModel)
    case idle(IdleFocusPopoverModel)
    case startConfig(FocusStartConfigModel)
    case disconnected
    case error(message: String)
}

struct PopoverViewModel: Equatable {
    let screen: PopoverScreen
    let connectionState: CompanionConnectionState
    let timerSnapshot: TimerSnapshot
    let contextSnapshot: ContextSnapshot
    let lastErrorDescription: String?

    var statusSymbolName: String {
        switch connectionState {
        case .connected:
            switch timerSnapshot.state {
            case "running": return "play.circle.fill"
            case "paused": return "pause.circle.fill"
            case "expired": return "hourglass.circle.fill"
            case "idle": return "circle"
            default: return "circle"
            }
        case .connecting:
            return "arrow.triangle.2.circlepath.circle"
        case .incompatible, .error:
            return "exclamationmark.triangle.fill"
        case .disconnected, .idle:
            return "bolt.horizontal.circle"
        }
    }
}

struct ActiveTimerPopoverModel: Equatable {
    let presentation: TimerPresentation
    let timerSnapshot: TimerSnapshot
    let contextSnapshot: ContextSnapshot
}

struct IdleFocusPopoverModel: Equatable {
    let issues: [DailyFocusIssue]
    let date: String
}

struct FocusStartConfigModel: Equatable {
    let issue: DailyFocusIssue
    let state: FocusStartConfigState
}

enum PopoverTab: String, CaseIterable, Equatable, Identifiable {
    case now
    case habits
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Daily"
        case .habits: return "Habits"
        case .stats: return "Stats"
        }
    }
}

struct StatsPopoverModel: Equatable {
    let snapshot: PopoverStatsSnapshot
}

enum FocusSessionMode: String, CaseIterable, Equatable, Identifiable {
    case stopwatch
    case pomodoro
    case timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stopwatch: return "Stopwatch"
        case .pomodoro: return "Pomodoro"
        case .timer: return "Timer"
        }
    }
}

enum FocusPresetChoice: String, CaseIterable, Equatable, Identifiable {
    case preset25
    case preset50
    case preset90
    case preset5
    case preset10
    case preset15
    case preset20
    case preset30
    case noBreak
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preset25: return "25m"
        case .preset50: return "50m"
        case .preset90: return "90m"
        case .preset5: return "5m"
        case .preset10: return "10m"
        case .preset15: return "15m"
        case .preset20: return "20m"
        case .preset30: return "30m"
        case .noBreak: return "No Break"
        case .custom: return "Custom"
        }
    }

    var minutesValue: Int? {
        switch self {
        case .preset25: return 25
        case .preset50: return 50
        case .preset90: return 90
        case .preset5: return 5
        case .preset10: return 10
        case .preset15: return 15
        case .preset20: return 20
        case .preset30: return 30
        case .noBreak, .custom: return nil
        }
    }
}

struct FocusStartConfigState: Equatable {
    var mode: FocusSessionMode = .stopwatch
    var focusChoice: FocusPresetChoice = .preset25
    var breakChoice: FocusPresetChoice = .preset5
    var longBreakChoice: FocusPresetChoice = .preset15
    var countdownChoice: FocusPresetChoice = .preset25
    var customFocusMinutes = 25
    var customBreakMinutes = 5
    var customLongBreakMinutes = 15
    var customCountdownMinutes = 25
    var pomodoroCycles = 4
    var pomodoroCyclesBeforeLongBreak = 4
    var extendMinutes = 25
    var extendSessions = 1

    init(
        mode: FocusSessionMode = .stopwatch,
        focusChoice: FocusPresetChoice = .preset25,
        breakChoice: FocusPresetChoice = .preset5,
        longBreakChoice: FocusPresetChoice = .preset15,
        countdownChoice: FocusPresetChoice = .preset25,
        customFocusMinutes: Int = 25,
        customBreakMinutes: Int = 5,
        customLongBreakMinutes: Int = 15,
        customCountdownMinutes: Int = 25,
        pomodoroCycles: Int = 4,
        pomodoroCyclesBeforeLongBreak: Int = 4,
        extendMinutes: Int = 25,
        extendSessions: Int = 1
    ) {
        self.mode = mode
        self.focusChoice = focusChoice
        self.breakChoice = breakChoice
        self.longBreakChoice = longBreakChoice
        self.countdownChoice = countdownChoice
        self.customFocusMinutes = customFocusMinutes
        self.customBreakMinutes = customBreakMinutes
        self.customLongBreakMinutes = customLongBreakMinutes
        self.customCountdownMinutes = customCountdownMinutes
        self.pomodoroCycles = pomodoroCycles
        self.pomodoroCyclesBeforeLongBreak = pomodoroCyclesBeforeLongBreak
        self.extendMinutes = extendMinutes
        self.extendSessions = extendSessions
    }

    static let focusChoices: [FocusPresetChoice] = [.preset25, .preset50, .preset90, .custom]
    static let shortBreakChoices: [FocusPresetChoice] = [.preset5, .preset10, .preset15, .noBreak, .custom]
    static let longBreakChoices: [FocusPresetChoice] = [.preset15, .preset20, .preset30, .noBreak, .custom]
    static let countdownChoices: [FocusPresetChoice] = [.preset25, .preset50, .preset90, .custom]

    static func defaultState(estimateMinutes: Int?, workedSeconds: Int) -> FocusStartConfigState {
        let remainingMinutes = remainingEstimateMinutes(estimateMinutes: estimateMinutes, workedSeconds: workedSeconds)
        let countdownMinutes = remainingMinutes ?? 25
        return FocusStartConfigState(
            mode: .stopwatch,
            focusChoice: .preset25,
            breakChoice: .preset5,
            longBreakChoice: .preset15,
            countdownChoice: countdownChoice(for: countdownMinutes),
            customFocusMinutes: 25,
            customBreakMinutes: 5,
            customLongBreakMinutes: 15,
            customCountdownMinutes: countdownMinutes,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4,
            extendMinutes: countdownMinutes,
            extendSessions: 1
        )
    }

    var resolvedFocusMinutes: Int {
        resolvedMinutes(for: focusChoice, customMinutes: customFocusMinutes, fallback: 25, allowZero: false)
    }

    var resolvedBreakMinutes: Int {
        resolvedMinutes(for: breakChoice, customMinutes: customBreakMinutes, fallback: 5, allowZero: true)
    }

    var resolvedLongBreakMinutes: Int {
        resolvedMinutes(for: longBreakChoice, customMinutes: customLongBreakMinutes, fallback: 15, allowZero: true)
    }

    var resolvedCountdownMinutes: Int {
        resolvedMinutes(for: countdownChoice, customMinutes: customCountdownMinutes, fallback: 25, allowZero: false)
    }

    var configuredDurationSeconds: Int? {
        switch mode {
        case .stopwatch:
            return nil
        case .pomodoro:
            return pomodoroValues.totalSeconds
        case .timer:
            return max(1, resolvedCountdownMinutes) * 60
        }
    }

    var effectivePomodoroCycles: Int {
        breaksEnabled ? max(1, pomodoroCycles) : 1
    }

    var effectiveCyclesBeforeLongBreak: Int {
        longBreakEnabled ? max(1, pomodoroCyclesBeforeLongBreak) : 0
    }

    var breaksEnabled: Bool {
        resolvedBreakMinutes > 0
    }

    var longBreakEnabled: Bool {
        breaksEnabled && resolvedLongBreakMinutes > 0
    }

    var showsCustomFocusField: Bool {
        mode == .pomodoro && focusChoice == .custom
    }

    var showsCustomBreakField: Bool {
        mode == .pomodoro && breakChoice == .custom
    }

    var showsCustomLongBreakField: Bool {
        mode == .pomodoro && breaksEnabled && longBreakChoice == .custom
    }

    var showsCustomCountdownField: Bool {
        mode == .timer && countdownChoice == .custom
    }

    var showsBreakControls: Bool {
        mode == .pomodoro
    }

    var showsLongBreakControls: Bool {
        mode == .pomodoro && breaksEnabled
    }

    var showsCycleControls: Bool {
        mode == .pomodoro && breaksEnabled
    }

    var showsLongBreakAfterControls: Bool {
        mode == .pomodoro && longBreakEnabled
    }

    func startRequest(for issue: DailyFocusIssue) -> CronaTimerStartRequest {
        switch mode {
        case .stopwatch:
            return CronaTimerStartRequest(
                repoID: nil,
                streamID: issue.streamID,
                issueID: issue.id,
                hardLimitTotalSeconds: nil,
                hardLimitWorkSeconds: nil,
                hardLimitBreakSeconds: nil,
                hardLimitLongBreakSeconds: nil,
                hardLimitCyclesBeforeLongBreak: nil
            )
        case .pomodoro:
            let values = pomodoroValues
            return CronaTimerStartRequest(
                repoID: nil,
                streamID: issue.streamID,
                issueID: issue.id,
                hardLimitKind: .pomodoro,
                hardLimitTotalSeconds: values.totalSeconds,
                hardLimitWorkSeconds: values.focusSeconds,
                hardLimitBreakSeconds: values.breakSeconds,
                hardLimitLongBreakSeconds: values.longBreakSeconds,
                hardLimitCyclesBeforeLongBreak: values.cyclesBeforeLongBreak
            )
        case .timer:
            let totalSeconds = max(1, resolvedCountdownMinutes) * 60
            return CronaTimerStartRequest(
                repoID: nil,
                streamID: issue.streamID,
                issueID: issue.id,
                hardLimitKind: .countdown,
                hardLimitTotalSeconds: totalSeconds,
                hardLimitWorkSeconds: nil,
                hardLimitBreakSeconds: nil,
                hardLimitLongBreakSeconds: nil,
                hardLimitCyclesBeforeLongBreak: nil
            )
        }
    }

    var extendRequest: CronaTimerExtendRequest? {
        switch mode {
        case .stopwatch:
            return nil
        case .timer:
            return CronaTimerExtendRequest(
                additionalSeconds: max(1, extendMinutes) * 60,
                additionalSessions: 0,
                hardLimitTotalSeconds: nil,
                hardLimitWorkSeconds: nil,
                hardLimitBreakSeconds: nil,
                hardLimitLongBreakSeconds: nil,
                hardLimitCyclesBeforeLongBreak: nil
            )
        case .pomodoro:
            let values = pomodoroValues
            return CronaTimerExtendRequest(
                additionalSeconds: 0,
                additionalSessions: max(1, extendSessions),
                hardLimitTotalSeconds: values.totalSeconds,
                hardLimitWorkSeconds: values.focusSeconds,
                hardLimitBreakSeconds: values.breakSeconds,
                hardLimitLongBreakSeconds: values.longBreakSeconds,
                hardLimitCyclesBeforeLongBreak: values.cyclesBeforeLongBreak
            )
        }
    }

    var pomodoroValues: (focusSeconds: Int?, breakSeconds: Int?, longBreakSeconds: Int?, cyclesBeforeLongBreak: Int?, totalSeconds: Int?) {
        let focusMinutes = max(1, resolvedFocusMinutes)
        let breakMinutes = breaksEnabled ? max(0, resolvedBreakMinutes) : 0
        let longBreakMinutes = longBreakEnabled ? max(0, resolvedLongBreakMinutes) : 0
        let cycles = breaksEnabled ? max(1, pomodoroCycles) : 1
        let cyclesBeforeLongBreak = longBreakEnabled ? max(1, pomodoroCyclesBeforeLongBreak) : 0

        let totalSeconds: Int
        if breakMinutes <= 0 {
            totalSeconds = focusMinutes * 60
        } else {
            totalSeconds = cycles * ((focusMinutes + breakMinutes) * 60) + max(0, cycles / max(1, cyclesBeforeLongBreak)) * max(0, (longBreakMinutes - breakMinutes) * 60)
        }

        return (
            focusMinutes * 60,
            breakMinutes * 60,
            longBreakMinutes * 60,
            cyclesBeforeLongBreak,
            totalSeconds
        )
    }

    private func resolvedMinutes(for choice: FocusPresetChoice, customMinutes: Int, fallback: Int, allowZero: Bool) -> Int {
        switch choice {
        case .custom:
            return max(allowZero ? 0 : 1, customMinutes)
        case .noBreak:
            return 0
        default:
            return max(allowZero ? 0 : 1, choice.minutesValue ?? fallback)
        }
    }

    private static func countdownChoice(for minutes: Int) -> FocusPresetChoice {
        switch minutes {
        case 25: return .preset25
        case 50: return .preset50
        case 90: return .preset90
        default: return .custom
        }
    }

    private static func remainingEstimateMinutes(estimateMinutes: Int?, workedSeconds: Int) -> Int? {
        guard let estimateMinutes, estimateMinutes > 0 else { return nil }
        let remaining = estimateMinutes - max(0, workedSeconds / 60)
        return remaining > 0 ? remaining : nil
    }
}

enum TimerEndProjection {
    static func startEndDate(
        config: FocusStartConfigState,
        now: Date = Date()
    ) -> Date? {
        guard let duration = config.configuredDurationSeconds, duration > 0 else {
            return nil
        }
        return now.addingTimeInterval(TimeInterval(duration))
    }

    static func activeEndDate(
        snapshot: TimerSnapshot,
        now: Date = Date()
    ) -> Date? {
        guard snapshot.sessionID != nil, snapshot.hardLimitActive else {
            return nil
        }
        let remaining = TimerPresentation.projectedDisplaySeconds(
            for: snapshot,
            at: now
        )
        return now.addingTimeInterval(TimeInterval(remaining))
    }

    static func extensionEndDate(
        snapshot: TimerSnapshot,
        request: CronaTimerExtendRequest,
        now: Date = Date()
    ) -> Date? {
        let addedSeconds: Int
        if request.additionalSeconds > 0 {
            addedSeconds = request.additionalSeconds
        } else {
            guard
                request.additionalSessions > 0,
                let perSession = request.hardLimitTotalSeconds,
                perSession > 0
            else {
                return nil
            }
            addedSeconds = perSession * request.additionalSessions
        }

        guard addedSeconds > 0 else { return nil }
        let remaining = TimerPresentation.projectedDisplaySeconds(
            for: snapshot,
            at: now
        )
        return now.addingTimeInterval(TimeInterval(remaining + addedSeconds))
    }
}

enum TimerEndTimeFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
