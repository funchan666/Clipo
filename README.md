# Clipo

Native SwiftUI iPhone app for shared tennis lessons and local practice-video review, iOS 17+. Open `Clipo.xcodeproj` and select the `Clipo` scheme.

- [Quick app demonstration](Documentation/Demo/Clipo-quick-tour.mp4) — about 2 minutes, edited from a real simulator recording; no audio.
- [API questions and decisions to confirm](Documentation/CONFIRMATIONS.md) — consolidated current handoff.
- [Supplied API reference](Documentation/API-reference.md).
- English policy drafts remain in `Documentation/Legal/`.

Backend: `https://devapi.io-jp.com`. Target Bundle ID: `com.cliporows.toolskeep` (the target overrides the older xcconfig fallback).
Configuration: `Config/Clipo.xcconfig` and `Clipo/Resources/Commerce.json`.

Monthly product: `ypsmwxmscbzeixig`, USD reference price 9.99.
Yearly product: `xfpkaphmqxhtgzvx`, USD reference price 99.99.
Google official test ads are enabled. Apple registration, production ad configuration and unresolved backend contracts are listed in the handoff.

The latest short demonstration covers startup, authorized consent and login, short-code playback, the five tabs, local editing preview, library, account/policy, membership and a rewarded test ad. It is not a full acceptance test or a completed purchase test. No source changes or new build were made for this recording. Old test recordings and incremental reports were removed at the user's request; app source, test code, artwork and policy files were preserved.

Confirmed API mapping: `unlimitedAfterAdCount` is the daily base favorite allowance; `favoriteBaseLimit` is the per-ad favorite reward. Rewarded ad type is `5`. Backend `usdPrice` values `999` / `9999` are fixed USD plan values and are sent unchanged. These contract changes received static review only; the existing demo predates them.

Startup now authenticates a real guest automatically and opens the app without a welcome/login gate. Connection failures offer retry and policy links. Sign-out and simulated account deletion controls have been removed at the user’s request; genuine server deletion remains a release requirement to resolve. Existing purchase ownership and recovery records are preserved.

The tennis redesign uses original `ClipoTennisCourt` and `ClipoTennisKit` raster assets, generated specifically for this project. Prompts are in `ProjectMaterials/UIAssets/Prompts/Tennis/`. The App Icon and launch mark are unchanged pending client artwork. Illustrations are decorative; lesson data still comes from the existing API, with no fabricated feed items. The client confirmed the currently empty recommendation feed is expected until videos are configured.

App-open ads use server `displayInterval` in minutes on cold start and background return, with persisted impression timing; zero means no interval restriction. Official test IDs remain enabled. The supplemental example also contains `adOrder`, `showIntervalRows`, and `maxHourlyImps`; these unspecified fields remain ignored and are not blockers for the requested ad flows.

The theme and automatic-entry changes received static inspection only: no build, tests, simulator run, live login, ad, or purchase verification this turn. The linked demo predates these changes. See the handoff for confirmed business rules still awaiting implementation, including independent offline-cache quotas and UTC resets.
