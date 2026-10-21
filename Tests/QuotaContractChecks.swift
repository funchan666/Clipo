import Foundation

// Standalone checks, deliberately not executed in the static-only delivery.
// Production QuotaStore uses this isolated in-memory persistence double here.
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
        let policy = CommerceConfiguration(products: [], rewardedAdType: 5,
            unlimitedAfterCompletedAds: 4, favoriteReward: 5, dailyWatchLimit: 5,
            dailyFavoriteLimit: 5, watchRewards: [3, 4, 6])
        func store(_ user: String = "test", remote: QuotaConfiguration? = nil) -> QuotaStore {
            let value = QuotaStore()
            value.configure(userID: user, policy: policy, remote: remote)
            return value
        }
        let quota = store()
        precondition(!quota.canRequestReward(for: .watch, premium: false))
        precondition(tryValue { try quota.rewardNoFill(UUID(), owner: "test", kind: .watch) } == nil)
        for n in 0..<5 { precondition(quota.recordWatch("watch-\(n)", premium: false)) }
        precondition(quota.watchesLeft == 0 && quota.downloadsLeft == 5)
        precondition(quota.recordWatch("watch-0", premium: false))
        precondition(!quota.mayWatch("new", premium: false))
        precondition(quota.canRequestReward(for: .watch, premium: false))
        precondition(quota.claimWatchLimitPrompt(premium: false))
        precondition(!quota.claimWatchLimitPrompt(premium: false))
        precondition(!quota.claimWatchLimitPrompt(premium: true))
        // No-fill gifts stay in the same phase; a second exhausted request has no cooldown.
        for round in 0..<2 {
            let id = UUID()
            precondition(tryValue { try quota.rewardNoFill(id, owner: "test", kind: .watch) } != nil)
            precondition(quota.watchesLeft == 3 && quota.completedAds(.watch) == 0)
            precondition(!quota.claimWatchLimitPrompt(premium: false))
            for n in 0..<3 { precondition(quota.recordWatch("gift-\(round)-\(n)", premium: false)) }
            precondition(quota.claimWatchLimitPrompt(premium: false))
            precondition(!quota.claimWatchLimitPrompt(premium: false))
            precondition(tryValue { try quota.rewardNoFill(id, owner: "test", kind: .watch) } == nil)
        }
        do { try quota.reward(UUID(), owner: "other", kind: .watch); fatalError("Owner bypassed") } catch { }
        for n in 0..<3 {
            try quota.reward(UUID(), owner: "test", kind: .watch)
            let reward = [3, 4, 6][n]
            for i in 0..<reward { precondition(quota.recordWatch("ad-\(n)-\(i)", premium: false)) }
        }
        _ = try quota.rewardNoFill(UUID(), owner: "test", kind: .watch)
        precondition(quota.watchesLeft == 6 && !quota.unlimited && quota.completedAds(.watch) == 3)
        let fourth = UUID()
        try quota.reward(fourth, owner: "test", kind: .watch)
        try quota.reward(fourth, owner: "test", kind: .watch)
        precondition(quota.unlimited && !quota.downloadsUnlimited && quota.completedAds(.watch) == 4)
        precondition(quota.downloadsLeft == 5)
        for n in 0..<5 { try quota.recordDownload("download-\(n)", owner: "test", premium: false) }
        precondition(quota.downloadsLeft == 0)
        try quota.recordDownload("download-0", owner: "test", premium: false)
        precondition(quota.downloadsLeft == 0)
        precondition(!quota.mayDownload("new", premium: false))
        precondition(quota.canRequestReward(for: .download, premium: false))
        _ = try quota.rewardNoFill(UUID(), owner: "test", kind: .download)
        precondition(quota.downloadsLeft == 5 && quota.completedAds(.download) == 0)
        for _ in 0..<4 { try quota.reward(UUID(), owner: "test", kind: .download) }
        precondition(quota.downloadsUnlimited && store().downloadsUnlimited)
        // UTC day rollover resets both counters but preserves downloaded identities.
        var saved = quota.usage!
        saved.day = Date().addingTimeInterval(-2 * 86_400)
        try SecureStorage.write(JSONEncoder().encode(saved), key: "quota.test")
        let reset = store()
        precondition(!reset.unlimited && !reset.downloadsUnlimited)
        precondition(reset.watchesLeft == 5 && reset.downloadsLeft == 5)
        try reset.recordDownload("download-0", owner: "test", premium: false)
        precondition(reset.downloadsLeft == 5)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        precondition(utc.component(.hour, from: reset.usage!.day) == 5)
        // Watching during membership must still be remembered when membership expires.
        precondition(reset.recordWatch("premium-view", premium: true))
        precondition(reset.recordWatch("premium-view", premium: false) && reset.watchesLeft == 5)
        // Failure to save never publishes a charge or reward.
        SecureStorage.failWrites = true
        do { try reset.recordDownload("write-fail", owner: "test", premium: false); fatalError("Failed write accepted") } catch { }
        precondition(reset.downloadsLeft == 5 && reset.usage?.downloaded?.contains("write-fail") == false)
        SecureStorage.failWrites = false
        // Unequal values expose swapped field mapping; old names now mean downloads.
        let remote = try JSONDecoder().decode(QuotaConfiguration.self, from:
            Data(#"{"unlimitedAfterAdCount":11,"favoriteBaseLimit":2}"#.utf8))
        let configured = store("remote", remote: remote)
        precondition(configured.downloadsLeft == 11)
        try configured.reward(UUID(), owner: "remote", kind: .download)
        precondition(configured.downloadsLeft == 13 && configured.watchesLeft == 5)
        let zero = try JSONDecoder().decode(QuotaConfiguration.self, from: Data(#"{"favoriteBaseLimit":0}"#.utf8))
        let fallback = store("fallback", remote: zero)
        try fallback.reward(UUID(), owner: "fallback", kind: .download)
        precondition(fallback.downloadsLeft == 5)
        // A live configuration changes ad rewards now, but cannot refill a spent base.
        let oldAllowance = try JSONDecoder().decode(QuotaConfiguration.self, from:
            Data(#"{"dailyWatchLimit":5,"unlimitedAfterAdCount":5,"firstAdRewardWatchCount":3,"favoriteBaseLimit":2}"#.utf8))
        let newAllowance = try JSONDecoder().decode(QuotaConfiguration.self, from:
            Data(#"{"dailyWatchLimit":20,"unlimitedAfterAdCount":10,"firstAdRewardWatchCount":7,"favoriteBaseLimit":4}"#.utf8))
        let daily = store("daily", remote: oldAllowance)
        precondition(daily.recordWatch("daily-view", premium: false))
        try daily.recordDownload("daily-download", owner: "daily", premium: false)
        daily.configure(userID: "daily", policy: policy, remote: newAllowance)
        precondition(daily.watchesLeft == 4 && daily.downloadsLeft == 4)
        // Both the freeze and pending values survive process recreation / a missing refresh.
        let reloaded = store("daily")
        precondition(reloaded.watchesLeft == 4 && reloaded.downloadsLeft == 4)
        reloaded.configure(userID: "daily", policy: policy, remote: newAllowance)
        try reloaded.reward(UUID(), owner: "daily", kind: .watch)
        try reloaded.reward(UUID(), owner: "daily", kind: .download)
        precondition(reloaded.watchesLeft == 11 && reloaded.downloadsLeft == 8)
        var priorDay = reloaded.usage!
        priorDay.day = Date().addingTimeInterval(-2 * 86_400)
        try SecureStorage.write(JSONEncoder().encode(priorDay), key: "quota.daily")
        let nextDay = store("daily")
        precondition(nextDay.watchesLeft == 20 && nextDay.downloadsLeft == 10)
        precondition(nextDay.completedAds(.watch) == 0 && nextDay.completedAds(.download) == 0)
        try nextDay.recordDownload("daily-download", owner: "daily", premium: false)
        precondition(nextDay.downloadsLeft == 10)
        // Untouched bases may refresh today; watch/download locks are independent.
        let separate = store("separate", remote: oldAllowance)
        precondition(separate.recordWatch("used-watch", premium: false))
        separate.configure(userID: "separate", policy: policy, remote: newAllowance)
        precondition(separate.watchesLeft == 4 && separate.downloadsLeft == 10)
        let noBase = try JSONDecoder().decode(QuotaConfiguration.self, from:
            Data(#"{"dailyWatchLimit":0,"unlimitedAfterAdCount":0,"firstAdRewardWatchCount":0,"favoriteBaseLimit":0}"#.utf8))
        separate.configure(userID: "separate", policy: policy, remote: noBase)
        precondition(separate.watchesLeft == 4 && separate.downloadsLeft == 0)
        try separate.reward(UUID(), owner: "separate", kind: .watch)
        precondition(separate.watchesLeft == 4) // Explicit zero reward is not replaced by a fallback.
        // Old favorite spend is not a download; existing watch history survives migration.
        var legacy = DailyUsage(day: Date())
        legacy.watched = ["already-watched"]; legacy.favoritesUsed = 4; legacy.extraFavorites = 10
        try SecureStorage.write(JSONEncoder().encode(legacy), key: "quota.legacy")
        let migrated = store("legacy")
        precondition(migrated.watchesLeft == 4 && migrated.downloadsLeft == 5)
        print("PASS: independent quotas, repeat deduplication, UTC rollover, no-fill, ownership, persistence and migration")
    }
    static func tryValue<T>(_ operation: () throws -> T) -> T { try! operation() }
}
