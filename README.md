# Clipo

Native SwiftUI iPhone app for shared tennis lessons and local practice-video review, iOS 17+. Open `Clipo.xcodeproj` and select the `Clipo` scheme.

- [Quick app demonstration](Documentation/Demo/Clipo-quick-tour.mp4) — about 2 minutes, edited from a real simulator recording; no audio.
- [API questions and decisions to confirm](Documentation/CONFIRMATIONS.md) — consolidated current handoff.
- [Supplied API reference](Documentation/API-reference.md).
- English policy drafts remain in `Documentation/Legal/`.

Backend: `https://devapi.io-jp.com`. Target Bundle ID: `com.cliporows.toolskeep` (the target overrides the older xcconfig fallback).
Configuration: `Config/Clipo.xcconfig` and `Clipo/Resources/Commerce.json`.

Monthly product: `coins_1.99`, USD reference price 9.99.
Yearly product: `conis_4.99`, USD reference price 99.99.
Google official test ads are enabled. Apple registration, production ad configuration and unresolved backend contracts are listed in the handoff.

The latest short demonstration covers startup, authorized consent and login, short-code playback, the five tabs, local editing preview, library, account/policy, membership and a rewarded test ad. It is not a full acceptance test or a completed purchase test. No source changes or new build were made for this recording. Old test recordings and incremental reports were removed at the user's request; app source, test code, artwork and policy files were preserved.

Confirmed API mapping: `unlimitedAfterAdCount` is the daily base download allowance; `favoriteBaseLimit` is the per-download-ad reward. Favorites are free. Rewarded ad type is `5`. Backend `usdPrice` values `999` / `9999` are fixed USD plan values and are sent unchanged. These contract changes received static review only; the existing demo predates them.

Startup now authenticates a real guest automatically and opens the app without a welcome/login gate. Connection failures offer retry and policy links. Sign-out and simulated account deletion controls have been removed at the user’s request; genuine server deletion remains a release requirement to resolve. Existing purchase ownership and recovery records are preserved.

The tennis redesign uses original `ClipoTennisCourt` and `ClipoTennisKit` raster assets, generated specifically for this project. Prompts are in `ProjectMaterials/UIAssets/Prompts/Tennis/`. The App Icon and launch mark are unchanged pending client artwork. Illustrations are decorative; lesson data still comes from the existing API, with no fabricated feed items. The client confirmed the currently empty recommendation feed is expected until videos are configured.

Tennis field notes are available from Home and the practice-tools tab. Five bundled articles, available in all seven app languages, cover the forehand, backhand, serve, scoring and four majors, with category filtering and a native reading view. Summaries were checked against the linked USTA and ITF sources on 2026-10-20. Reading uses no video quota or backend requests; only opening a source loads a website. The feature reuses original tennis artwork. Source navigation, device layout and offline behavior have received static inspection only, not runtime verification.

App-open ads use server `displayInterval` in minutes on cold start and background return, with persisted impression timing; zero means no interval restriction. Official test IDs remain enabled. The supplemental example also contains `adOrder`, `showIntervalRows`, and `maxHourlyImps`; these unspecified fields remain ignored and are not blockers for the requested ad flows.

The theme and automatic-entry changes received static inspection only: no build, tests, simulator run, live login, ad, or purchase verification this turn. The linked demo predates these changes. See the handoff for confirmed business rules still awaiting implementation, including backend restore reconciliation and production configuration. Independent download quotas and UTC resets are now implemented in source, with no runtime verification.

Language switching is available in Me → App language: English (default), Korean, Japanese, Indonesian, Portuguese, Arabic and Spanish. Selection is persisted independently of device language and updates owned UI and bundled field notes without resetting session or media stores. Arabic uses RTL layout with directional navigation arrows; artwork, URLs and the playback timeline retain their original orientation. USD reference prices remain USD. Remote/user content, external policy pages and OS-controlled sheets retain their source/system language. The seven catalogs contain 410 matching entries each. Localization resources, placeholders and project references were inspected statically; no build, simulator or multilingual runtime verification was performed.

The illustrated UI refresh replaces the tools landing page and field-notes index with compact image-led navigation. Nine original editorial illustrations and four bitmap control surfaces live in `ClipoCourtEditorial` and `ClipoCourtControls`. Shared action buttons, choice controls, the Home open-link action and membership plan selection now display the original control art; native text stays localized and scalable. Full educational articles and existing functional routes remain available. Prompts are in `ProjectMaterials/UIAssets/Prompts/CourtEditorial/`. Artwork was visually inspected; resource references, catalog parity and source changes were checked statically. The updated native screens have not been built or run.


Confirmed allowance changes now separate free favorites, online viewing and offline downloads. Each allowance has its own four-ad progression; no-fill gifts do not advance it and only appear after the matching allowance is exhausted. The ledger resets at 05:00 UTC, preserves same-day watch identity and remembers successfully downloaded IDs across days. Playback options include offline download; Library → Downloads plays the persisted local media. HLS assets remain at their system-provided location, while ordinary files are stored in Application Support. Download journals make quota/index completion retryable. These paths have received static inspection only.

Clean reinstall now resets the guest session/UUID while preserving historical payment ownership records. Failed and cancelled StoreKit transactions are durably queued for backend status reporting using real available fields; refresh/relaunch retries pending reports. Existing upgrades keep their installation identity. The standalone quota contract checks were updated, but neither they nor builds, media downloads, ads or payments were run for this change.
