# Clipo

Native SwiftUI iPhone app, iOS 17+. Open `Clipo.xcodeproj` and select the `Clipo` scheme.

- [Quick app demonstration](Documentation/Demo/Clipo-quick-tour.mp4) — about 2 minutes, edited from a real simulator recording; no audio.
- [API questions and decisions to confirm](Documentation/CONFIRMATIONS.md) — consolidated current handoff.
- [Supplied API reference](Documentation/API-reference.md).
- English policy drafts remain in `Documentation/Legal/`.

Backend: `https://devapi.io-jp.com`. Provisional Bundle ID: `com.clipo.video`.
Configuration: `Config/Clipo.xcconfig` and `Clipo/Resources/Commerce.json`.

Monthly product: `ypsmwxmscbzeixig`, USD reference price 9.99.
Yearly product: `xfpkaphmqxhtgzvx`, USD reference price 99.99.
Google official test ads are enabled. Apple registration, production ad configuration and unresolved backend contracts are listed in the handoff.

The latest short demonstration covers startup, authorized consent and login, short-code playback, the five tabs, local editing preview, library, account/policy, membership and a rewarded test ad. It is not a full acceptance test or a completed purchase test. No source changes or new build were made for this recording. Old test recordings and incremental reports were removed at the user's request; app source, test code, artwork and policy files were preserved.

Confirmed API mapping: `unlimitedAfterAdCount` is the daily base favorite allowance; `favoriteBaseLimit` is the per-ad favorite reward. Rewarded ad type is `5`. Backend `usdPrice` values `999` / `9999` are fixed USD plan values and are sent unchanged. These contract changes received static review only; the existing demo predates them.

Startup now prepares a guest session for package/ad configuration while preserving the explicit welcome consent/entry step. App-open ads use server `displayInterval` in minutes on cold start and background return, with persisted impression timing. Official test IDs remain enabled. These changes received static inspection only; the demo predates them. See the handoff for other confirmed rules still awaiting implementation.
