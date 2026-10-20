# Home platform guide

The final homepage guide is a static platform-identifier grid below the link composer. It is not a backend recommendation list or website directory. The earlier paste/code/discover/help shortcut draft was removed after the user's clarification.

The user requested popular platforms and more than six entries. The twelve identifiers are TikTok, YouTube, Instagram, Facebook, X, Reddit, Vimeo, Dailymotion, Pinterest, Twitch, Snapchat and Bilibili. Tapping one opens native copy/paste instructions for that platform; it does not launch a website, overwrite the link field or start an automatic request.

The grid uses the generated `ClipoPlatformAtlas` raster, with labels and interaction remaining native SwiftUI. The 3-by-4 source atlas is cropped for display only. The on-screen grid adapts to available width, uses a narrower two-column arrangement for accessibility text sizes, and retains normal scrolling and safe areas. The existing link illustration was reduced into the top action row to give the platform area more room; no app-name or page-title header was restored.

Artwork was generated using the built-in image tool. Final prompt: `ProjectMaterials/UIAssets/Prompts/Platforms/platform-atlas.txt`. Final asset: `Clipo/Resources/Assets.xcassets/ClipoPlatformAtlas.imageset/platform-atlas.png`. These are generated platform identifiers, not a claim of official partnership or a new proprietary brand system. Unused intermediate platform/shortcut atlases were not added to app resources.

Brand references consulted: [TikTok developer design guidance](https://developers.tiktok.com/docs/en/getting-started-design-guidelines), [YouTube press resources](https://blog.youtube/press/), [Meta brand resources](https://www.meta.com/brand/resources/meta/company-brand/) and [Reddit brand resources](https://redditinc.com/brand).

Video resolution continues through the existing backend API. Adding an identifier does not add a platform SDK or implement a new extractor. No per-platform external-link playback validation was performed. The user confirmed support for the earlier reference-platform list; the newly requested popular-platform list still requires end-to-end service verification.

Static asset metadata/reference, source and diff checks only. No compilation, tests or simulator/device run. The generated atlas was visually inspected; the updated native screen has not been runtime-rendered.
