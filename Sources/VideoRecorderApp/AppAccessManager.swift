import Foundation
import StoreKit

enum AppAccessProduct: String, CaseIterable {
    case yearly = "com.recepgur.videorecorder.pro.yearly"
    case lifetime = "com.recepgur.videorecorder.pro.lifetime"

    var plan: AppAccessPlan {
        switch self {
        case .yearly: return .yearly
        case .lifetime: return .lifetime
        }
    }
}

enum AppAccessPlan: String, CaseIterable, Equatable {
    case yearly
    case lifetime

    var defaultTitle: String {
        switch self {
        case .yearly:
            return String(localized: "Yıllık Pro")
        case .lifetime:
            return String(localized: "Ömür Boyu Pro")
        }
    }

    var defaultDescription: String {
        switch self {
        case .yearly:
            return String(localized: "Yıllık abonelik. Sınırsız kayıt ve tüm Pro özellikleri açar.")
        case .lifetime:
            return String(localized: "Tek seferlik satın alımla kalıcı erişim. Önce yıllık plan alman gerekmez.")
        }
    }
}

enum AppAccessKind: Equatable {
    case localTrial
    case freeTier
    case freeTierExhausted
    case yearly
    case lifetime
}

struct AppStoreProductInfo: Equatable, Identifiable {
    let id: String
    let displayName: String
    let displayPrice: String
    let description: String
}

enum AppStorePurchaseResult: Equatable {
    case success
    case pending
    case userCancelled
}

struct AppAccessOffer: Equatable, Identifiable {
    let id: String
    let plan: AppAccessPlan
    let title: String
    let price: String?
    let description: String
    let isAvailableForPurchase: Bool
}

struct AppAccessState: Equatable {
    var accessKind: AppAccessKind
    var localTrialDaysRemaining: Int
    var freeTierSecondsRemaining: Int
    var offers: [AppAccessOffer]

    static let `default` = AppAccessState(
        accessKind: .freeTierExhausted,
        localTrialDaysRemaining: 0,
        freeTierSecondsRemaining: 0,
        offers: []
    )

    var canStartRecording: Bool {
        switch accessKind {
        case .localTrial, .yearly, .lifetime:
            return true
        case .freeTier:
            return freeTierSecondsRemaining > 0
        case .freeTierExhausted:
            return false
        }
    }
}

protocol DateProviding {
    var now: Date { get }
}

struct SystemDateProvider: DateProviding {
    var now: Date { Date() }
}

protocol FreeTierUsageStoring: AnyObject {
    var localTrialStartDate: Date? { get set }
    var currentPeriodStartDate: Date? { get set }
    var consumedSecondsThisPeriod: Int { get set }
}

final class UserDefaultsFreeTierUsageStore: FreeTierUsageStoring {
    private let defaults: UserDefaults
    private let trialStartKey = "appAccess.localTrialStartDate"
    private let periodStartKey = "appAccess.currentPeriodStartDate"
    private let consumedSecondsKey = "appAccess.consumedSecondsThisPeriod"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var localTrialStartDate: Date? {
        get { defaults.object(forKey: trialStartKey) as? Date }
        set { defaults.set(newValue, forKey: trialStartKey) }
    }

    var currentPeriodStartDate: Date? {
        get { defaults.object(forKey: periodStartKey) as? Date }
        set { defaults.set(newValue, forKey: periodStartKey) }
    }

    var consumedSecondsThisPeriod: Int {
        get { defaults.integer(forKey: consumedSecondsKey) }
        set { defaults.set(newValue, forKey: consumedSecondsKey) }
    }
}

protocol AppStorePurchasing: AnyObject {
    func products(for productIDs: [String]) async throws -> [AppStoreProductInfo]
    func currentEntitlementProductIDs() async -> Set<String>
    func purchase(productID: String) async throws -> AppStorePurchaseResult
    func syncPurchases() async throws
}

private final class StoreKitPurchaseController: AppStorePurchasing {
    private var cachedProducts: [String: Product] = [:]

    func products(for productIDs: [String]) async throws -> [AppStoreProductInfo] {
        let products = try await Product.products(for: productIDs)
        for product in products {
            cachedProducts[product.id] = product
        }

        return products.map {
            AppStoreProductInfo(
                id: $0.id,
                displayName: $0.displayName,
                displayPrice: $0.displayPrice,
                description: $0.description
            )
        }
    }

    func currentEntitlementProductIDs() async -> Set<String> {
        var productIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else {
                continue
            }
            productIDs.insert(transaction.productID)
        }

        return productIDs
    }

    func purchase(productID: String) async throws -> AppStorePurchaseResult {
        let product: Product
        if let cached = cachedProducts[productID] {
            product = cached
        } else {
            guard let fetched = try await Product.products(for: [productID]).first else {
                return .userCancelled
            }
            cachedProducts[productID] = fetched
            product = fetched
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                return .userCancelled
            }
            await transaction.finish()
            return .success
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .userCancelled
        }
    }

    func syncPurchases() async throws {
        try await AppStore.sync()
    }
}

@MainActor
protocol AppAccessManaging: AnyObject {
    var state: AppAccessState { get }
    func refresh() async
    func purchase(plan: AppAccessPlan) async -> AppStorePurchaseResult
    func restorePurchases() async
    func consumeFreeTierUsage(seconds: TimeInterval)
}

@MainActor
final class AppAccessManager: AppAccessManaging {
    private let storeKit: any AppStorePurchasing
    private let usageStore: any FreeTierUsageStoring
    private let clock: any DateProviding
    private let calendar: Calendar
    private let localTrialLengthInDays: Int
    private let freeTierSecondsPerPeriod: Int
    private let allowsUnitTestAccessFallback: Bool
    private let allowsDebugAccessFallback: Bool
    private let allowsInternalTestingAccessFallback: Bool

    private(set) var state: AppAccessState = .default

    init(
        storeKit: any AppStorePurchasing = StoreKitPurchaseController(),
        usageStore: any FreeTierUsageStoring = UserDefaultsFreeTierUsageStore(),
        clock: any DateProviding = SystemDateProvider(),
        calendar: Calendar = .current,
        localTrialLengthInDays: Int = 3,
        freeTierSecondsPerPeriod: Int = 7 * 60,
        allowsUnitTestAccessFallback: Bool = true,
        allowsDebugAccessFallback: Bool = true,
        allowsInternalTestingAccessFallback: Bool = Bundle.main.object(
            forInfoDictionaryKey: "FrameMateDisablePurchasesForInternalTesting"
        ) as? Bool ?? false
    ) {
        self.storeKit = storeKit
        self.usageStore = usageStore
        self.clock = clock
        self.calendar = calendar
        self.localTrialLengthInDays = localTrialLengthInDays
        self.freeTierSecondsPerPeriod = freeTierSecondsPerPeriod
        self.allowsUnitTestAccessFallback = allowsUnitTestAccessFallback
        self.allowsDebugAccessFallback = allowsDebugAccessFallback
        self.allowsInternalTestingAccessFallback = allowsInternalTestingAccessFallback
    }

    func refresh() async {
        let offers = await loadOffers()
        let entitlements = await storeKit.currentEntitlementProductIDs()
        let local = resolveLocalAccessState(now: clock.now)

        let accessKind: AppAccessKind
        if entitlements.contains(AppAccessProduct.lifetime.rawValue) {
            accessKind = .lifetime
        } else if entitlements.contains(AppAccessProduct.yearly.rawValue) {
            accessKind = .yearly
        } else if allowsInternalTestingAccessFallback {
            accessKind = .yearly
        } else if allowsUnitTestAccessFallback && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Keep existing recording-flow unit tests focused on capture behavior.
            // Real app, TestFlight, and App Store builds do not run with this XCTest environment.
            accessKind = .yearly
        } else if allowsDebugAccessFallback && isDebugBuild && !isRunningUnitTests {
            accessKind = .yearly
        } else {
            accessKind = local.kind
        }

        state = AppAccessState(
            accessKind: accessKind,
            localTrialDaysRemaining: local.daysRemaining,
            freeTierSecondsRemaining: local.secondsRemaining,
            offers: offers
        )
    }

    /// Local, account-free access: a short unlimited trial followed by a
    /// permanent monthly free-recording quota. Runs entirely off-device so
    /// a new install never has to touch StoreKit until the user chooses to
    /// buy Pro.
    private func resolveLocalAccessState(now: Date) -> (kind: AppAccessKind, daysRemaining: Int, secondsRemaining: Int) {
        if usageStore.localTrialStartDate == nil {
            usageStore.localTrialStartDate = now
        }
        let trialStart = usageStore.localTrialStartDate ?? now
        let elapsedTrialDays = calendar.dateComponents([.day], from: trialStart, to: now).day ?? 0
        if elapsedTrialDays < localTrialLengthInDays {
            return (.localTrial, localTrialLengthInDays - elapsedTrialDays, freeTierSecondsPerPeriod)
        }

        if let periodStart = usageStore.currentPeriodStartDate {
            let elapsedMonths = calendar.dateComponents([.month], from: periodStart, to: now).month ?? 0
            if elapsedMonths >= 1 {
                usageStore.currentPeriodStartDate = now
                usageStore.consumedSecondsThisPeriod = 0
            }
        } else {
            usageStore.currentPeriodStartDate = now
            usageStore.consumedSecondsThisPeriod = 0
        }

        let remaining = max(0, freeTierSecondsPerPeriod - usageStore.consumedSecondsThisPeriod)
        return (remaining > 0 ? .freeTier : .freeTierExhausted, 0, remaining)
    }

    /// Records recording time against the monthly free-tier quota. No-op
    /// outside `.freeTier` (paid plans and the local trial are unmetered).
    func consumeFreeTierUsage(seconds: TimeInterval) {
        guard state.accessKind == .freeTier else { return }
        usageStore.consumedSecondsThisPeriod += Int(seconds.rounded(.up))
    }

    func purchase(plan: AppAccessPlan) async -> AppStorePurchaseResult {
        guard let product = AppAccessProduct.allCases.first(where: { $0.plan == plan }) else {
            return .userCancelled
        }

        do {
            let result = try await storeKit.purchase(productID: product.rawValue)
            if result == .success {
                await refresh()
            }
            return result
        } catch {
            return .userCancelled
        }
    }

    func restorePurchases() async {
        do {
            try await storeKit.syncPurchases()
        } catch {
            // Keep the current state; UI will continue to show the paywall.
        }
        await refresh()
    }

    private func loadOffers() async -> [AppAccessOffer] {
        do {
            let products = try await storeKit.products(for: AppAccessProduct.allCases.map(\.rawValue))
            let infos = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            return AppAccessProduct.allCases.map { product in
                let info = infos[product.rawValue]
                return AppAccessOffer(
                    id: product.rawValue,
                    plan: product.plan,
                    title: info?.displayName ?? product.plan.defaultTitle,
                    price: info?.displayPrice,
                    description: info.flatMap { info in
                        info.description.isEmpty ? nil : info.description
                    } ?? product.plan.defaultDescription,
                    isAvailableForPurchase: info != nil
                )
            }
        } catch {
            return AppAccessProduct.allCases.map { product in
                AppAccessOffer(
                    id: product.rawValue,
                    plan: product.plan,
                    title: product.plan.defaultTitle,
                    price: nil,
                    description: product.plan.defaultDescription,
                    isAvailableForPurchase: false
                )
            }
        }
    }

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var isDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

}
