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
    private var startupDeadline: Task<Void, Never>?
    private var appOpenAd: AppOpenAd?
    private var rewarded: RewardedAd?
    private var rewardGranted = false
    private var started = false
    private static let demoAppID = "ca-app-pub-3940256099942544~1458002511"
    private static let demoRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"

    private static let demoAppOpenUnitID = "ca-app-pub-3940256099942544/5575463023"

    func watch(commerce: CommerceStore, quota: QuotaStore) async {
        guard !busy, !isPresenting else { return }
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

    // One opportunity per cold launch, only while the original loading screen is visible.
    func beginStartup(commerce: CommerceStore) {
        guard !startupStarted else { return }
        startupStarted = true
        guard let owner = commerce.api.session?.userId.value else { finishStartup(); return }
        startupDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)); self?.finishStartup() }
            catch { }
        }
        Task { [weak self] in
            guard let self else { return }
            let demoMode = (Bundle.main.object(forInfoDictionaryKey: "ClipoAdsTestMode") as? String) == "YES"
            // Official demo ads do not depend on a registered backend package.
            // Production ads must first obtain the real configuration and account rights.
            if !demoMode { await commerce.refresh() }
            guard !self.startupFinished else { return }
            guard commerce.api.session?.userId.value == owner, !commerce.premium else { self.finishStartup(); return }
            guard demoMode || commerce.rightsVerified else { self.finishStartup(); return }
            let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
            let unitID: String
            if demoMode, appID == Self.demoAppID { unitID = Self.demoAppOpenUnitID }
            else if !demoMode, let appID, appID != Self.demoAppID,
                    let unit = commerce.release?.adList?.first(where: { $0.adType == 1 && $0.advertiser?.lowercased() == "google" }),
                    unit.config.appId == appID, let configured = unit.config.adUnitId?.nilIfBlank {
                unitID = configured
            } else { self.finishStartup(); return }
            do {
                try await self.prepareSDK(demoMode: demoMode, mayPresentConsent: false)
                guard !self.startupFinished else { return }
                let ad = try await AppOpenAd.load(with: unitID, request: Request())
                guard !self.startupFinished else { return }
                guard commerce.api.session?.userId.value == owner, !commerce.premium,
                      UIApplication.shared.applicationState == .active,
                      !self.busy, !self.isPresenting else { self.finishStartup(); return }
                try ad.canPresent(from: nil)
                self.appOpenAd = ad
                ad.fullScreenContentDelegate = self
                self.startupDeadline?.cancel()
                self.isPresenting = true
                ad.present(from: nil)
            } catch { self.finishStartup() }
        }
    }

    private func finishStartup() {
        guard !startupFinished else { return }
        startupDeadline?.cancel()
        startupDeadline = nil
        appOpenAd = nil
        isPresenting = false
        startupFinished = true
    }

    func privacyOptions() async {
        do { try await ConsentForm.presentPrivacyOptionsForm(from: nil) }
        catch { self.error = error.localizedDescription }
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if ad is AppOpenAd { finishStartup(); return }
        rewarded = nil
        isPresenting = false
        if !rewardGranted, error == nil { message = "No reward was received. Finish a rewarded ad to get more views." }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if ad is AppOpenAd { finishStartup(); return }
        rewarded = nil
        isPresenting = false
        self.error = error.localizedDescription
    }
}

struct LuckyRewardNotice: Identifiable {
    let id = UUID()
    let message: String
}
