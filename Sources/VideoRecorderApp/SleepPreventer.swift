import IOKit.pwr_mgt

final class SleepPreventer {
    private var systemAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var displayAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var isActive = false

    // Both assertions are required: NoIdleSleep alone keeps the system awake but does not
    // stop the display from sleeping/locking on its own idle timer, which would interrupt
    // an in-progress screen recording with a lock screen.
    func prevent(reason: String) {
        if isActive { allow() }
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &systemAssertionID
        )
        let displayResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &displayAssertionID
        )
        isActive = (systemResult == kIOReturnSuccess) || (displayResult == kIOReturnSuccess)
        if systemResult != kIOReturnSuccess {
            print("[SleepPreventer] Warning: system sleep assertion failed (result: \(systemResult))")
        }
        if displayResult != kIOReturnSuccess {
            print("[SleepPreventer] Warning: display sleep assertion failed — screen may still lock (result: \(displayResult))")
        }
    }

    func allow() {
        guard isActive else { return }
        IOPMAssertionRelease(systemAssertionID)
        IOPMAssertionRelease(displayAssertionID)
        systemAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
        displayAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
        isActive = false
    }

    deinit { allow() }
}
