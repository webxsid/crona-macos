import Foundation

enum FlexibleDurationParser {
    static func optionalMinutes(_ input: String) -> Result<Int?, ValidationError> {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return .success(nil) }
        if let minutes = Int(raw), minutes >= 0 { return .success(minutes) }
        if let hours = Double(raw), hours >= 0 {
            return .success(Int((hours * 60).rounded()))
        }
        guard let seconds = durationSeconds(raw), seconds >= 0 else {
            return .failure(.invalid)
        }
        return .success(Int((seconds / 60).rounded()))
    }

    enum ValidationError: Error, Equatable {
        case invalid
    }

    private static func durationSeconds(_ raw: String) -> Double? {
        let pattern = #"^(?:(\d+(?:\.\d+)?)h)?(?:(\d+(?:\.\d+)?)m)?(?:(\d+(?:\.\d+)?)s)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.range.length == raw.utf16.count,
              raw.contains(where: { $0 == "h" || $0 == "m" || $0 == "s" })
        else { return nil }

        func value(at index: Int) -> Double {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: raw)
            else { return 0 }
            return Double(raw[swiftRange]) ?? 0
        }
        return value(at: 1) * 3_600 + value(at: 2) * 60 + value(at: 3)
    }
}
