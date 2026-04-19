import XCTest
@testable import FrameMate

@MainActor
final class AppAccessManagerTests: XCTestCase {
    func testRefreshLocksRecordingWhenNoPurchaseExists() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let store = MockAppStorePurchasing(
            productsToReturn: [
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
            ]
        )
        let trialStore = MockTrialStartDateStore()
        let manager = AppAccessManager(
            storeKit: store,
            trialStore: trialStore,
            clock: FixedDateProvider(now: now),
            calendar: Calendar(identifier: .gregorian),
            allowsUnitTestAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .expired)
        XCTAssertEqual(manager.state.trialDaysRemaining, 0)
        XCTAssertFalse(manager.state.canStartRecording)
        XCTAssertEqual(manager.state.offers.map(\.plan), [.yearly, .lifetime])
        XCTAssertNil(trialStore.startDate)
    }

    func testRefreshKeepsRecordingLockedWhenLegacyLocalTrialExists() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let legacyStart = calendar.date(byAdding: .day, value: -1, to: now)
        let manager = AppAccessManager(
            storeKit: MockAppStorePurchasing(),
            trialStore: MockTrialStartDateStore(startDate: legacyStart),
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .expired)
        XCTAssertEqual(manager.state.trialDaysRemaining, 0)
        XCTAssertFalse(manager.state.canStartRecording)
    }

    func testRefreshAllowsYearlyEntitlementFromSubscriptionOrAppleTrial() async {
        let store = MockAppStorePurchasing(
            entitlementProductIDs: [AppAccessProduct.yearly.rawValue]
        )
        let manager = AppAccessManager(
            storeKit: store,
            trialStore: MockTrialStartDateStore(),
            allowsUnitTestAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .yearly)
        XCTAssertTrue(manager.state.canStartRecording)
    }

    func testRefreshPrefersLifetimeEntitlementOverExpiredTrial() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let expiredStart = calendar.date(byAdding: .day, value: -30, to: now)
        let store = MockAppStorePurchasing(
            entitlementProductIDs: [AppAccessProduct.lifetime.rawValue]
        )
        let manager = AppAccessManager(
            storeKit: store,
            trialStore: MockTrialStartDateStore(startDate: expiredStart),
            clock: FixedDateProvider(now: now),
            calendar: calendar,
            allowsUnitTestAccessFallback: false
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .lifetime)
        XCTAssertTrue(manager.state.canStartRecording)
    }
}
