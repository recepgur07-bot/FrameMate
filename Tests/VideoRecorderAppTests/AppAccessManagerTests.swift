import XCTest
@testable import FrameMate

@MainActor
final class AppAccessManagerTests: XCTestCase {
    private func makeStore(
        productsToReturn: [AppStoreProductInfo] = [
            AppStoreProductInfo(
                id: AppAccessProduct.yearly.rawValue,
                displayName: "Yearly Pro",
                displayPrice: "$19.99",
                description: "Unlock yearly access"
            ),
            AppStoreProductInfo(
                id: AppAccessProduct.lifetime.rawValue,
                displayName: "Lifetime Pro",
                displayPrice: "$59.99",
                description: "Unlock lifetime access"
            )
        ],
        entitlementProductIDs: Set<String> = []
    ) -> MockAppStorePurchasing {
        MockAppStorePurchasing(productsToReturn: productsToReturn, entitlementProductIDs: entitlementProductIDs)
    }

    func testRefreshGrantsLocalTrialOnFirstLaunchWithoutAnyPurchase() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let usageStore = MockFreeTierUsageStore()
        let manager = AppAccessManager(
            storeKit: makeStore(),
            usageStore: usageStore,
            clock: FixedDateProvider(now: now),
            calendar: Calendar(identifier: .gregorian),
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .localTrial)
        XCTAssertEqual(manager.state.localTrialDaysRemaining, 3)
        XCTAssertTrue(manager.state.canStartRecording)
        XCTAssertEqual(manager.state.offers.map(\.plan), [.yearly, .lifetime])
        XCTAssertEqual(usageStore.localTrialStartDate, now)
    }

    func testRefreshMovesToFreeTierAfterLocalTrialExpires() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let trialStart = calendar.date(byAdding: .day, value: -3, to: now)
        let manager = AppAccessManager(
            storeKit: makeStore(),
            usageStore: MockFreeTierUsageStore(localTrialStartDate: trialStart),
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .freeTier)
        XCTAssertEqual(manager.state.freeTierSecondsRemaining, 420)
        XCTAssertTrue(manager.state.canStartRecording)
    }

    func testConsumeFreeTierUsageReducesRemainingSeconds() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let trialStart = calendar.date(byAdding: .day, value: -3, to: now)
        let usageStore = MockFreeTierUsageStore(localTrialStartDate: trialStart)
        let manager = AppAccessManager(
            storeKit: makeStore(),
            usageStore: usageStore,
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()
        manager.consumeFreeTierUsage(seconds: 90)
        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .freeTier)
        XCTAssertEqual(manager.state.freeTierSecondsRemaining, 330)
    }

    func testFreeTierBecomesExhaustedWhenQuotaFullyConsumed() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let trialStart = calendar.date(byAdding: .day, value: -3, to: now)
        let periodStart = calendar.date(byAdding: .day, value: -1, to: now)
        let usageStore = MockFreeTierUsageStore(
            localTrialStartDate: trialStart,
            currentPeriodStartDate: periodStart,
            consumedSecondsThisPeriod: 420
        )
        let manager = AppAccessManager(
            storeKit: makeStore(),
            usageStore: usageStore,
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .freeTierExhausted)
        XCTAssertEqual(manager.state.freeTierSecondsRemaining, 0)
        XCTAssertFalse(manager.state.canStartRecording)
    }

    func testFreeTierQuotaResetsWhenNewMonthlyPeriodBegins() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let trialStart = calendar.date(byAdding: .day, value: -40, to: now)
        let periodStart = calendar.date(byAdding: .month, value: -1, to: now)
        let usageStore = MockFreeTierUsageStore(
            localTrialStartDate: trialStart,
            currentPeriodStartDate: periodStart,
            consumedSecondsThisPeriod: 420
        )
        let manager = AppAccessManager(
            storeKit: makeStore(),
            usageStore: usageStore,
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .freeTier)
        XCTAssertEqual(manager.state.freeTierSecondsRemaining, 420)
        XCTAssertEqual(usageStore.consumedSecondsThisPeriod, 0)
    }

    func testRefreshAllowsYearlyEntitlementFromSubscription() async {
        let manager = AppAccessManager(
            storeKit: makeStore(entitlementProductIDs: [AppAccessProduct.yearly.rawValue]),
            usageStore: MockFreeTierUsageStore(),
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .yearly)
        XCTAssertTrue(manager.state.canStartRecording)
    }

    func testRefreshPrefersLifetimeEntitlementOverExhaustedFreeTier() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let trialStart = calendar.date(byAdding: .day, value: -30, to: now)
        let usageStore = MockFreeTierUsageStore(
            localTrialStartDate: trialStart,
            currentPeriodStartDate: trialStart,
            consumedSecondsThisPeriod: 420
        )
        let manager = AppAccessManager(
            storeKit: makeStore(entitlementProductIDs: [AppAccessProduct.lifetime.rawValue]),
            usageStore: usageStore,
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .lifetime)
        XCTAssertTrue(manager.state.canStartRecording)
    }

    func testRefreshLocksRecordingForBetaBuildsWithoutPurchaseOnceFreeTierExhausted() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let trialStart = calendar.date(byAdding: .day, value: -30, to: now)
        let usageStore = MockFreeTierUsageStore(
            localTrialStartDate: trialStart,
            currentPeriodStartDate: trialStart,
            consumedSecondsThisPeriod: 420
        )
        let manager = AppAccessManager(
            storeKit: makeStore(),
            usageStore: usageStore,
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .freeTierExhausted)
        XCTAssertFalse(manager.state.canStartRecording)
    }

    func testRefreshAllowsInternalTestingBuildsWithoutPurchase() async {
        let manager = AppAccessManager(
            storeKit: makeStore(),
            usageStore: MockFreeTierUsageStore(),
            allowsUnitTestAccessFallback: false,
            allowsDebugAccessFallback: false,
            allowsInternalTestingAccessFallback: true
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .yearly)
        XCTAssertTrue(manager.state.canStartRecording)
    }
}
