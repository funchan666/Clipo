# Player artwork

Created using the built-in Host-Native image tool for the 2026-10-20 player refresh.

- `PlayerActions.txt`: initial four-glyph atlas prompt. The transparent draft had speckled edges and was not shipped. A second image-tool edit retained all four glyphs, removed noise, reduced the bookmarks, and rendered crisp white artwork on solid black. The final 1254×1254 PNG is `ClipoPlayerActions`; SwiftUI displays measured optical crop regions with screen blending. No icon contours were drawn in code.
- `PlayerScrim.txt`: smooth transparent-to-black readability overlay. The generated 1254×1254 RGBA asset is `ClipoPlayerScrim`. Center-column alpha samples at 0%, 25%, 50%, 75%, 100% height were 0, 0, 1, 140, 217. The artwork was inspected; no pixel editing scripts were used.

Asset catalog: `Clipo/Resources/Assets.xcassets/Player/`.
