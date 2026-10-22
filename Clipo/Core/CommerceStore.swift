import Foundation
import Combine
import StoreKit

private struct PurchaseFailure: Codable {
    let status: String
    let transactionID: String
    let receipt: String
}

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
    var failure: PurchaseFailure?
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
    @Published private(set) var loadingPlans = false
    @Published private(set) var plansError: String?
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
    private var processingFailures: Set<String> = []
    private var ownerID: String?
    private var refreshID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var refreshingOwner: String?
    var premium: Bool { expiration.map { $0 > Date() } ?? false }
    var canExportMedia: Bool {
        rightsVerified && premium && ownerID != nil && ownerID == api.session?.userId.value
    }
    func requireMediaExport() throws {
        guard rightsVerified, ownerID != nil, ownerID == api.session?.userId.value else {
            throw ClipoError.service("Connect to verify your Plus membership before exporting.")
        }
        guard premium else { throw ClipoError.service("Export is included with Plus.") }
    }
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
        let owner = api.session?.userId.value
        if let refreshTask, refreshingOwner == owner {
            await refreshTask.value
            return
        }
        refreshTask?.cancel()
        refreshingOwner = owner
        let id = UUID()
        refreshID = id
        let task = Task { await self.refreshRightsAndConfiguration(id: id) }
        refreshTask = task
        await task.value
        if refreshID == id { refreshTask = nil; refreshingOwner = nil }
    }
    private func refreshRightsAndConfiguration(id: UUID) async {
        guard refreshID == id, !Task.isCancelled else { return }
        rightsVerified = false
        let userID = api.session?.userId.value
        if ownerID != userID { expiration = nil; release = nil; ownerID = userID }
        quota.configure(userID: userID, policy: policy, remote: release?.quotaConfig)
        guard userID != nil else { return }
        error = nil
        // Independent requests share the authenticated session, not each other's latency.
        async let configurationRequest = api.releaseConfiguration()
        async let rightsRequest = api.rights()
        do {
            let configuration = try await configurationRequest
            guard refreshID == id, api.session?.userId.value == userID else { return }
            release = configuration
            quota.configure(userID: userID, policy: policy, remote: configuration.quotaConfig)
        } catch { if refreshID == id { self.error = error.localizedDescription } }
        guard refreshID == id, api.session?.userId.value == userID else { return }
        // Account rights remain independently refreshable if package configuration fails.
        do {
            let rights = try await rightsRequest
            guard refreshID == id, api.session?.userId.value == userID else { return }
            expiration = rights.expiration
            rightsVerified = true
        } catch { if refreshID == id, self.error == nil { self.error = error.localizedDescription } }
        retryPending()
    }
    // Fetch metadata when the paywall opens; this never creates an order or payment.
    func loadPlans() async {
        guard !loadingPlans, !preparingPurchase, !busy else { return }
        loadingPlans = true
        plansError = nil
        products = []
        defer { loadingPlans = false }
        for entry in policy?.products ?? [] {
            do {
                let product = try await requestProduct(entry.id)
                try Task.checkCancellation()
                products.append(product)
            } catch is CancellationError { return }
            catch { plansError = error.localizedDescription }
        }
        if products.isEmpty, plansError == nil {
            plansError = "This plan isn’t available from Apple yet. Please try again later."
        }
    }

    // Payment still requires an explicit action after Apple terms are visible.
    func purchase(planID: String) async {
        guard !busy, !preparingPurchase, !loadingPlans else { return }
        error = nil
        message = nil
        guard let owner = api.session else { error = "Your connection is not ready. Please try again shortly."; return }
        guard ledgerAvailable, policy?.products.contains(where: { $0.id == planID }) == true,
              let displayedProduct = products.first(where: { $0.productIdentifier == planID }) else {
            error = "Purchases are temporarily unavailable. Please try again later."; return
        }
        guard SKPaymentQueue.canMakePayments() else { error = "Purchases are not allowed on this device."; return }
        preparingPurchase = true
        defer { preparingPurchase = false }
        do {
            let product = try await requestProduct(planID)
            try Task.checkCancellation()
            guard api.session?.userId.value == owner.userId.value else { throw ClipoError.unauthorized }
            products.removeAll { $0.productIdentifier == product.productIdentifier }
            products.append(product)
            // If Apple changed the offer after display, show it before another purchase tap.
            guard displayedProduct.price == product.price,
                  displayedProduct.priceLocale == product.priceLocale,
                  displayedProduct.subscriptionPeriod?.unit == product.subscriptionPeriod?.unit,
                  displayedProduct.subscriptionPeriod?.numberOfUnits == product.subscriptionPeriod?.numberOfUnits else {
                throw ClipoError.service("Apple updated this plan. Review the price and billing period, then continue.")
            }
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
    func period(_ product: SKProduct, locale: Locale) -> String {
        guard let period = product.subscriptionPeriod else { return "" }
        var components = DateComponents()
        let unit: NSCalendar.Unit
        switch period.unit {
        case .day: unit = .day; components.day = period.numberOfUnits
        case .week: unit = .weekOfMonth; components.weekOfMonth = period.numberOfUnits
        case .month: unit = .month; components.month = period.numberOfUnits
        case .year: unit = .year; components.year = period.numberOfUnits
        @unknown default: return ""
        }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = unit
        formatter.unitsStyle = .full
        return formatter.string(from: components) ?? ""
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
                "usdPrice": entry.usdPrice, "packageName": api.configuration.servicePackageName,
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
        guard !busy, !preparingPurchase, !loadingPlans else { return }
        guard api.session != nil, ledgerAvailable else { error = "Your connection or purchase records are not ready. Please try again shortly."; return }
        busy = true
        error = nil
        message = "Checking your Apple purchases…"
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    func retryPending() {
        guard ledgerAvailable else { return }
        for record in records where record.failure != nil {
            Task { await reportFailure(recordID: record.id) }
        }
        for transaction in SKPaymentQueue.default().transactions where transaction.transactionState == .purchased || transaction.transactionState == .restored {
            Task { await confirm(transaction) }
        }
    }
    // A durable outbox allows cancellation/error reporting to retry after network loss
    // or a relaunch, without retaining a failed StoreKit transaction in the queue.
    private func reportFailure(recordID: String) async {
        guard !processingFailures.contains(recordID),
              let record = records.first(where: { $0.id == recordID }),
              let failure = record.failure else { return }
        processingFailures.insert(recordID)
        defer { processingFailures.remove(recordID) }
        do {
            guard record.apiHost == api.configuration.apiBaseURL?.absoluteString else { throw ClipoError.configuration }
            let owner = api.session?.userId.value == record.owner.userId.value ? (api.session ?? record.owner) : record.owner
            let body: [String: Any] = [
                "verificationData": failure.receipt, "purchaseID": record.orderID,
                "status": failure.status, "transactionId": failure.transactionID,
                "sandBoxTest": record.billing.sandBoxTest ?? false,
                "iosVerifyShareKey": record.billing.iosVerifyShareKey ?? ""
            ]
            _ = try await api.paymentRequest(path: "/app-api/flow/rights-order/buySuccess", body: body, owner: owner)
            guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
            var next = records
            next[index].failure = nil
            try save(next)
        } catch {
            // Keep the original status/owner and retry on refresh. Never report success.
            self.error = "Purchase status is waiting to sync. Please try again when connected."
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
            guard let product = response.products.first(where: { $0.productIdentifier == requestedProductID }), product.subscriptionPeriod.map({ $0.numberOfUnits > 0 }) == true else {
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
                    guard let index = records.firstIndex(where: { $0.id == transaction.payment.applicationUsername }) else {
                        self.error = "An Apple purchase is awaiting account reconciliation. Its original order could not be identified; it has not been discarded."
                        continue
                    }
                    let cancelled = (transaction.error as? SKError)?.code == .paymentCancelled
                    var next = records
                    next[index].abandoned = true
                    next[index].failure = PurchaseFailure(
                        status: cancelled ? "canceled" : "error",
                        transactionID: transaction.transactionIdentifier ?? "",
                        receipt: Bundle.main.appStoreReceiptURL.flatMap { try? Data(contentsOf: $0) }?.base64EncodedString() ?? "")
                    do { try save(next) } catch { self.error = error.localizedDescription; continue }
                    if cancelled { message = "Purchase cancelled." }
                    else { error = transaction.error?.localizedDescription ?? "Purchase could not be completed." }
                    queue.finishTransaction(transaction)
                    let recordID = next[index].id
                    Task { await reportFailure(recordID: recordID) }
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
            else if message == "Checking your Apple purchases…" { message = nil }
            await refresh()
        }
    }
    nonisolated func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        Task { @MainActor in
            busy = false
            message = nil
            if (error as? SKError)?.code == .paymentCancelled {
                self.error = nil
                message = "Restore cancelled. Your purchases have not changed."
            } else {
                self.error = "Apple couldn’t restore purchases. Sign in to your Apple account and try again."
            }
        }
    }
}
