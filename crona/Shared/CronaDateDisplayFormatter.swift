import Foundation

enum CronaDateDisplayFormatter {
    static func string(fromISODate rawValue: String, settings: CronaCoreSettings) -> String {
        guard let date = parse(rawValue) else { return rawValue }
        let preset = settings.dateDisplayPreset.lowercased()
        let pattern: String
        switch preset {
        case "us": pattern = "MM/DD/YYYY"
        case "europe": pattern = "DD/MM/YYYY"
        case "long": pattern = "D MMM YYYY"
        case "custom": pattern = settings.dateDisplayFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        default: pattern = "YYYY-MM-DD"
        }
        return render(date: date, pattern: pattern.isEmpty ? "YYYY-MM-DD" : pattern)
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func render(date: Date, pattern: String) -> String {
        var result = ""
        var index = pattern.startIndex
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .weekday, .weekOfYear], from: date)
        let month = components.month ?? 0
        let day = components.day ?? 0
        let year = components.year ?? 0
        let weekday = components.weekday ?? 1

        while index < pattern.endIndex {
            if pattern[index] == "[" {
                guard let end = pattern[index...].firstIndex(of: "]") else { return render(date: date, pattern: "YYYY-MM-DD") }
                result += String(pattern[pattern.index(after: index)..<end])
                index = pattern.index(after: end)
                continue
            }

            let remainder = pattern[index...]
            let token = ["YYYY", "dddd", "MMMM", "ddd", "MMM", "Do", "YY", "MM", "DD", "WW", "LL", "L", "M", "D", "W", "d"].first {
                remainder.hasPrefix($0)
            }
            guard let token else {
                result.append(pattern[index])
                index = pattern.index(after: index)
                continue
            }

            switch token {
            case "YYYY": result += String(format: "%04d", year)
            case "YY": result += String(format: "%02d", year % 100)
            case "M", "L": result += "\(month)"
            case "MM", "LL": result += String(format: "%02d", month)
            case "D": result += "\(day)"
            case "DD": result += String(format: "%02d", day)
            case "Do": result += ordinal(day)
            case "d": result += "\(weekday - 1)"
            case "W": result += "\(components.weekOfYear ?? 0)"
            case "WW": result += String(format: "%02d", components.weekOfYear ?? 0)
            case "MMM": result += monthName(month, abbreviated: true)
            case "MMMM": result += monthName(month, abbreviated: false)
            case "ddd": result += weekdayName(weekday, abbreviated: true)
            case "dddd": result += weekdayName(weekday, abbreviated: false)
            default: break
            }
            index = pattern.index(index, offsetBy: token.count)
        }
        return result
    }

    private static func ordinal(_ value: Int) -> String {
        let suffix: String
        if (11...13).contains(value % 100) { suffix = "th" }
        else {
            switch value % 10 { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" }
        }
        return "\(value)\(suffix)"
    }

    private static func monthName(_ month: Int, abbreviated: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        return abbreviated ? formatter.shortMonthSymbols[month - 1] : formatter.monthSymbols[month - 1]
    }

    private static func weekdayName(_ weekday: Int, abbreviated: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        return abbreviated ? formatter.shortWeekdaySymbols[weekday - 1] : formatter.weekdaySymbols[weekday - 1]
    }
}
