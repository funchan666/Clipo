# Edge-to-edge presentation

- All app-owned page and sheet backgrounds explicitly extend through container safe areas using `clipoScreenBackground`. System purchase, advertising, photo/file picker and share presentations retain their platform layout.
- LaunchScreen and the in-app startup mark are centered in the full container, rather than the safe-area rectangle.
- Discover and full-screen playback measure an expanded viewport for paging and video. Their enclosing container supplies independent top, bottom, leading and trailing insets to playback controls. Page identity and playback ownership remain unchanged when container dimensions change.
- Interactive foreground content, the custom tab bar and keyboard avoidance remain inset. This implements full-screen visuals, not placing interactive controls underneath the camera cutout or home indicator. The question about also extending foreground content remains unanswered at delivery.
- The minimum target remains iOS 17; the installed SDK inspected was iOS 27.1. No new device-specific dimensions or APIs were introduced.

Reference: [Apple: ignoresSafeArea(_:edges:)](https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:)). Using `.container` leaves keyboard-region behavior intact.

Validation: source/diff inspection and LaunchScreen XML parsing only. No compilation, tests, simulator launch, device or Duo posture verification was performed. Live paging, keyboard and touch behavior still require runtime verification.
