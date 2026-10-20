import Foundation
import Combine
import GoogleMobileAds
import UserMessagingPlatform
import UIKit

@MainActor
final class RewardedAds: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var busy = false
    @Published private(set) var isPresenting = false
    @Published private(set) var privacyOptionsRequired = false
    @Published var error: String?
    @Published var message: String?
    @Published var luckyReward: LuckyRewardNotice?
    @Published private(set) var startupFinished = false
    private var startupStarted = false
    @Published private(set) var isPreparingAppOpen = false
    private var appOpenTask: Task<Void, Never>?
    private var appOpenDeadline: Task<Void, Never>?
    private var appOpenAttempt: UUID?
    private var appOpenHistoryKey: String?
    private var returnedFromBackground = false
    private var appOpenAd: AppOpenAd?
    private var rewarded: RewardedAd?
    private var rewardGranted = false
    private var started = false
    private static let demoAppID = "ca-app-pub-3940256099942544~1458002511"
    private static let demoRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"

    private static let demoAppOpenUnitID = "ca-app-pub-3940256099942544/5575463023"

    func watch(commerce: CommerceStore, quota: QuotaStore) async {
        guard !busy, !isPresenting, !isPreparingAppOpen else { return }
        guard let policy = commerce.policy, let owner = commerce.api.session?.userId.value else {
            error = "Rewarded ads are not available right now. No views have been deducted."; return
        }
        let demoMode = (Bundle.main.object(forInfoDictionaryKey: "ClipoAdsTestMode") as? String) == "YES"
        let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        let unitID: String
        if demoMode {
            // Demo mode must never load an account-owned ad unit, even if the backend sends one.
            guard appID == Self.demoAppID else {
                error = "Test ads require Google's sample iOS App ID."; return
            }
            unitID = Self.demoRewardedUnitID
        } else {
            guard let appID, appID.hasPrefix("ca-app-pub-"), appID.contains("~"), appID != Self.demoAppID,
                  let unit = commerce.release?.adList?.first(where: { $0.adType == policy.rewardedAdType && $0.advertiser?.lowercased() == "google" }),
                  let configuredUnitID = unit.config.adUnitId?.nilIfBlank, unit.config.appId == appID else {
                error = "Rewarded ads are not available right now. No views have been deducted."; return
            }
            unitID = configuredUnitID
        }
        busy = true
        error = nil
        message = nil
        rewardGranted = false
        let attemptID = UUID()
        var loadingRewarded = false
        do {
            try await prepareSDK(demoMode: demoMode, mayPresentConsent: true)
            loadingRewarded = true
            let ad = try await RewardedAd.load(with: unitID, request: Request())
            loadingRewarded = false
            guard commerce.api.session?.userId.value == owner else { throw ClipoError.unauthorized }
            rewarded = ad
            ad.fullScreenContentDelegate = self
            let rewardID = UUID()
            isPresenting = true
            ad.present(from: nil) { [weak self] in
                guard let self, !self.rewardGranted else { return }
                do {
                    try quota.reward(rewardID, owner: owner)
                    self.rewardGranted = true
                    self.message = "Your viewing and save allowance has been updated."
                } catch { self.error = "The ad finished, but its reward could not be saved. \(error.localizedDescription)" }
            }
        } catch {
            isPresenting = false
            let failure = error as NSError
            // Do not treat offline, configuration, consent, or presentation errors as no-fill.
            if loadingRewarded, failure.domain == GADErrorDomain, failure.code == 1 {
                do {
                    guard commerce.api.session?.userId.value == owner else { throw ClipoError.unauthorized }
                    if let gift = try quota.rewardNoFill(attemptID, owner: owner) {
                        luckyReward = LuckyRewardNotice(message: gift)
                    }
                } catch { self.error = error.localizedDescription }
            } else {
                self.error = "An ad could not be loaded. Please try again later. \(error.localizedDescription)"
            }
        }
        busy = false
    }
    private func prepareSDK(demoMode: Bool, mayPresentConsent: Bool) async throws {
        if !demoMode {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            if mayPresentConsent { try await ConsentForm.loadAndPresentIfRequired(from: nil) }
            guard ConsentInformation.shared.canRequestAds else { throw ClipoError.service("Ads are unavailable with your current privacy choices.") }
        } else {
            // Google's demo app has no Clipo-owned UMP message configuration.
            // This branch is restricted to the exact official demo App ID and ad unit above.
            privacyOptionsRequired = false
        }
        if !started {
            await withCheckedContinuation { continuation in
                MobileAds.shared.start { _ in continuation.resume() }
            }
            started = true
        }
    }

    // Cold start includes pre-login guest preparation. Foreground returns use the same gate.
    func beginStartup(commerce: CommerceStore, accountAccess: AccountAccessFlow) {
        guard !startupStarted else { return }
        startupStarted = true
        requestAppOpen(commerce: commerce, accountAccess: accountAccess, coldStart: true)
    }

    func didEnterBackground() {
        // An ad or SDK consent browser returning to the app must not recursively trigger an ad.
        returnedFromBackground = !isPresenting && !isPreparingAppOpen
        if isPreparingAppOpen { finishAppOpen() }
    }

    func didBecomeActive(commerce: CommerceStore, accountAccess: AccountAccessFlow) {
        guard returnedFromBackground else { return }
        returnedFromBackground = false
        requestAppOpen(commerce: commerce, accountAccess: accountAccess, coldStart: false)
    }

    private func requestAppOpen(commerce: CommerceStore, accountAccess: AccountAccessFlow, coldStart: Bool) {
        guard appOpenAttempt == nil, !busy, !isPresenting,
              !commerce.busy, !commerce.preparingPurchase, !accountAccess.isBusy else {
            if coldStart { startupFinished = true }
            return
        }
        let attempt = UUID()
        appOpenAttempt = attempt
        isPreparingAppOpen = true
        // A slow/unavailable backend must not leave the splash or welcome button blocked.
        appOpenDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.appOpenAttempt == attempt, !self.isPresenting else { return }
            self.finishAppOpen()
        }
        appOpenTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await commerce.api.prepareVisitor()
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, let owner = commerce.api.session?.userId.value else {
                    self.finishAppOpen(attempt: attempt); return
                }
                await commerce.refresh()
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, commerce.api.session?.userId.value == owner,
                      commerce.rightsVerified, !commerce.premium else {
                    self.finishAppOpen(attempt: attempt); return
                }
                let demoMode = (Bundle.main.object(forInfoDictionaryKey: "ClipoAdsTestMode") as? String) == "YES"
                let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
                let unit = commerce.release?.adList?.first {
                    $0.adType == 1 && $0.advertiser?.lowercased() == "google"
                }
                // Only official demo mode can run without package ad configuration.
                let interval = unit?.displayInterval ?? (demoMode ? 0 : nil)
                let unitID: String
                if demoMode, appID == Self.demoAppID { unitID = Self.demoAppOpenUnitID }
                else if !demoMode, let appID, appID != Self.demoAppID,
                        let unit, unit.config.appId == appID,
                        let configured = unit.config.adUnitId?.nilIfBlank,
                        configured.hasPrefix("ca-app-pub-"), configured.contains("/") {
                    unitID = configured
                } else { self.finishAppOpen(attempt: attempt); return }
                let key = "app-open.last-impression.\(commerce.api.configuration.bundleID).\(commerce.api.configuration.apiBaseURL?.host ?? "none").\(demoMode ? "demo" : "production")"
                let lastShown = UserDefaults.standard.object(forKey: key) as? Date
                guard AppOpenTiming.isDue(intervalMinutes: interval, lastShown: lastShown) else {
                    self.finishAppOpen(attempt: attempt); return
                }
                // Consent is a genuine Google surface; don't time out underneath it.
                self.appOpenDeadline?.cancel()
                try await self.prepareSDK(demoMode: demoMode, mayPresentConsent: true)
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt else { return }
                self.appOpenDeadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    guard let self, self.appOpenAttempt == attempt, !self.isPresenting else { return }
                    self.finishAppOpen()
                }
                let ad = try await AppOpenAd.load(with: unitID, request: Request())
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, commerce.api.session?.userId.value == owner,
                      !commerce.premium, UIApplication.shared.applicationState == .active,
                      !self.busy, !self.isPresenting, !commerce.busy, !commerce.preparingPurchase,
                      !accountAccess.isBusy,
                      AppOpenTiming.isDue(intervalMinutes: interval,
                        lastShown: UserDefaults.standard.object(forKey: key) as? Date) else {
                    self.finishAppOpen(attempt: attempt); return
                }
                try ad.canPresent(from: nil)
                self.appOpenAd = ad
                self.appOpenHistoryKey = key
                ad.fullScreenContentDelegate = self
                self.appOpenDeadline?.cancel()
                self.isPreparingAppOpen = false
                self.isPresenting = true
                ad.present(from: nil)
            } catch { self.finishAppOpen(attempt: attempt) }
        }
    }

    private func finishAppOpen(attempt: UUID? = nil) {
        if let attempt, attempt != appOpenAttempt { return }
        appOpenAttempt = nil
        appOpenDeadline?.cancel()
        appOpenDeadline = nil
        appOpenTask?.cancel()
        appOpenTask = nil
        appOpenAd = nil
        appOpenHistoryKey = nil
        isPreparingAppOpen = false
        isPresenting = false
        startupFinished = true
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        guard let current = appOpenAd, ad === current, let key = appOpenHistoryKey else { return }
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func privacyOptions() async {
        do { try await ConsentForm.presentPrivacyOptionsForm(from: nil) }
        catch { self.error = error.localizedDescription }
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if ad is AppOpenAd { finishAppOpen(); return }
        rewarded = nil
        isPresenting = false
        if !rewardGranted, error == nil { message = "No reward was received. Finish a rewarded ad to get more views." }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if ad is AppOpenAd { finishAppOpen(); return }
        rewarded = nil
        isPresenting = false
        self.error = error.localizedDescription
    }
}

struct LuckyRewardNotice: Identifiable {
    let id = UUID()
    let message: String
}
