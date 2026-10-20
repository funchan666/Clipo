# Account access and policy integration

## Behavior

- Both supplied Google Sites URLs are configured in `Config/Clipo.xcconfig`; the empty expansion inside `https:/$()/` preserves the slashes instead of starting an xcconfig comment.
- Every manual guest-login entry uses `LoginControls`. Agreement starts unchecked. Tapping sign-in before agreement opens a custom prompt without signing in or automatically checking the box. The two documents remain independently accessible.
- Documents open in an embedded WKWebView with ephemeral website data, a close button, loading state and error/retry UI. HTTPS links stay in the reader; user-activated email links open the system mail handler. No app credentials or script bridge are passed to the page.
- Login uses shared account-operation state to block repeat submissions and background interaction. Loading reflects the real async request; failure keeps the login form and agreement state.
- Me directly presents sign-out, a simulated Delete account action, legal documents, advertising privacy choices where applicable, and the Apple subscription-management link. There is no separate Settings sheet or navigation step.
- Exit actions ask for confirmation, then show a brief 300 ms local loading transition before performing the Keychain mutation. Success clears local navigation and returns to the welcome screen. Errors stay on Me with a message. The root account-operation overlay provides loading and blocks interaction; the inline section does not dismiss its parent.
- Sign-out removes the cached session while preserving the installation login identity. The next login can recover the same guest according to the existing backend contract.
- **Deletion is explicitly a local simulation.** It removes both the cached session and installation login identity. It makes no server deletion call and leaves local media, bookmarks and purchase recovery records intact. The confirmation explains these limits. The next login requests a new guest identity; backend results remain authoritative.
- Reset restores the previous installation value if session removal fails. It never clears the immutable purchase ledger or reassigns pending purchases to the next guest.

## Artwork and layout

The Me refresh replaces the tall membership advertisement with a compact horizontal original-art card. Account identity and membership status sit above it; actual views/saves balances appear as two typographic columns. Unlimited daily viewing does not incorrectly imply unlimited saves. Privacy/subscription and account actions are grouped directly below. No avatar, new app logo, system icons or additional top-level page title was introduced. Existing original Plus artwork and the raster back glyph are reused; the latter is rotated for disclosure rows.

Account controls are disabled during account operations, purchase preparation/processing and advertising presentation. Privacy documents still use the existing WKWebView. Sign-out preserves installation identity; simulated deletion keeps its explicit scope and original confirmation. Native scrolling, wrapping rows, bounded content width and ViewThatFits keep the layout container-driven without changing session ownership.

The 2026-10-20 welcome refresh removes the feature checklist, guest-account caption and pre-login local-editor entry. It uses one original `ClipoArtWelcome` illustration, the short “Your next favorite.” headline, and the one-tap sign-in action. The unchecked consent control and document links now sit below the sign-in button. Editing remains available in Tools after sign-in.

`ClipoArtWelcome` was generated through the built-in Host-Native image workflow; its transparent PNG is included in the asset catalog. Prompt: `ProjectMaterials/UIAssets/Prompts/Welcome/WelcomeHero.txt`. The artwork is decorative and excluded from VoiceOver. Welcome layout uses the current container height, a bounded reading width, scalable text and scrolling; resizing does not reset consent or trigger login. No logo, app name or feature cards were added.

`ClipoConsentStates` is an original transparent two-state checkbox atlas generated with the built-in image tool. Source prompt: `ProjectMaterials/UIAssets/Prompts/Consent/consent-states.txt`. SwiftUI crops the atlas for display; it does not draw the checkmark. The loading treatment reuses the original `ClipoLoadingMark` raster with opacity animation and Reduce Motion support.

Dialogs use their current container, a readable maximum width, scrolling for long text and safe-area-aware layout. Reading documents, consent state and account-operation state do not depend on device dimensions. No new Duo-specific SDK APIs or geometry-driven view identities were added.

## Verification and remaining work

The initial account-access delivery used static source/diff review, Xcode project/plist parsing, asset metadata/reference checks and public URL HTTP/title checks. Later sign-in/sign-out runtime results are documented in `RUNTIME-AUDIT-2026-10-20.md`.

The subsequent welcome-only redesign was checked at source and asset level, including PNG transparency and asset-catalog references. The generated illustration was visually inspected. This new layout has not been compiled or rendered in a simulator/device; earlier runtime results do not validate the changed layout, Dynamic Type or Duo postures.

The subsequent Me/settings consolidation was reviewed through source/diff and resource references only. No compilation, simulator/device launch, sign-out or deletion was performed for this revision. Earlier account-operation runtime evidence predates this inline presentation.

Before replacing the simulation, obtain and implement the backend account-deletion method, parameters and response contract. Preserve purchase-owner recovery and define server/local retention behavior explicitly.
