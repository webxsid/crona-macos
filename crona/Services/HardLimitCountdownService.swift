import Combine
import Foundation

enum HardLimitCountdownPauseReason: Hashable {
    case keyboardFocus
    case hoverEnd
    case hoverExtend
}

struct HardLimitCountdownState: Equatable {
    let duration: TimeInterval
    var remaining: TimeInterval
    var isPaused: Bool
    var isRunning: Bool

    init(duration: TimeInterval, remaining: TimeInterval? = nil, isPaused: Bool = false, isRunning: Bool = true) {
        self.duration = max(0, duration)
        self.remaining = min(max(0, remaining ?? duration), max(0, duration))
        self.isPaused = isPaused
        self.isRunning = isRunning
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining / duration))
    }

    var displayedSeconds: Int {
        Int(ceil(remaining))
    }

    mutating func advance(by elapsed: TimeInterval) -> Bool {
        guard isRunning, !isPaused, elapsed > 0 else { return false }
        remaining = max(0, remaining - elapsed)
        if remaining == 0 {
            isRunning = false
            return true
        }
        return false
    }
}

@MainActor
final class HardLimitCountdownService: ObservableObject {
    nonisolated static let defaultDuration: TimeInterval = 30

    @Published private(set) var state = HardLimitCountdownState(
        duration: defaultDuration,
        isRunning: false
    )

    private var countdownTask: Task<Void, Never>?
    private var expiryHandler: (() -> Void)?
    private var pauseReasons: Set<HardLimitCountdownPauseReason> = []

    func start(
        duration: TimeInterval = HardLimitCountdownService.defaultDuration,
        onExpiry: @escaping () -> Void
    ) {
        cancel()
        state = HardLimitCountdownState(duration: duration)
        expiryHandler = onExpiry

        countdownTask = Task { @MainActor [weak self] in
            var previousTick = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }

                let now = Date.now
                let elapsed = now.timeIntervalSince(previousTick)
                previousTick = now

                var nextState = self.state
                let expired = nextState.advance(by: elapsed)
                self.state = nextState

                if expired {
                    let handler = self.expiryHandler
                    self.countdownTask = nil
                    self.expiryHandler = nil
                    handler?()
                    return
                }
            }
        }
    }

    func setPaused(_ isPaused: Bool, reason: HardLimitCountdownPauseReason) {
        if isPaused {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }
        let shouldPause = !pauseReasons.isEmpty
        guard state.isRunning, state.isPaused != shouldPause else { return }
        state.isPaused = shouldPause
    }

    func clearPauseReasons() {
        pauseReasons.removeAll()
        guard state.isPaused else { return }
        state.isPaused = false
    }

    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        expiryHandler = nil
        pauseReasons.removeAll()
        state.isRunning = false
        state.isPaused = false
    }
}
