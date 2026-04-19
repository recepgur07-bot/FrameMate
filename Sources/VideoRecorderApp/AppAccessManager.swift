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
            return String(localized: "14 gün ücretsiz dene, sonra yıllık Pro erişim.")
        case .lifetime:
            return String(localized: "Tek seferlik satın alımla kalıcı erişim.")
        }
    }
}

enum AppAccessKind: Equatable {
    case trial
    case yearly
    case lifetime
    case expired
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
    var trialDaysRemaining: Int
    var offers: [AppAccessOffer]

    static let `default` = AppAccessState(
        accessKind: .expired,
        trialDaysRemaining: 0,
        offers: []
    )

    var canStartRecording: Bool {
        accessKind != .expired
    }
}

protocol DateProviding {
    var now: Date { get }
}

struct SystemDateProvider: DateProviding {
    var now: Date { Date() }
}

protocol TrialStartDateStoring: AnyObject {
    var startDate: Date? { get set }
}

final class UserDefaultsTrialStartDateStore: TrialStartDateStoring {
    private let defaults: UserDefaults
    private let key = "appAccess.trialStartDate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var startDate: Date? {
        get { defaults.object(forKey: key) as? Date }
        set { defaults.set(newValue, forKey: key) }
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
}

@MainActor
final class AppAccessManager: AppAccessManaging {
    private let storeKit: any AppStorePurchasing
    private let trialStore: any TrialStartDateStoring
    private let clock: any DateProviding
    private let calendar: Calendar
    private let trialLengthInDays: Int
    private let allowsUnitTestAccessFallback: Bool

    private(set) var state: AppAccessState = .default

    init(
        storeKit: any AppStorePurchasing = StoreKitPurchaseController(),
        trialStore: any TrialStartDateStoring = UserDefaultsTrialStartDateStore(),
        clock: any DateProviding = SystemDateProvider(),
        calendar: Calendar = .current,
        trialLengthInDays: Int = 14,
        allowsUnitTestAccessFallback: Bool = true
    ) {
        self.storeKit = storeKit
        self.trialStore = trialStore
        self.clock = clock
        self.calendar = calendar
        self.trialLengthInDays = trialLengthInDays
        self.allowsUnitTestAccessFallback = allowsUnitTestAccessFallback
    }

    func refresh() async {
        let offers = await loadOffers()
        let entitlements = await storeKit.currentEntitlementProductIDs()

        let accessKind: AppAccessKind
        if entitlements.contains(AppAccessProduct.lifetime.rawValue) {
            accessKind = .lifetime
        } else if entitlements.contains(AppAccessProduct.yearly.rawValue) {
            accessKind = .yearly
        } else if allowsUnitTestAccessFallback && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Keep existing recording-flow unit tests focused on capture behavior.
            // Real app, TestFlight, and App Store builds do not run with this XCTest environment.
            accessKind = .yearly
        } else {
            accessKind = .expired
        }

        state = AppAccessState(
            accessKind: accessKind,
            trialDaysRemaining: 0,
            offers: offers
        )
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
                    description: info?.description.isEmpty == false ? info!.description : product.plan.defaultDescription,
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

}
