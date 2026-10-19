# Clipo

Native SwiftUI iPhone app for opening video links, browsing a vertical video feed and editing local videos. iOS 17+.

Open `Clipo.xcodeproj` and select the shared `Clipo` scheme. Backend: `https://devapi.io-d.cc`. Provisional Bundle ID: `com.clipo.video`.

Configuration lives in `Config/Clipo.xcconfig` and `Clipo/Resources/Commerce.json`. Set your signing team, registered product configuration, AdMob App ID and public policy URLs before release. Google Mobile Ads and UMP are declared as official Swift packages; dependencies are resolved in the checked-in workspace lockfile.

Google's official iOS demo App ID and rewarded ad unit are enabled with `CLIPO_ADS_TEST_MODE = YES`. Sign in and open Clipo Plus → Watch ad for more views to try the SDK reward flow. Before publishing, set this flag to `NO` and configure your production App ID and backend ad unit. Demo mode does not exercise the production UMP consent flow.

See `Documentation/IMPLEMENTATION.md` for feature scope, subscription/ad defaults, pending service configuration and validation limits. On 2026-10-19, the Debug configuration built successfully with Xcode 27.1 for generic iOS arm64, with code signing disabled. No tests, simulator/app launch or live business API checks were performed. This is not an archive or signing verification.

Launch now uses a centered original Clipo icon and a static loading mark; the matching in-app splash gently pulses before showing the existing one-tap sign-in page. This subsequent splash UI change has been checked statically only and is not covered by the earlier successful build. See the startup section in `Documentation/IMPLEMENTATION.md`.

The subsequent visual refresh unifies the welcome, home, Studio, Library and Plus pages with charcoal surfaces, pale link/benefit panels and a compact original-icon navigation bar. Source, asset references and color contrast were inspected; this refresh has not been compiled or rendered in a simulator/device.

TabBar now uses eight newly generated original PNGs under `Clipo/Resources/Assets.xcassets/TabBar`, including baked-in selected backgrounds. Prompts and source provenance are in `ProjectMaterials/UIAssets/Prompts/TabBar`. Tab artwork no longer uses atlas cropping or code-drawn selection decorations; full-cell hit regions remain native. Runtime tapping has not been verified.
