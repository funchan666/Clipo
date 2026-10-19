import Foundation
import Combine

struct DailyUsage: Codable {
    var day: Date
    var watched: Set<String> = []
    var favoritesUsed = 0
    var completedRewardIDs: Set<UUID> = []
    var extraWatches = 0
    var extraFavorites = 0
}
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var usage: DailyUsage?
    @Published var error: String?
    private var userID: String?
    private var policy: CommerceConfiguration?
    private var remote: QuotaConfiguration?
    private var storageOK = true
    private var timeZone = TimeZone.current
    var unlimited: Bool { (usage?.completedRewardIDs.count ?? 0) >= (policy?.unlimitedAfterCompletedAds ?? Int.max) }
    var watchesLeft: Int { max(0, (remote?.dailyWatchLimit ?? policy?.dailyWatchLimit ?? 0) + (usage?.extraWatches ?? 0) - (usage?.watched.count ?? 0)) }
    var favoritesLeft: Int { max(0, (remote?.favoriteBaseLimit ?? policy?.dailyFavoriteLimit ?? 0) + (usage?.extraFavorites ?? 0) - (usage?.favoritesUsed ?? 0)) }
    var rewardSummary: String {
        guard let policy else { return "Rewards are unavailable." }
        let count = usage?.completedRewardIDs.count ?? 0
        if count + 1 >= policy.unlimitedAfterCompletedAds { return "Watch a full ad for unlimited viewing until 5 AM and \(policy.favoriteReward) more saves." }
        return "Watch a full ad for \(nextWatchReward) more views and \(policy.favoriteReward) more saves."
    }
    private var nextWatchReward: Int {
        let index = min(usage?.completedRewardIDs.count ?? 0, 2)
        let remoteValues = [remote?.firstAdRewardWatchCount, remote?.secondAdRewardWatchCount, remote?.thirdAdRewardWatchCount]
        return max(0, remoteValues[index] ?? policy?.watchRewards[safe: index] ?? 0)
    }
    func configure(userID: String?, policy: CommerceConfiguration?, remote: QuotaConfiguration?) {
        self.policy = policy
        self.remote = remote
        guard self.userID != userID || usage == nil else { resetIfNeeded(); return }
        self.userID = userID
        usage = nil
        storageOK = true
        error = nil
        timeZone = .current
        guard userID != nil else { return }
        do {
            if let data = try SecureStorage.read(key) { usage = try JSONDecoder().decode(DailyUsage.self, from: data) }
            else { try commit(DailyUsage(day: boundary())) }
            resetIfNeeded()
        } catch { storageOK = false; self.error = "Daily allowance could not be read. Please try again later." }
    }
    func resetIfNeeded() {
        guard storageOK, userID != nil, let usage else { return }
        let today = boundary()
        // Only move forward; turning the clock back cannot restore spent allowance.
        if today > usage.day {
            do { try commit(DailyUsage(day: today)) }
            catch { storageOK = false; self.error = error.localizedDescription }
        }
    }
    func mayWatch(_ id: String, premium: Bool) -> Bool {
        resetIfNeeded()
        return premium || (storageOK && userID != nil && (unlimited || usage?.watched.contains(id) == true || watchesLeft > 0))
    }
    func recordWatch(_ id: String, premium: Bool) -> Bool {
        guard mayWatch(id, premium: premium) else { return false }
        if premium || unlimited { return true }
        guard var next = usage else { return false }
        next.watched.insert(id)
        do { try commit(next); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func consumeFavorite(premium: Bool) -> Bool {
        resetIfNeeded()
        if premium { return true }
        guard storageOK, favoritesLeft > 0, var next = usage else { return false }
        next.favoritesUsed += 1
        do { try commit(next); return true }
        catch { error = error.localizedDescription; return false }
    }
    func refundFavorite() {
        guard var next = usage, next.favoritesUsed > 0 else { return }
        next.favoritesUsed -= 1
        do { try commit(next) } catch { self.error = error.localizedDescription }
    }
    func reward(_ id: UUID, owner: String) throws {
        guard owner == userID, storageOK else { throw ClipoError.storage }
        resetIfNeeded()
        guard var next = usage, let policy else { throw ClipoError.configuration }
        guard !next.completedRewardIDs.contains(id) else { return }
        next.extraWatches += nextWatchReward
        next.extraFavorites += max(0, policy.favoriteReward)
        next.completedRewardIDs.insert(id)
        try commit(next)
    }
    private var key: String { "quota.\(userID ?? "none")" }
    private func boundary() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let five = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? start
        return now >= five ? five : (calendar.date(byAdding: .day, value: -1, to: five) ?? five)
    }
    private func commit(_ value: DailyUsage) throws {
        try SecureStorage.write(JSONEncoder().encode(value), key: key)
        usage = value
    }
}
extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
