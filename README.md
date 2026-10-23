# Clipo

Native SwiftUI iPhone application for tennis lesson links, video playback, local practice review, tennis field notes and manual serve tracking. Requires iOS 17 or later. Open Clipo.xcodeproj and select the Clipo scheme.

Configuration is in Config/Clipo.xcconfig. The target currently retains the existing testing Bundle ID im.seex.lobo; production service requests use com.cliporows.toolskeep. The API host is b8pd8t.clipo.vip. Change signing and registered products together before submitting a different Bundle ID.

Purchases use Apple StoreKit products and receipts, followed by server order confirmation. There is no local StoreKit configuration attached to the shared scheme. Prices and billing periods shown to customers come from Apple. Commerce.json requests clipo.plus.monthly and clipo.plus.yearly while preserving the server contract values; the temporary test product configuration was removed at the user's request on 2026-10-23. Historical purchase records retain their original product IDs and ownership.

Codemagic uses the `clipo-ios-app-store` workflow, the `Clipo` App Store Connect integration, Xcode 26.5, `Clipo.xcodeproj`, and the shared `Clipo` scheme. The App Store app ID is `6825652572` and the Bundle ID is `com.cliporows.toolskeep`. Configure matching App Store distribution certificates and profiles in Codemagic. The workflow increments the build number, checks the exported IPA identity, and uploads through `auth: integration`; review submission remains manual. CI signing and upload have not been verified locally.

Documentation/AppStoreMetadata.md contains the current store copy and review access instructions. Documentation/CONFIRMATIONS.md records current decisions and unresolved release dependencies. Documentation/ResourceOptimization.json records lossless image checks. Font licenses are retained in Resources/Fonts.

Historical design drafts, source artwork, recordings and legal drafts have been moved outside the project. They are not build inputs. Build and runtime checks require explicit task authorization.
