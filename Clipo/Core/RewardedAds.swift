import Foundation
import Combine
import GoogleMobileAds
import UserMessagingPlatform
import UIKit
import OSLog

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
    private var appOpenPreloadTask: Task<AppOpenAd, Error>?
    private let appOpenLog = Logger(subsystem: "com.clipo.video", category: "AppOpen")
    private var appOpenStage = "idle"
    private var appOpenDeadline: Task<Void, Never>?
    private var appOpenAttempt: UUID?
    private var appOpenHistoryKey: String?
    private var returnedFromBackground = false
    private var appOpenAd: AppOpenAd?
    private var rewarded: RewardedAd?
    private var rewardGranted = false
    private var rewardAttempt: UUID?
    @Published private(set) var completedReward: UUID?
    private var started = false
    private static let demoAppID = "ca-app-pub-3940256099942544~1458002511"
    private static let demoRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"

    private static let demoAppOpenUnitID = "ca-app-pub-3940256099942544/5575463023"

    func watch(commerce: CommerceStore, quota: QuotaStore, kind: AllowanceKind) async {
        guard !busy, !isPresenting, !isPreparingAppOpen else { return }
        quota.resetIfNeeded()
        guard quota.canRequestReward(for: kind, premium: commerce.premium) else { return }
        guard commerce.rightsVerified, let policy = commerce.policy, let owner = commerce.api.session?.userId.value else {
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
        let attemptID = UUID()
        rewardAttempt = attemptID
        busy = true
        defer {
            if rewardAttempt == attemptID { busy = false; rewardAttempt = nil }
        }
        error = nil
        message = nil
        luckyReward = nil
        rewardGranted = false
        var loadingRewarded = false
        var timeout: Task<Void, Never>?
        func armDeadline() {
            timeout?.cancel()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self, self.rewardAttempt == attemptID, !self.isPresenting else { return }
                self.rewardAttempt = nil
                self.busy = false
                if loadingRewarded {
                    self.grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
                } else {
                    self.error = "Rewarded ads are not available right now. No views have been deducted."
                }
            }
        }
        // Include SDK preparation in the wait budget. Only the real privacy
        // consent surface may pause it; loading can always be cancelled.
        armDeadline()
        defer { timeout?.cancel() }
        do {
            try await prepareSDK(demoMode: demoMode, mayPresentConsent: true,
                                 mayContinue: { self.rewardAttempt == attemptID }) { presenting in
                if presenting { timeout?.cancel() }
                else { armDeadline() }
            }
            try Task.checkCancellation()
            guard rewardAttempt == attemptID else { return }
            loadingRewarded = true
            let ad = try await RewardedAd.load(with: unitID, request: Request())
            loadingRewarded = false
            try Task.checkCancellation()
            guard rewardAttempt == attemptID, UIApplication.shared.applicationState == .active else { return }
            try ad.canPresent(from: nil)
            guard commerce.api.session?.userId.value == owner, !commerce.premium else { throw ClipoError.unauthorized }
            rewarded = ad
            ad.fullScreenContentDelegate = self
            let rewardID = UUID()
            isPresenting = true
            ad.present(from: nil) { [weak self, weak ad] in
                guard let self, let ad, self.rewarded === ad, !self.rewardGranted else { return }
                do {
                    try quota.reward(rewardID, owner: owner, kind: kind)
                    self.rewardGranted = true
                    self.message = kind == .watch ? "Your viewing allowance has been updated." : "Your download allowance has been updated."
                } catch { self.error = "The ad finished, but its reward could not be saved. \(error.localizedDescription)" }
            }
        } catch {
            guard rewardAttempt == attemptID else { return }
            isPresenting = false
            let failure = error as NSError
            // A cancelled request is not an unavailable-ad result. Once an actual
            // SDK load fails without an ad (including network/timeout/mediation),
            // apply the documented lucky gift, not only Google's no-fill code.
            if Task.isCancelled || error is CancellationError ||
                (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) { return }
            if loadingRewarded {
                grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            } else {
                self.error = "An ad could not be loaded. Please try again later. \(error.localizedDescription)"
            }
        }
    }
    func cancelRewardLoading() {
        guard !isPresenting else { return }
        rewardAttempt = nil
        busy = false
    }

    private func grantUnavailableReward(_ attempt: UUID, owner: String, commerce: CommerceStore,
                                        quota: QuotaStore, kind: AllowanceKind) {
        do {
            guard commerce.api.session?.userId.value == owner else { throw ClipoError.unauthorized }
            guard !commerce.premium else { return }
            if let gift = try quota.rewardNoFill(attempt, owner: owner, kind: kind) {
                luckyReward = LuckyRewardNotice(message: gift)
            }
        } catch { self.error = error.localizedDescription }
    }

    private func prepareSDK(demoMode: Bool, mayPresentConsent: Bool,
                            mayContinue: () -> Bool = { true },
                            consentPresentation: ((Bool) -> Void)? = nil) async throws {
        try Task.checkCancellation()
        guard mayContinue() else { throw CancellationError() }
        if !demoMode {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            try Task.checkCancellation()
            guard mayContinue() else { throw CancellationError() }
            if mayPresentConsent {
                consentPresentation?(true)
                defer { consentPresentation?(false) }
                try await ConsentForm.loadAndPresentIfRequired(from: nil)
            }
            guard ConsentInformation.shared.canRequestAds else { throw ClipoError.service("Ads are unavailable with your current privacy choices.") }
        } else {
            // Google's demo app has no Clipo-owned UMP message configuration.
            // This branch is restricted to the exact official demo App ID and ad unit above.
            privacyOptionsRequired = false
        }
        try Task.checkCancellation()
        guard mayContinue() else { throw CancellationError() }
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
        returnedFromBackground = !isPresenting && !isPreparingAppOpen && !busy
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
        // A two-second combined budget cancelled cold-start ads before the SDK
        // could finish loading. Keep one bounded opportunity, with demo loading
        // running alongside login/configuration rather than after both complete.
        let waitingBudget = coldStart ? 6.0 : 4.0
        appOpenStage = "authentication"
        appOpenLog.info("App-open opportunity started; coldStart=\(coldStart), budget=\(waitingBudget)")
        scheduleAppOpenDeadline(attempt: attempt, seconds: waitingBudget)
        appOpenTask = Task { [weak self] in
            guard let self else { return }
            let demoMode = (Bundle.main.object(forInfoDictionaryKey: "ClipoAdsTestMode") as? String) == "YES"
            let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
            if demoMode, appID == Self.demoAppID {
                // Official test inventory needs no account configuration. Actual
                // presentation still waits for verified rights and the interval.
                self.appOpenPreloadTask = Task { [weak self] in
                    guard let self else { throw CancellationError() }
                    try await self.prepareSDK(demoMode: true, mayPresentConsent: false,
                                              mayContinue: { self.appOpenAttempt == attempt })
                    try Task.checkCancellation()
                    guard self.appOpenAttempt == attempt else { throw CancellationError() }
                    let ad = try await AppOpenAd.load(with: Self.demoAppOpenUnitID, request: Request())
                    try Task.checkCancellation()
                    return ad
                }
            }
            do {
                try await commerce.api.prepareVisitor()
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, let owner = commerce.api.session?.userId.value else {
                    self.finishAppOpen(attempt: attempt); return
                }
                self.appOpenStage = "rights-and-configuration"
                await commerce.refresh()
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, commerce.api.session?.userId.value == owner,
                      commerce.rightsVerified, !commerce.premium else {
                    self.finishAppOpen(attempt: attempt, reason: commerce.premium ? "membership" : "rights-unavailable"); return
                }
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
                } else { self.finishAppOpen(attempt: attempt, reason: "ad-configuration-unavailable"); return }
                let key = "app-open.last-impression.\(commerce.api.configuration.bundleID).\(commerce.api.configuration.apiBaseURL?.host ?? "none").\(demoMode ? "demo" : "production")"
                let lastShown = UserDefaults.standard.object(forKey: key) as? Date
                guard AppOpenTiming.isDue(intervalMinutes: interval, lastShown: lastShown) else {
                    self.finishAppOpen(attempt: attempt, reason: "interval-not-due"); return
                }
                self.appOpenStage = "ad-preparation"
                let ad: AppOpenAd
                if demoMode, let preload = self.appOpenPreloadTask {
                    ad = try await preload.value
                } else {
                    // Production inventory still follows the real consent flow.
                    try await self.prepareSDK(demoMode: demoMode, mayPresentConsent: true,
                        mayContinue: { self.appOpenAttempt == attempt },
                        consentPresentation: { [weak self] presenting in
                            guard let self, self.appOpenAttempt == attempt else { return }
                            if presenting { self.appOpenDeadline?.cancel() }
                            else { self.scheduleAppOpenDeadline(attempt: attempt, seconds: waitingBudget) }
                        })
                    try Task.checkCancellation()
                    guard self.appOpenAttempt == attempt else { return }
                    ad = try await AppOpenAd.load(with: unitID, request: Request())
                }
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
                self.appOpenPreloadTask = nil
                self.appOpenStage = "presenting"
                self.appOpenLog.info("App-open ad ready; presenting")
                self.appOpenAd = ad
                self.appOpenHistoryKey = key
                ad.fullScreenContentDelegate = self
                self.appOpenDeadline?.cancel()
                self.isPreparingAppOpen = false
                self.isPresenting = true
                ad.present(from: nil)
            } catch {
                if self.appOpenAttempt == attempt {
                    let failure = error as NSError
                    self.appOpenLog.info("App-open preparation failed; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                }
                self.finishAppOpen(attempt: attempt, reason: "preparation-failed")
            }
        }
    }

    private func scheduleAppOpenDeadline(attempt: UUID, seconds: Double) {
        appOpenDeadline?.cancel()
        appOpenDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.appOpenAttempt == attempt, !self.isPresenting else { return }
            self.finishAppOpen(attempt: attempt, reason: "deadline")
        }
    }

    private func finishAppOpen(attempt: UUID? = nil, reason: String = "finished") {
        if let attempt, attempt != appOpenAttempt { return }
        appOpenLog.info("App-open ended; reason=\(reason, privacy: .public), stage=\(self.appOpenStage, privacy: .public)")
        appOpenStage = "idle"
        appOpenAttempt = nil
        appOpenPreloadTask?.cancel()
        appOpenPreloadTask = nil
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
        appOpenLog.info("App-open impression recorded")
    }

    func privacyOptions() async {
        do { try await ConsentForm.presentPrivacyOptionsForm(from: nil) }
        catch { self.error = error.localizedDescription }
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if let current = appOpenAd, ad === current { finishAppOpen(); return }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        isPresenting = false
        if rewardGranted { completedReward = UUID() }
        else if error == nil { message = "No reward was received. Finish the ad to receive your reward." }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if let current = appOpenAd, ad === current { finishAppOpen(); return }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        isPresenting = false
        self.error = error.localizedDescription
    }
}

struct LuckyRewardNotice: Identifiable {
    let id = UUID()
    let message: String
}
