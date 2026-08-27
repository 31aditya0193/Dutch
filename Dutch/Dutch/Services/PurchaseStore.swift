/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import StoreKit
import SwiftUI

/// The one-time purchase that lifts the limit on how many groups this device
/// can create.
///
/// A single non-consumable, and a Family Shareable one. There is no server to
/// check it against and nothing about it goes through CloudKit — the App
/// Store's own record is the only authority, and it already follows the Apple
/// Account onto every device the user signs in to, plus everyone in their
/// family. That is also why "restore" is barely a feature here:
/// `currentEntitlements` finds the purchase on a fresh install without anyone
/// tapping anything, and the button exists mostly because App Review requires
/// one to be visible (guideline 3.1.1).
///
/// Family Sharing is why `revocationDate` is checked rather than assumed away.
/// Without it the only route to a revoked purchase is a refund; with it, a
/// member leaving the family loses the entitlement too — which is an ordinary
/// event rather than an exceptional one, and has to actually take effect.
///
/// Named to sit next to `GroupStore`: both are the one place a kind of state is
/// written. This one owns no Core Data.
@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()

    /// Must match the product identifier in App Store Connect *and* in
    /// `Dutch.storekit`. A mismatch is not an error anywhere — `products(for:)`
    /// simply returns an empty array and the paywall renders with no price.
    static let unlimitedGroupsID = "net.smigi.Dutch.unlimitedgroups"

    /// The product, once the App Store has answered. `nil` until then, and on
    /// a device that is offline or has App Store access restricted.
    ///
    /// Every figure the paywall shows comes from here rather than from a
    /// constant in the source. `displayPrice` is already localized, already
    /// converted to the user's storefront, and already reflects any price
    /// change or promotion made in App Store Connect after this build shipped —
    /// a hardcoded "$4.99" would be wrong for most of the world on day one.
    @Published private(set) var product: Product?

    /// Whether this Apple Account owns the purchase.
    @Published private(set) var hasUnlimitedGroups: Bool

    /// True while the App Store sheet is up or a restore is in flight, so the
    /// paywall can disable its buttons rather than let a second tap start a
    /// second purchase.
    @Published private(set) var isWorking = false

    /// Set when loading the product failed, so the paywall can offer a retry
    /// instead of showing an empty price and a dead button.
    @Published private(set) var loadFailed = false

    /// Watches for entitlement changes that don't originate from our own
    /// purchase call: an Ask to Buy approval arriving later, a Family Sharing
    /// grant, a purchase made on another device, or a refund.
    private var updates: Task<Void, Never>?

    // MARK: - Entitlement cache

    /// The app group suite, for the same reason everything else uses it, and
    /// falling back the same way.
    private static let defaults = UserDefaults(
        suiteName: PersistenceController.appGroupIdentifier
    ) ?? .standard

    private static let entitlementKey = "hasUnlimitedGroups"

    /// UI tests run with no App Store at all, so the entitlement is always
    /// false there — which makes the free tier the deterministic thing they
    /// test against. This flag exists for the test that eventually needs the
    /// other side of the gate; without it that test could only fail obscurely,
    /// at a paywall it never asked for.
    private static var isUITestingUnlocked: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting-unlocked")
    }

    // MARK: - Init

    private init() {
        // Seeded from the cache rather than starting false, because
        // `currentEntitlements` is asynchronous and the group list is on screen
        // before it answers. Starting locked would show a paying customer the
        // paywall for the first moments of every cold launch — and, worse,
        // would do it at the exact moment they tapped New Group.
        //
        // The cache is only ever a head start: `refreshEntitlement` overwrites
        // it in both directions a moment later, so a refund still takes effect
        // and the local value cannot drift away from the App Store's.
        hasUnlimitedGroups = Self.isUITestingUnlocked
            || Self.defaults.bool(forKey: Self.entitlementKey)

        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }
    }

    deinit {
        updates?.cancel()
    }

    // MARK: - Loading

    /// Fetches the product and re-checks the entitlement.
    ///
    /// Safe to call repeatedly — the group list calls it on appearance so that
    /// a device which was offline at launch picks up the price later.
    func load() async {
        await refreshEntitlement()
        await loadProduct()
    }

    private func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.unlimitedGroupsID]).first
            loadFailed = product == nil
        } catch {
            loadFailed = true
        }
    }

    /// Asks StoreKit what this Apple Account currently owns.
    ///
    /// `currentEntitlements` reads the on-device record, so this is correct
    /// offline and does not need a network round trip. Revoked purchases —
    /// refunds, Family Sharing withdrawn — are already excluded from it, and
    /// `revocationDate` is checked anyway because the cost of being wrong in
    /// that direction is charging someone twice.
    func refreshEntitlement() async {
        var owned = Self.isUITestingUnlocked

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.productID == Self.unlimitedGroupsID else { continue }
            guard transaction.revocationDate == nil else { continue }
            owned = true
        }

        hasUnlimitedGroups = owned
        Self.defaults.set(owned, forKey: Self.entitlementKey)
    }

    // MARK: - Buying

    enum PurchaseOutcome {
        case purchased
        case cancelled
        /// Ask to Buy, or a payment the App Store has yet to settle. Nothing to
        /// show yet; the `Transaction.updates` listener picks it up if and when
        /// it is approved.
        case pending
        case failed(String)
    }

    func purchase() async -> PurchaseOutcome {
        guard let product else { return .failed("The purchase isn't available right now.") }
        guard !isWorking else { return .cancelled }

        isWorking = true
        defer { isWorking = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // A transaction that fails StoreKit's own signature check.
                    // Not something a user can act on, and not something to
                    // unlock on.
                    return .failed("That purchase couldn't be verified.")
                }
                await transaction.finish()
                await refreshEntitlement()
                return .purchased

            case .userCancelled:
                return .cancelled

            case .pending:
                return .pending

            @unknown default:
                return .failed("That purchase couldn't be completed.")
            }
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    /// Turns a StoreKit failure into something a person can act on.
    ///
    /// `error.localizedDescription` alone is what shipped first, and StoreKit's
    /// own wording is written for developers: "Item Unavailable" tells a user
    /// nothing about whether to wait, check their settings, or give up. It also
    /// tells *us* nothing — several unrelated causes share it — so the raw
    /// error is logged alongside, where Console.app can pick it up from a
    /// TestFlight or sandbox build.
    private static func message(for error: Error) -> String {
        print("[Dutch] Purchase failed: \(type(of: error)).\(error) — \(error.localizedDescription)")

        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return String(localized: "This purchase isn't available on your App Store account yet. If the app was just updated, try again a little later.")
            case .purchaseNotAllowed:
                return String(localized: "Purchases are turned off on this device. Check Screen Time restrictions.")
            case .ineligibleForOffer:
                return String(localized: "This offer isn't available on your account.")
            case .invalidOfferIdentifier, .invalidOfferPrice, .invalidOfferSignature, .missingOfferParameters:
                return String(localized: "That purchase couldn't be set up. Please try again.")
            case .invalidQuantity:
                return String(localized: "That quantity isn't available.")
            default:
                // Plain `default`, not `@unknown default`: StoreKit adds cases
                // between SDK versions and this is a fallback message, not a
                // decision — a build warning here would be noise.
                return String(localized: "That purchase couldn't be completed.")
            }
        }

        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError:
                return String(localized: "The App Store couldn't be reached. Check your connection and try again.")
            case .notAvailableInStorefront:
                return String(localized: "This purchase isn't available in your country's App Store.")
            case .userCancelled:
                return String(localized: "Purchase cancelled.")
            case .notEntitled:
                return String(localized: "This device isn't allowed to make that purchase.")
            case .systemError, .unknown:
                return String(localized: "The App Store couldn't complete that right now. Please try again.")
            default:
                return String(localized: "That purchase couldn't be completed.")
            }
        }

        return error.localizedDescription
    }

    /// Re-syncs with the App Store and re-checks the entitlement.
    ///
    /// `AppStore.sync()` prompts for the Apple Account password, so it is only
    /// ever called from a button the user pressed — never automatically at
    /// launch, which would be an unexplained password prompt on first run.
    /// Returns whether the purchase was found.
    func restore() async -> Bool {
        guard !isWorking else { return hasUnlimitedGroups }

        isWorking = true
        defer { isWorking = false }

        // A failure here is usually a cancelled password prompt. The
        // entitlement is re-read either way, because the local record may
        // already have held the purchase.
        try? await AppStore.sync()
        await refreshEntitlement()
        return hasUnlimitedGroups
    }
}
