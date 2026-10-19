# Tools tab

The third destination is now Tools. Home handles links, Discover handles the video feed, Tools handles local media changes, Library holds saved/imported/exported items, and Me handles the account and membership.

Tools offers three focused workflows: Extract audio (M4A), Change speed and Reframe video. Each opens the existing native import workspace with the corresponding control selected. Quick workflows show only their relevant controls; the audio workflow's main export action produces audio. Full editor remains available as a separate action with all editing controls.

Library's Edit action presents the editor with the selected local movie and returns to Library when dismissed. The welcome screen's local entry opens Tools without requiring login. Existing AVFoundation export and library persistence services are reused. No channel feed, new backend service, subscription or reward logic is introduced by this change.

Original image assets were generated with the host-native image tool and copied unchanged:

- `Clipo/Resources/Assets.xcassets/TabBar/TabToolsNormal.imageset/TabToolsNormal.png`
- `Clipo/Resources/Assets.xcassets/TabBar/TabToolsSelected.imageset/TabToolsSelected.png`
- `Clipo/Resources/Assets.xcassets/Illustrations/ClipoArtTools.imageset/ClipoArtTools.png`

Prompts and source manifest: `ProjectMaterials/UIAssets/Prompts/Tools/`.

The page uses the existing container-limited scrolling column and bottom safe-area navigation. The original raster images do not intercept taps; tool actions have explicit hit areas and accessible identifiers. No container-size-based view identity or new device-specific API is used.

Validation is limited to source routing, resource references, PNG alpha/original-copy checks and git diff inspection. No build, tests, simulator, actual media conversion or Duo display transition was run for this change.
