import Foundation

enum MenuBarTextFormatter {
    static func statusItemTitle(
        preferences: CompanionPreferences,
        connectionState: CompanionConnectionState,
        timerSnapshot: TimerSnapshot,
        todayWorkedSeconds: Int? = nil
    ) -> String {
        guard preferences.menuBarDisplayMode.showsText else {
            return ""
        }

        guard connectionState == .connected else { return "Offline" }

        switch timerSnapshot.state {
        case "running", "paused":
            return formatElapsed(
                seconds: timerSnapshot.displayElapsedSeconds,
                format: preferences.menuBarTimeFormat,
                showsSeconds: preferences.menuBarShowsSeconds
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

    static func formatElapsed(
        seconds: Int,
        format: MenuBarTimeFormat,
        showsSeconds: Bool
    ) -> String {
        let totalHours = max(0, seconds) / 3600
        let minutes = (max(0, seconds) % 3600) / 60
        let remainingSeconds = max(0, seconds) % 60

        switch format {
        case .clock:
            if showsSeconds {
                return String(format: "%d:%02d:%02d", totalHours, minutes, remainingSeconds)
            }
            return String(format: "%d:%02d", totalHours, minutes)
        case .expanded:
            if showsSeconds {
                return "\(totalHours)h\(minutes)m\(remainingSeconds)s"
            }
            return "\(totalHours)h\(minutes)m"
        }
    }

    static func formatMinutes(_ minutes: Int) -> String {
        formatElapsed(seconds: max(0, minutes) * 60, format: .expanded, showsSeconds: false)
    }
}
