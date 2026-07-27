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
        // Stopping is also valid while still `.preparing`: startup does real async work
        // (device configuration, permission checks) before reaching `.recording`, and a
        // user can request stop in that window. Rejecting it there would silently drop
        // the stop request instead of tearing down whatever has already started.
        guard phase == .recording || phase == .preparing else { return false }
        phase = .stopping
        return true
    }

    mutating func finish() {
        phase = .idle
    }
}
