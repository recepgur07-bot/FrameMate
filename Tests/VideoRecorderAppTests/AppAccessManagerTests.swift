import XCTest
@testable import FrameMate

@MainActor
final class AppAccessManagerTests: XCTestCase {
    func testRefreshStartsFourteenDayTrialWhenNoPurchaseExists() async {
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
            calendar: Calendar(identifier: .gregorian)
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .trial)
        XCTAssertEqual(manager.state.trialDaysRemaining, 14)
        XCTAssertTrue(manager.state.canStartRecording)
        XCTAssertEqual(manager.state.offers.map(\.plan), [.yearly, .lifetime])
        XCTAssertEqual(trialStore.startDate, now)
    }

    func testRefreshLocksRecordingWhenTrialExpiredAndNoEntitlementExists() async {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let expiredStart = calendar.date(byAdding: .day, value: -14, to: now)
        let manager = AppAccessManager(
            storeKit: MockAppStorePurchasing(),
            trialStore: MockTrialStartDateStore(startDate: expiredStart),
            clock: FixedDateProvider(now: now),
            calendar: calendar
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .expired)
        XCTAssertEqual(manager.state.trialDaysRemaining, 0)
        XCTAssertFalse(manager.state.canStartRecording)
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
            calendar: calendar
        )

        await manager.refresh()

        XCTAssertEqual(manager.state.accessKind, .lifetime)
        XCTAssertTrue(manager.state.canStartRecording)
    }
}
