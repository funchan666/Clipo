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
    private var preloadUnitID: String?
    private var preloadRequestID: UUID?
    private var preparedAppOpen: AppOpenAd?
    private var preparedAppOpenDate: Date?
    private var preparedUnitID: String?
    private var presentedUnitID: String?
    private let appOpenLog = Logger(subsystem: "com.clipo.video", category: "AppOpen")
    private var appOpenStage = "idle"
    private var appOpenDeadline: Task<Void, Never>?
    private var appOpenAttempt: UUID?
    private var appOpenHistoryKey: String?
    private var returnedFromBackground = false
    private var appOpenConsentPresented = false
    private var appOpenAd: AppOpenAd?
    private var rewarded: RewardedAd?
    private var unavailableReward: (() -> Void)?
    private var rewardGranted = false
    private var rewardAttempt: UUID?
    @Published private(set) var completedReward: UUID?
    private var started = false
    func watch(commerce: CommerceStore, quota: QuotaStore, kind: AllowanceKind) async {
        guard !Task.isCancelled, !busy, !isPresenting, !isPreparingAppOpen else { return }
        quota.resetIfNeeded()
        guard quota.canRequestReward(for: kind, premium: commerce.premium) else { return }
        guard commerce.rightsVerified, let policy = commerce.policy, let owner = commerce.api.session?.userId.value else {
            error = "Rewarded ads are not available right now. No views have been deducted."; return
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
        unavailableReward = nil
        let packagedAppID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        guard let placement = commerce.release?.googlePlacement(for: policy.rewardedAdType, packagedAppID: packagedAppID) else {
            appOpenLog.error("Rewarded ad configuration missing, invalid or inconsistent with the packaged App ID")
            grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            return
        }
        let unitID = placement.unitID
        let demoMode = placement.isOfficialDemo
        var timeout: Task<Void, Never>?
        func armDeadline() {
            timeout?.cancel()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self, self.rewardAttempt == attemptID, !self.isPresenting else { return }
                self.rewardAttempt = nil
                self.busy = false
                self.grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
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
            let ad = try await RewardedAd.load(with: unitID, request: Request())
            try Task.checkCancellation()
            guard rewardAttempt == attemptID, UIApplication.shared.applicationState == .active else { return }
            try ad.canPresent(from: nil)
            guard commerce.api.session?.userId.value == owner, !commerce.premium else { throw ClipoError.unauthorized }
            rewarded = ad
            unavailableReward = { [weak self] in
                self?.grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
            }
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
            // Preparation, consent configuration and load failures all mean no ad.
            // Explicit cancellation never earns a gift or bypasses consent.
            if Task.isCancelled || error is CancellationError ||
                (failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled) { return }
            appOpenLog.error("Rewarded ad unavailable; domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            grantUnavailableReward(attemptID, owner: owner, commerce: commerce, quota: quota, kind: kind)
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
                error = nil
                message = nil
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
            if mayPresentConsent, ConsentInformation.shared.consentStatus == .required {
                let form = try await ConsentForm.load()
                try Task.checkCancellation()
                guard mayContinue() else { throw CancellationError() }
                consentPresentation?(true)
                defer { consentPresentation?(false) }
                try await form.present(from: nil)
            }
            guard ConsentInformation.shared.canRequestAds else { throw ClipoError.service("Ads are unavailable with your current privacy choices.") }
        } else {
            // Google's demo app has no Clipo-owned UMP message configuration.
            // This branch is restricted to the exact official demo App ID and ad unit returned by getV2.
            privacyOptionsRequired = false
        }
        try Task.checkCancellation()
        guard mayContinue() else { throw CancellationError() }
        startSDKIfNeeded()
    }

    private func startSDKIfNeeded() {
        guard !started else { return }
        started = true
        // Google-only integration: start once, then request ads immediately, as
        // in Google's quick start. Adapter completion must not block the app.
        MobileAds.shared.start { [weak self] _ in
            self?.appOpenLog.info("Google Mobile Ads initialization callback received")
        }
    }

    private func preloadAppOpen(unitID: String) async throws -> AppOpenAd {
        if preparedUnitID == unitID, let ad = preparedAppOpen, let date = preparedAppOpenDate,
           Date().timeIntervalSince(date) >= 0, Date().timeIntervalSince(date) < 4 * 60 * 60 {
            appOpenLog.info("Using preloaded app-open ad")
            return ad
        }
        if let task = appOpenPreloadTask, preloadUnitID == unitID { return try await task.value }
        appOpenPreloadTask?.cancel()
        preparedAppOpen = nil
        preparedAppOpenDate = nil
        preparedUnitID = nil
        preloadUnitID = unitID
        let requestID = UUID()
        preloadRequestID = requestID
        // This task belongs to the inventory cache, not a splash-screen deadline.
        let task = Task { @MainActor [weak self] () throws -> AppOpenAd in
            let began = ContinuousClock.now
            do {
                let ad = try await AppOpenAd.load(with: unitID, request: Request())
                try Task.checkCancellation()
                guard let self, self.preloadRequestID == requestID else { throw CancellationError() }
                self.preparedAppOpen = ad
                self.preparedAppOpenDate = Date()
                self.preparedUnitID = unitID
                self.appOpenPreloadTask = nil
                self.preloadUnitID = nil
                self.preloadRequestID = nil
                self.appOpenLog.info("App-open inventory ready after \(began.duration(to: .now).description, privacy: .public)")
                return ad
            } catch {
                if let self, self.preloadRequestID == requestID {
                    self.appOpenPreloadTask = nil
                    self.preloadUnitID = nil
                    self.preloadRequestID = nil
                    let failure = error as NSError
                    self.appOpenLog.error("App-open inventory failed; domain=\(failure.domain, privacy: .public), code=\(failure.code), message=\(failure.localizedDescription, privacy: .public)")
                }
                throw error
            }
        }
        appOpenPreloadTask = task
        return try await task.value
    }

    // Cold start includes pre-login guest preparation. Foreground returns use the same gate.
    func beginStartup(commerce: CommerceStore, accountAccess: AccountAccessFlow) {
        guard !startupStarted else { return }
        startupStarted = true
        requestAppOpen(commerce: commerce, accountAccess: accountAccess, coldStart: true)
    }

    func didEnterBackground() {
        // An ad or SDK consent browser returning to the app must not recursively trigger an ad.
        returnedFromBackground = !isPresenting && !busy && !appOpenConsentPresented
        if isPreparingAppOpen, !appOpenConsentPresented { finishAppOpen(reason: "background", preservePreparation: true) }
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
        // Bound only this presentation opportunity. A slow network must not keep
        // the home screen locked or discard inventory for the next foreground.
        let waitingBudget = coldStart ? 2.0 : 1.0
        appOpenStage = "authentication"
        appOpenLog.info("App-open opportunity started; coldStart=\(coldStart), budget=\(waitingBudget)")
        scheduleAppOpenDeadline(attempt: attempt, seconds: waitingBudget)
        appOpenTask = Task { [weak self] in
            guard let self else { return }
            let packagedAppID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
            do {
                try await commerce.api.prepareVisitor()
                try Task.checkCancellation()
                guard let owner = commerce.api.session?.userId.value else {
                    self.finishAppOpen(attempt: attempt); return
                }
                if self.appOpenAttempt == attempt { self.appOpenStage = "rights-and-configuration" }
                self.appOpenLog.info("App-open guest authentication ready")
                await commerce.refresh()
                try Task.checkCancellation()
                guard commerce.api.session?.userId.value == owner,
                      commerce.rightsVerified, !commerce.premium else {
                    self.finishAppOpen(attempt: attempt, reason: commerce.premium ? "membership" : "rights-unavailable"); return
                }
                let unit = commerce.release?.adList?.first {
                    $0.adType == 1 && $0.advertiser?.lowercased() == "google"
                }
                guard let placement = commerce.release?.googlePlacement(for: 1, packagedAppID: packagedAppID) else {
                    self.appOpenLog.error("App-open configuration missing, invalid or inconsistent with the packaged App ID")
                    self.finishAppOpen(attempt: attempt, reason: "ad-configuration-unavailable"); return
                }
                let interval = unit?.displayInterval
                let unitID = placement.unitID
                let key = "app-open.last-impression.\(commerce.api.configuration.servicePackageName).\(commerce.api.configuration.apiBaseURL?.host ?? "none").\(placement.isOfficialDemo ? "demo" : "production")"
                self.appOpenLog.info("App-open rights/configuration ready; intervalMinutes=\(interval ?? -1)")
                if self.appOpenAttempt == attempt { self.appOpenStage = "ad-preparation" }
                // Late inventory may be retained, but consent/presentation may not interrupt Home.
                let mayPresentConsent = self.appOpenAttempt == attempt
                try await self.prepareSDK(demoMode: placement.isOfficialDemo,
                    mayPresentConsent: mayPresentConsent,
                    mayContinue: { !mayPresentConsent || self.appOpenAttempt == attempt },
                    consentPresentation: { [weak self] presenting in
                        guard let self, self.appOpenAttempt == attempt else { return }
                        self.appOpenConsentPresented = presenting
                        if presenting { self.appOpenDeadline?.cancel() }
                        else { self.scheduleAppOpenDeadline(attempt: attempt, seconds: waitingBudget) }
                    })
                guard AppOpenTiming.isDue(intervalMinutes: interval,
                    lastShown: UserDefaults.standard.object(forKey: key) as? Date) else {
                    Task { try? await self.preloadAppOpen(unitID: unitID) }
                    self.finishAppOpen(attempt: attempt, reason: "interval-not-due")
                    return
                }
                let ad = try await self.preloadAppOpen(unitID: unitID)
                try Task.checkCancellation()
                guard self.appOpenAttempt == attempt, commerce.api.session?.userId.value == owner,
                      !commerce.premium, UIApplication.shared.applicationState == .active,
                      !self.busy, !self.isPresenting, !commerce.busy, !commerce.preparingPurchase,
                      !accountAccess.isBusy,
                      AppOpenTiming.isDue(intervalMinutes: interval,
                        lastShown: UserDefaults.standard.object(forKey: key) as? Date) else {
                    self.finishAppOpen(attempt: attempt); return
                }
                do { try ad.canPresent(from: nil) }
                catch {
                    self.preparedAppOpen = nil
                    self.preparedAppOpenDate = nil
                    self.preparedUnitID = nil
                    throw error
                }
                self.preparedAppOpen = nil
                self.preparedAppOpenDate = nil
                self.preparedUnitID = nil
                self.presentedUnitID = unitID
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
            self.finishAppOpen(attempt: attempt, reason: "deadline", preservePreparation: true)
        }
    }

    private func finishAppOpen(attempt: UUID? = nil, reason: String = "finished", preservePreparation: Bool = false) {
        if let attempt, attempt != appOpenAttempt { return }
        appOpenLog.info("App-open ended; reason=\(reason, privacy: .public), stage=\(self.appOpenStage, privacy: .public)")
        appOpenStage = "idle"
        appOpenAttempt = nil
        appOpenDeadline?.cancel()
        appOpenDeadline = nil
        if !preservePreparation { appOpenTask?.cancel() }
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
        if let current = appOpenAd, ad === current {
            let unitID = presentedUnitID
            presentedUnitID = nil
            finishAppOpen()
            if let unitID { Task { try? await self.preloadAppOpen(unitID: unitID) } }
            return
        }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        unavailableReward = nil
        isPresenting = false
        if rewardGranted { completedReward = UUID() }
        else if error == nil { message = "No reward was received. Finish the ad to receive your reward." }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if let current = appOpenAd, ad === current { finishAppOpen(); return }
        guard let current = rewarded, ad === current else { return }
        rewarded = nil
        isPresenting = false
        let fallback = unavailableReward
        unavailableReward = nil
        if !rewardGranted { fallback?() }
    }
}

struct LuckyRewardNotice: Identifiable {
    let id = UUID()
    let message: String
}
