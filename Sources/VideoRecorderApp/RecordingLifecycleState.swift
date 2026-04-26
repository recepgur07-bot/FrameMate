struct RecordingLifecycleState: Equatable {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case stopping
    }

    private(set) var phase: Phase = .idle

    var canBeginPreparing: Bool { phase == .idle }
    var isPreparing: Bool { phase == .preparing }
    var isRecording: Bool { phase == .recording }
    var isStopping: Bool { phase == .stopping }

    @discardableResult
    mutating func beginPreparing() -> Bool {
        guard phase == .idle else { return false }
        phase = .preparing
        return true
    }

    @discardableResult
    mutating func markStarted() -> Bool {
        guard phase == .preparing else { return false }
        phase = .recording
        return true
    }

    @discardableResult
    mutating func beginStopping() -> Bool {
        guard phase == .recording else { return false }
        phase = .stopping
        return true
    }

    mutating func finish() {
        phase = .idle
    }
}
