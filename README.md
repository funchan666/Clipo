# Clipo

Native SwiftUI iPhone app for opening video links, browsing a vertical video feed and editing local videos. iOS 17+.

Open `Clipo.xcodeproj` and select the shared `Clipo` scheme. Backend: `https://devapi.io-d.cc`. Provisional Bundle ID: `com.clipo.video`.

Configuration lives in `Config/Clipo.xcconfig` and `Clipo/Resources/Commerce.json`. Set your signing team, registered product configuration, AdMob App ID and public policy URLs before release. Google Mobile Ads and UMP are declared as official Swift packages; dependencies have not been resolved in this task.

See `Documentation/IMPLEMENTATION.md` for feature scope, subscription/ad defaults, pending service configuration and validation limits. No build, test, simulator run or live business API request has been performed.
