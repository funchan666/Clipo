# Immersive player refresh — 2026-10-20

The requested TikTok-style structure uses full-viewport video, vertical page snapping, a compact right action rail, bottom-left metadata and a thin bottom seek control. It does not fabricate social counts, creators, comments or follow actions unsupported by the backend.

## Changes

- Replaced the abrupt 220-point dark panel with an original raster opacity scrim.
- Right rail now contains Save/Saved, Share and More with new original bitmap glyphs, measured optical centers and at least 48×54-point tap areas. Saved uses a filled bookmark and the existing lime accent.
- Mute is at the top right; Back or Discover search sits at the top left. Removed the persistent Discover header slab when search is closed.
- Channel/title are compact white text in a separate flexible column; removed uppercase monospaced lime text and the repeated swipe instruction.
- A 2-point white progress track retains a 44-point interaction area. Scrubbing pauses playback, exposes elapsed/total time and resumes only if previously playing and still active, eligible, foreground and not presenting an ad. The shared editor scrubbers retain their lime/default sizing.
- Existing fullscreen page identities, stream URLs, looping, watch/favorite accounting and genuine share sheet are retained. Video content is not altered to mask unavailable resources.

## Layout and verification

Media follows the enclosing viewport. Foreground controls use independently supplied safe-area insets; background extends to the screen edges. No screen-size constants, device-specific geometry, new SDK APIs or dimension-based view identities were introduced.

Inspected source, diffs, asset metadata, glyph crop bounds and PNG alpha. Generated artwork was visually reviewed. This revision has not been compiled or run, and neither live vertical swipe behavior nor Duo posture/Dynamic Type layouts are claimed as verified. Previous runtime evidence in `RUNTIME-AUDIT-2026-10-20.md` predates this revision.
