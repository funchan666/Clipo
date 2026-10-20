# Membership presentation and on-demand Apple lookup

## Display

The paywall immediately renders the two configured plans from `Commerce.json`: Monthly USD 9.99 and Yearly USD 99.99. These reference display amounts are explicit fields and are not calculated from the backend `usdPrice` parameter. Existing product identifiers and backend values remain unchanged.

The dark layout uses the existing original Plus artwork, a short benefit headline, two selectable price rows and one primary Continue button. The selected plan is identified with text as well as a distinct surface. Rewarded advertising is secondary. Close remains visible above the scroll view. Restore, subscription management, policy links and renewal disclosures remain accessible below the main offer.

## Purchase flow

1. Opening the screen refreshes backend configuration/rights only. It does not run `SKProductsRequest`.
2. Selecting a plan is local. Pressing Continue requests only that selected product from Apple.
3. The request has a 20-second timeout, cancellation handling, request-identity checks and a single continuation completion path. Empty, invalid, failed or stale responses do not create an order or queue a payment.
4. A valid result updates the displayed amount using `SKProduct.price` and `priceLocale`. The returned subscription period must match the selected monthly/yearly plan.
5. After checking the original account still owns the operation, refresh backend configuration/rights. A current member is not charged again. The existing purchase preconditions still apply; missing distribution/billing configuration is not bypassed.
6. Continue through the existing SK1 order creation, immutable owner/host binding, persisted ledger, Apple payment, verification and recovery flow. Only Apple-returned product data is used to create `SKMutablePayment`. The local reference price never grants entitlement or simulates success.

While preparing or purchasing, repeated purchase, restore, advertising and dismissal actions are blocked. The account is checked again after asynchronous preparation. The existing receipt verification and finish-after-persistence behavior are retained.

Apple references: [Fetching product information](https://developer.apple.com/documentation/storekit/fetching-product-information-from-the-app-store) and [Offering, completing and restoring purchases](https://developer.apple.com/documentation/storekit/offering-completing-and-restoring-in-app-purchases). This is an incremental SK1 change, not a StoreKit migration.

## Verification boundary

Performed source/diff inspection, resource-reference checks and JSON checks for exact IDs, displayed prices and unchanged backend parameters. Reused and visually inspected the existing original illustration; no new art or system icons were introduced. The layout uses a bounded container, wrapping/stacking rows and persistent selection independent of size. No new SDK or device-specific layout API was introduced.

No build, simulator/device run, StoreKit request, payment or sandbox transaction was performed for this revision. Prior runtime audit results predate the changed paywall and purchase-preparation path. Apple product registration and backend distribution-package configuration are still required for an actual purchase.
