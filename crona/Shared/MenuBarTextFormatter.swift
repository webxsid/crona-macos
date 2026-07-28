import Foundation

enum MenuBarTextFormatter {
    static func statusItemTitle(
        preferences: CompanionPreferences,
        connectionState: CompanionConnectionState,
        timerSnapshot: TimerSnapshot,
        todayWorkedSeconds: Int? = nil,
        now: Date = Date()
    ) -> String {
        guard preferences.menuBarDisplayMode.showsText else {
            return ""
        }

        guard connectionState == .connected else { return "Offline" }

        switch timerSnapshot.state {
        case "running", "paused":
            return formatStatusTimer(
                seconds: TimerPresentation.projectedDisplaySeconds(
                    for: timerSnapshot,
                    at: now
                ),
                style: preferences.menuBarTimeFormat
            )
        default:
            switch preferences.menuBarIdleTextMode {
            case .idle:
                return "Idle"
            case .focusToday:
                guard let todayWorkedSeconds else { return "Idle" }
                return formatFocusDuration(seconds: todayWorkedSeconds)
            }
        }
    }

    static func formatFocusDuration(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3600
        let minutes = (clampedSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    static func formatStatusTimer(seconds: Int, style: MenuBarTimeFormat) -> String {
        switch style {
        case .clock:
            return formatClock(seconds: seconds)
        case .adaptive:
            return formatAdaptive(seconds: seconds)
        }
    }

    static func formatClock(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3600
        let minutes = (clampedSeconds % 3600) / 60
        let remainingSeconds = clampedSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func formatAdaptive(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3600
        let minutes = (clampedSeconds % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(clampedSeconds)s"
    }

    static func formatCompactDuration(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3600
        let minutes = (clampedSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    static func nextRefreshInterval(
        seconds: Int,
        style: MenuBarTimeFormat,
        countsDown: Bool
    ) -> TimeInterval {
        let clampedSeconds = max(0, seconds)
        guard style == .adaptive, clampedSeconds >= 60 else {
            return 1
        }

        let secondsIntoMinute = clampedSeconds % 60
        if countsDown {
            return TimeInterval(secondsIntoMinute + 1)
        }
        return TimeInterval(secondsIntoMinute == 0 ? 60 : 60 - secondsIntoMinute)
    }

    static func formatMinutes(_ minutes: Int) -> String {
        formatCompactDuration(seconds: max(0, minutes) * 60)
    }
}
