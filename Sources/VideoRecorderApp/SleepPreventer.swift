import IOKit.pwr_mgt

final class SleepPreventer {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var isActive = false

    func prevent(reason: String) {
        if isActive { allow() }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        isActive = (result == kIOReturnSuccess)
        if !isActive {
            print("[SleepPreventer] Warning: IOPMAssertionCreateWithName failed — sleep not prevented (result: \(result))")
        }
    }

    func allow() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
        isActive = false
    }

    deinit { allow() }
}
