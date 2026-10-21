# Home and Library matte controls — 2026-10-21

Original artwork generated with the built-in image tool (Garden Host-Native workflow).
Final asset: `Clipo/Resources/Assets.xcassets/ClipoMatteControls.imageset/artwork.png`.
The previous glossy atlas remains unchanged for other screens.

## Final generation prompt

Production UI sprite atlas, opaque square image. Four equal rows separated by straight horizontal boundaries at exactly 25%, 50%, 75%. Each row contains one perfectly clean flat matte rounded rectangle button silhouette, spanning x=5% to 95%, y=row top+5% canvas to row bottom-5% canvas. All corners modest radius. Row 1 button tennis lime #D8FF62 on solid dark background #091713. Row 2 button pine #173E31 on solid dark background #091713. Row 3 button pine #173E31 on solid ivory background #F2F0DD. Row 4 button muted sage #BCC7B1 on solid ivory background #F2F0DD. Original refined tennis-club app digital graphic. No text, icon, shadow, bevel, highlights, border, distressed edges, dirt, or transparency. Extremely clean antialiased contours. Subtle matte paper texture confined to buttons only; backgrounds completely solid uniform colors. Center interiors practically flat for nine-slice UI stretch. Four rows evenly spaced and exactly equal size. No mockup.

## Integration

The delivered image is 1254 × 1254. `MatteSurface` extracts the measured silhouettes and uses cap insets to preserve their corners; it does not draw replacement artwork. The first two transparent drafts were rejected for ragged edges and were not added to the app.

Library categories use intrinsic localized widths with one-row, two-row, and vertical fallbacks. Selection remains in LibraryView state. Home keeps the original raw-query search behavior and uses a dedicated disabled-button palette. Seven-language label references, asset JSON, and diff whitespace were checked statically. No build, simulator run, or release was performed for this visual revision.
