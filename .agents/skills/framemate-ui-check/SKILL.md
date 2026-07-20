---
name: framemate-ui-check
description: Use when changing FrameMate UI flows, SwiftUI wording, onboarding, settings, menu bar behavior, or local HTML support/privacy pages.
---

# FrameMate UI Check

1. Start by identifying the UI surface:
   - Native macOS SwiftUI app UI
   - Repo-local HTML/support/privacy/store asset pages
2. For native macOS SwiftUI changes:
   - prefer source inspection and repo tests first
   - run relevant `xcodebuild test` coverage, then the full canonical test suite when the flow changed materially
   - do not default to Browser for native macOS window validation
3. For repo-local HTML or browser-shaped artifacts such as `docs/app-store/support.html` or `docs/app-store/privacy-policy.html`:
   - use Browser to inspect rendering, interaction, and screenshots when helpful
4. Check user-facing copy for consistency with FrameMate naming and accessibility language.
5. When onboarding, settings, status, or announcements change, pay extra attention to accessibility-facing text and any tests covering that copy.
6. Pass criteria:
   - relevant UI flow tests pass
   - browser checks are limited to browser-native assets
   - final notes clearly distinguish native-app verification from browser verification
7. Fail criteria:
   - browser was used as a substitute for native macOS verification without reason
   - UI-copy changes are unverified
   - changed flows skip canonical repo verification
