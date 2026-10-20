import Foundation

// Test-only persistence double. This file is not an app target source; the production
// QuotaStore is compiled unchanged against an isolated, in-memory ledger.
@MainActor enum SecureStorage {
    static var values: [String: Data] = [:]
    static var failWrites = false
    static func read(_ key: String) throws -> Data? { values[key] }
    static func write(_ data: Data, key: String) throws {
        if failWrites { throw ClipoError.storage }
        values[key] = data
    }
}
@main enum QuotaContractChecks {
    @MainActor static func main() throws {
        let policy = CommerceConfiguration(products: [], rewardedAdType: 2,
            unlimitedAfterCompletedAds: 4, favoriteReward: 5, dailyWatchLimit: 5,
            dailyFavoriteLimit: 5, watchRewards: [3, 4, 6])
        func store() -> QuotaStore {
            let store = QuotaStore()
            store.configure(userID: "test", policy: policy, remote: nil)
            return store
        }
        var quota = store()
        let firstGift = UUID()
        precondition(tryValue { try quota.rewardNoFill(firstGift, owner: "test") } != nil)
        precondition(quota.watchesLeft == 8 && quota.favoritesLeft == 10)
        precondition(quota.usage?.completedRewardIDs.isEmpty == true && !quota.unlimited)
        precondition(tryValue { try quota.rewardNoFill(firstGift, owner: "test") } == nil)
        do { _ = try quota.rewardNoFill(UUID(), owner: "test"); fatalError("Cooldown bypassed") } catch { }
        do { _ = try quota.rewardNoFill(UUID(), owner: "other"); fatalError("Owner bypassed") } catch { }
        // Complete three real-ad callbacks, then allow a new no-fill request.
        for _ in 0..<3 { try quota.reward(UUID(), owner: "test") }
        var saved = quota.usage!
        saved.lastLuckyReward = Date().addingTimeInterval(-61)
        try SecureStorage.write(JSONEncoder().encode(saved), key: "quota.test")
        quota = store()
        let before = quota.watchesLeft
        _ = try quota.rewardNoFill(UUID(), owner: "test")
        precondition(quota.watchesLeft == before + 6 && !quota.unlimited)
        precondition(quota.usage?.completedRewardIDs.count == 3)
        let fourth = UUID()
        try quota.reward(fourth, owner: "test")
        let after = quota.favoritesLeft
        try quota.reward(fourth, owner: "test")
        precondition(quota.unlimited && quota.favoritesLeft == after)
        precondition(store().unlimited) // persisted completion survives reconstruction
        saved = quota.usage!
        saved.lastLuckyReward = Date().addingTimeInterval(-61)
        try SecureStorage.write(JSONEncoder().encode(saved), key: "quota.test")
        quota = store()
        let oldViews = quota.watchesLeft
        _ = try quota.rewardNoFill(UUID(), owner: "test")
        precondition(quota.watchesLeft == oldViews && quota.unlimited)
        precondition(quota.favoritesLeft == after + 5)
        // Failure must not publish or claim a reward before persistence succeeds.
        saved = quota.usage!
        saved.lastLuckyReward = Date().addingTimeInterval(-61)
        try SecureStorage.write(JSONEncoder().encode(saved), key: "quota.test")
        quota = store()
        SecureStorage.failWrites = true
        let beforeFailure = quota.favoritesLeft
        do { _ = try quota.rewardNoFill(UUID(), owner: "test"); fatalError("Failed write accepted") } catch { }
        precondition(quota.favoritesLeft == beforeFailure)
        SecureStorage.failWrites = false
        // Existing JSON without the new optional fields remains readable.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        json.removeValue(forKey: "luckyRewardIDs"); json.removeValue(forKey: "lastLuckyReward")
        let legacy = try JSONDecoder().decode(DailyUsage.self, from: JSONSerialization.data(withJSONObject: json))
        precondition(legacy.completedRewardIDs.count == 4 && legacy.luckyRewardIDs == nil)
        print("PASS: no-fill phase, cooldown, owner, idempotency, fourth-ad unlimited, persistence, write failure, legacy ledger")
    }
    static func tryValue<T>(_ operation: () throws -> T) -> T { try! operation() }
}
