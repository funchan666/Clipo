import Foundation
import Combine
import StoreKit

private struct PurchaseRecord: Codable {
    let id: String
    let orderID: String
    let productID: String
    let owner: VisitorSession
    let apiHost: String
    let billing: IOSBillingConfiguration
    var originalTransactionID: String?
    var transactionIDs: Set<String> = []
    var confirmedIDs: Set<String> = []
    var abandoned = false
}

@MainActor
final class CommerceStore: NSObject, ObservableObject {
    @Published private(set) var products: [SKProduct] = []
    @Published private(set) var release: ReleaseConfiguration?
    @Published private(set) var rightsVerified = false
    @Published private(set) var expiration: Date?
    @Published private(set) var busy = false
    @Published private(set) var loadingProducts = false
    @Published private(set) var preparingPurchase = false
    @Published var message: String?
    @Published var error: String?
    private(set) var policy: CommerceConfiguration?
    let api: APIClient
    let quota: QuotaStore
    private var records: [PurchaseRecord] = []
    private var ledgerAvailable = true
    private var productsRequest: SKProductsRequest?
    private var productContinuation: CheckedContinuation<SKProduct, Error>?
    private var productTimeout: Task<Void, Never>?
    private var requestedProductID: String?
    private var receiptRequest: SKReceiptRefreshRequest?
    private var receiptContinuation: CheckedContinuation<Void, Error>?
    private var processing: Set<String> = []
    private var ownerID: String?
    private var refreshID = UUID()
    var premium: Bool { expiration.map { $0 > Date() } ?? false }
    var purchasesAllowed: Bool { release != nil && release?.NB01 != true && api.session != nil && api.configuration.isReady && ledgerAvailable }

    init(api: APIClient, quota: QuotaStore) {
        self.api = api
        self.quota = quota
        super.init()
        do {
            policy = try CommerceConfiguration.load()
            if let data = try SecureStorage.read("purchase-ledger") { records = try JSONDecoder().decode([PurchaseRecord].self, from: data) }
        } catch {
            ledgerAvailable = false
            self.error = "Purchase recovery storage is unavailable. Purchases are paused to protect existing orders."
        }
        SKPaymentQueue.default().add(self)
    }
    func refresh() async {
        let id = UUID()
        refreshID = id
        rightsVerified = false
        let userID = api.session?.userId.value
        if ownerID != userID { expiration = nil; release = nil; ownerID = userID }
        quota.configure(userID: userID, policy: policy, remote: release?.quotaConfig)
        guard userID != nil else { return }
        error = nil
        do {
            let configuration = try await api.releaseConfiguration()
            guard refreshID == id, api.session?.userId.value == userID else { return }
            release = configuration
            quota.configure(userID: userID, policy: policy, remote: configuration.quotaConfig)
        } catch { if refreshID == id { self.error = error.localizedDescription } }
        guard refreshID == id, api.session?.userId.value == userID else { return }
        // Account rights remain independently refreshable if package configuration fails.
        do {
            let rights = try await api.rights()
            guard refreshID == id, api.session?.userId.value == userID else { return }
            expiration = rights.expiration
            rightsVerified = true
        } catch { if refreshID == id, self.error == nil { self.error = error.localizedDescription } }
        retryPending()
    }
    // Called only by an explicit purchase action, never when the paywall appears.
    func purchase(planID: String) async {
        guard !busy, !preparingPurchase else { return }
        error = nil
        message = nil
        guard let owner = api.session else { error = "Sign in before subscribing."; return }
        guard ledgerAvailable, let entry = policy?.products.first(where: { $0.id == planID }) else {
            error = "Purchases are temporarily unavailable. Please try again later."; return
        }
        guard SKPaymentQueue.canMakePayments() else { error = "Purchases are not allowed on this device."; return }
        preparingPurchase = true
        defer { preparingPurchase = false }
        do {
            let product = try await requestProduct(planID)
            try Task.checkCancellation()
            guard api.session?.userId.value == owner.userId.value else { throw ClipoError.unauthorized }
            guard let period = product.subscriptionPeriod, period.numberOfUnits == 1,
                  (entry.period == .month && period.unit == .month) || (entry.period == .year && period.unit == .year) else {
                throw ClipoError.service("Apple returned a different subscription period. Please try again later.")
            }
            products.removeAll { $0.productIdentifier == product.productIdentifier }
            products.append(product)
            await refresh()
            try Task.checkCancellation()
            guard api.session?.userId.value == owner.userId.value else { throw ClipoError.unauthorized }
            guard !premium else { message = "Your membership is already active."; return }
            await buy(product)
        } catch is CancellationError {
            // No order or payment is created when preparation is cancelled.
        } catch { self.error = error.localizedDescription }
    }
    private func requestProduct(_ id: String) async throws -> SKProduct {
        guard productsRequest == nil else { throw ClipoError.service("An Apple request is already in progress.") }
        let request = SKProductsRequest(productIdentifiers: [id])
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                productsRequest = request
                requestedProductID = id
                productContinuation = continuation
                loadingProducts = true
                request.delegate = self
                request.start()
                productTimeout = Task { @MainActor [weak self, weak request] in
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    guard let request else { return }
                    self?.finishProductRequest(request, result: .failure(ClipoError.service("Apple is taking too long to respond. Please try again.")))
                }
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.finishProductRequest(request, result: .failure(CancellationError()))
            }
        })
    }
    private func finishProductRequest(_ request: SKRequest, result: Result<SKProduct, Error>) {
        guard request === productsRequest else { return }
        productTimeout?.cancel()
        productTimeout = nil
        request.delegate = nil
        request.cancel()
        productsRequest = nil
        requestedProductID = nil
        loadingProducts = false
        let continuation = productContinuation
        productContinuation = nil
        continuation?.resume(with: result)
    }
    func price(_ product: SKProduct) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price) ?? product.price.stringValue
    }
    func period(_ product: SKProduct) -> String {
        guard let period = product.subscriptionPeriod else { return "" }
        let unit: String
        switch period.unit { case .day: unit = "day"; case .week: unit = "week"; case .month: unit = "month"; case .year: unit = "year"; @unknown default: unit = "period" }
        return period.numberOfUnits == 1 ? "per \(unit)" : "every \(period.numberOfUnits) \(unit)s"
    }
    private func buy(_ product: SKProduct) async {
        guard !busy else { return }
        guard purchasesAllowed, let owner = api.session, let billing = release?.ios,
              let entry = policy?.products.first(where: { $0.id == product.productIdentifier }) else {
            error = "Subscriptions are temporarily unavailable. Please try again later."; return
        }
        guard api.configuration.privacyURL != nil, api.configuration.termsURL != nil else {
            error = "Subscription information is being prepared. Please try again later."; return
        }
        guard SKPaymentQueue.canMakePayments() else { error = "Purchases are not allowed on this device."; return }
        guard !SKPaymentQueue.default().transactions.contains(where: { $0.transactionState != .failed }) else {
            error = "An earlier purchase still needs to finish. Use Retry purchase confirmation."; return
        }
        busy = true
        error = nil
        message = nil
        do {
            let payload: [String: Any] = ["rightsName": product.productIdentifier, "price": product.price.stringValue,
                "usdPrice": entry.usdPrice, "packageName": api.configuration.bundleID,
                "versionCode": api.configuration.version, "payType": "1", "source": "ios"]
            let data = try await api.paymentRequest(path: "/app-api/flow/rights-order/buy", body: payload, owner: owner)
            let response = try JSONDecoder().decode(APIEnvelope<ServiceID>.self, from: data)
            guard let order = response.data?.value, !order.isEmpty else { throw ClipoError.invalidResponse }
            let record = PurchaseRecord(id: UUID().uuidString, orderID: order, productID: product.productIdentifier,
                owner: owner, apiHost: api.configuration.apiBaseURL?.absoluteString ?? "", billing: billing)
            var next = records
            next.append(record)
            try save(next)
            guard api.session?.userId.value == owner.userId.value else { throw ClipoError.unauthorized }
            let payment = SKMutablePayment(product: product)
            payment.applicationUsername = record.id
            SKPaymentQueue.default().add(payment)
        } catch { self.error = error.localizedDescription; busy = false }
    }
    func restore() {
        guard !busy, !preparingPurchase else { return }
        guard api.session != nil, ledgerAvailable else { error = "Sign in before restoring purchases."; return }
        busy = true
        error = nil
        message = "Checking your Apple purchases…"
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    func retryPending() {
        guard ledgerAvailable else { return }
        for transaction in SKPaymentQueue.default().transactions where transaction.transactionState == .purchased || transaction.transactionState == .restored {
            Task { await confirm(transaction) }
        }
    }
    private func confirm(_ transaction: SKPaymentTransaction) async {
        guard ledgerAvailable, let transactionID = transaction.transactionIdentifier, !processing.contains(transactionID) else { return }
        processing.insert(transactionID)
        defer { processing.remove(transactionID); busy = false }
        let binding = transaction.payment.applicationUsername ?? transaction.original?.payment.applicationUsername
        let original = transaction.original?.transactionIdentifier ?? transactionID
        guard let index = records.firstIndex(where: {
            $0.id == binding || $0.transactionIDs.contains(transactionID) || $0.originalTransactionID == original
        }), records[index].productID == transaction.payment.productIdentifier else {
            error = "An Apple purchase is awaiting account reconciliation. Its original order could not be identified; it has not been discarded."
            return
        }
        if records[index].confirmedIDs.contains(transactionID) {
            SKPaymentQueue.default().finishTransaction(transaction)
            return
        }
        do {
            var next = records
            next[index].originalTransactionID = original
            next[index].transactionIDs.insert(transactionID)
            try save(next)
            let record = records[index]
            guard record.apiHost == api.configuration.apiBaseURL?.absoluteString else { throw ClipoError.configuration }
            if Bundle.main.appStoreReceiptURL.flatMap({ try? Data(contentsOf: $0) })?.isEmpty != false {
                try await refreshReceipt()
            }
            guard let receiptURL = Bundle.main.appStoreReceiptURL, let receipt = try? Data(contentsOf: receiptURL), !receipt.isEmpty else {
                throw ClipoError.service("Apple’s receipt is unavailable. Retry confirmation when connected.")
            }
            // A refreshed credential is accepted only for the same original user.
            let owner = api.session?.userId.value == record.owner.userId.value ? (api.session ?? record.owner) : record.owner
            let body: [String: Any] = ["verificationData": receipt.base64EncodedString(), "purchaseID": record.orderID,
                "status": "purchased", "sandBoxTest": record.billing.sandBoxTest ?? false,
                "transactionId": transactionID, "iosVerifyShareKey": record.billing.iosVerifyShareKey ?? ""]
            _ = try await api.paymentRequest(path: "/app-api/flow/rights-order/buySuccess", body: body, owner: owner)
            var confirmed = records
            confirmed[index].confirmedIDs.insert(transactionID)
            try save(confirmed) // Keychain write and read-back must precede finishTransaction.
            SKPaymentQueue.default().finishTransaction(transaction)
            if api.session?.userId.value == record.owner.userId.value {
                let rights = try await api.rights()
                if api.session?.userId.value == record.owner.userId.value { expiration = rights.expiration }
            }
            message = "Purchase confirmed. Membership has been refreshed."
        } catch { self.error = "Purchase is pending confirmation. \(error.localizedDescription)" }
    }
    private func refreshReceipt() async throws {
        guard receiptRequest == nil else { throw ClipoError.service("Receipt refresh is already in progress. Please retry shortly.") }
        try await withCheckedThrowingContinuation { continuation in
            receiptContinuation = continuation
            let request = SKReceiptRefreshRequest(receiptProperties: nil)
            receiptRequest = request
            request.delegate = self
            request.start()
        }
    }
    private func save(_ next: [PurchaseRecord]) throws {
        guard ledgerAvailable else { throw ClipoError.storage }
        try SecureStorage.write(JSONEncoder().encode(next), key: "purchase-ledger")
        records = next
    }
}

extension CommerceStore: SKProductsRequestDelegate, SKRequestDelegate, SKPaymentTransactionObserver {
    nonisolated func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        Task { @MainActor in
            guard request === productsRequest else { return }
            guard let product = response.products.first(where: { $0.productIdentifier == requestedProductID }), product.subscriptionPeriod != nil else {
                finishProductRequest(request, result: .failure(ClipoError.service("This plan isn’t available from Apple yet. Please try again later.")))
                return
            }
            finishProductRequest(request, result: .success(product))
        }
    }
    nonisolated func request(_ request: SKRequest, didFailWithError error: Error) {
        Task { @MainActor in
            if request === receiptRequest {
                receiptRequest = nil
                receiptContinuation?.resume(throwing: error)
                receiptContinuation = nil
            } else if request === productsRequest {
                finishProductRequest(request, result: .failure(error))
            }
        }
    }
    nonisolated func requestDidFinish(_ request: SKRequest) {
        Task { @MainActor in
            if request === receiptRequest {
                receiptRequest = nil
                receiptContinuation?.resume()
                receiptContinuation = nil
            }
        }
    }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        Task { @MainActor in
            for transaction in transactions {
                switch transaction.transactionState {
                case .purchased, .restored: await confirm(transaction)
                case .failed:
                    busy = false
                    if let index = records.firstIndex(where: { $0.id == transaction.payment.applicationUsername }) {
                        var next = records; next[index].abandoned = true
                        do { try save(next) } catch { self.error = error.localizedDescription; continue }
                    }
                    if (transaction.error as? SKError)?.code == .paymentCancelled { message = "Purchase cancelled." }
                    else { error = transaction.error?.localizedDescription ?? "Purchase could not be completed." }
                    queue.finishTransaction(transaction)
                case .deferred: busy = false; message = "Your purchase is waiting for approval."
                case .purchasing: busy = true
                @unknown default: break
                }
            }
        }
    }
    nonisolated func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        Task { @MainActor in
            busy = false
            if queue.transactions.isEmpty { message = "Apple has no pending purchases to restore." }
            await refresh()
        }
    }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        Task { @MainActor in busy = false; self.error = error.localizedDescription }
    }
}
