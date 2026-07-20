---
name: macos-app-ui-check
description: Use when changing native macOS SwiftUI flows, wording, settings, or repo-local HTML/support pages.
---

# macOS App UI Check

1. Identify whether the surface is native macOS SwiftUI or browser-native content.
2. For native macOS SwiftUI changes:
   - prefer source inspection and `xcodebuild` verification first
   - do not default to Browser for native window validation
3. For local HTML or browser-native artifacts, Browser may be used for rendering checks.
4. Re-run the canonical test suite when the user-facing flow changed materially.
5. Keep final notes explicit about what was verified natively versus in a browser.
