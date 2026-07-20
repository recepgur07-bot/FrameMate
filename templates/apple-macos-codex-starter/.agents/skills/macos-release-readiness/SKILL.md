---
name: macos-release-readiness
description: Use when preparing this macOS app for release, metadata review, or shipping-risk checks.
---

# macOS Release Readiness

1. Use App Store Connect MCP for live App Store and TestFlight facts whenever the request depends on current external state.
2. Use GitHub MCP for PR and review context when release readiness depends on branch or PR discussion.
3. Run the canonical repo verification command before saying the app is release-ready:
   - `xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'`
4. Inspect `fastlane/Appfile` and `fastlane/Fastfile` when release automation is part of the task.
5. Fail release-readiness claims if tests fail or external release facts are unverified.
