# Me tab — 2026-10-19

The account page is now the fifth top-level destination: Home, Discover, Studio, Library, Me. Home's account/settings shortcut selects the same Me tab instead of presenting a duplicate sheet. Successful sign-out clears the local-workspace route and editor selection and returns to the welcome screen.

Me contains the existing guest identity, membership entry/status, daily allowance, rewards entry, sign-out confirmation, advertising privacy choices when required, policy links and version. The membership panel reuses ClipoArtPlus. Existing payment, ad reward and session services are unchanged.

Two original PNG assets were created with the host-native image tool using the Library tab assets as visual references:

- `Clipo/Resources/Assets.xcassets/TabBar/TabMeNormal.imageset/TabMeNormal.png`
- `Clipo/Resources/Assets.xcassets/TabBar/TabMeSelected.imageset/TabMeSelected.png`

Prompts: `TabMeNormal.txt`, `TabMeSelected.txt`. Source paths: `me-manifest.json`. Both generated files were copied without image processing.

The native tab cells remain equal-width with 68pt height and explicit rectangular hit areas. Images fit the proposed cell width up to 64pt, avoiding a fixed 64pt minimum when five tabs share a narrow container. Images are excluded from hit testing; accessible names, selected traits and identifiers remain attached to the actual buttons. The bar stays inside the existing bottom safe-area inset. Container resizing does not change route identity.

Static checks: all ten tab image catalog entries resolve, both new PNGs contain alpha and match their generated originals, the five enum cases map to five routes, old settings-sheet bindings are removed, and git diff whitespace checks pass. No compilation, tests, simulator/device interaction, native screenshot review or folded-display verification was performed.
