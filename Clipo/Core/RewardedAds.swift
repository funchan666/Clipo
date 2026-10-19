import Foundation
import Combine
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class RewardedAds: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var busy = false
    @Published private(set) var isPresenting = false
    @Published private(set) var privacyOptionsRequired = false
    @Published var error: String?
    @Published var message: String?
    private var rewarded: RewardedAd?
    private var rewardGranted = false
    private var started = false
    private static let demoAppID = "ca-app-pub-3940256099942544~1458002511"
    private static let demoRewardedUnitID = "ca-app-pub-3940256099942544/1712485313"

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
        do {
            if !demoMode {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                }
                privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                try await ConsentForm.loadAndPresentIfRequired(from: nil)
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
            let ad = try await RewardedAd.load(with: unitID, request: Request())
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
        } catch { self.error = "An ad could not be loaded. Please try again later. \(error.localizedDescription)"; isPresenting = false }
        busy = false
    }
    func privacyOptions() async {
        do { try await ConsentForm.presentPrivacyOptionsForm(from: nil) }
        catch { self.error = error.localizedDescription }
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        rewarded = nil
        isPresenting = false
        if !rewardGranted, error == nil { message = "No reward was received. Finish a rewarded ad to get more views." }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        rewarded = nil
        isPresenting = false
        self.error = error.localizedDescription
    }
}
