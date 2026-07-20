---
name: macos-release-readiness
description: Use when preparing FrameMate for TestFlight, App Store submission, release metadata review, or shipping-risk checks.
---

# FrameMate macOS Release Readiness

1. Use App Store Connect MCP for live App Store, TestFlight, build, and submission facts whenever the request depends on current external state.
2. Use GitHub MCP for PR and review context if release readiness depends on a specific pull request or branch discussion.
3. Read repo-local release material before making release claims:
   - `docs/ReleaseRiskMatrix.md`
   - `docs/app-store/app-review-notes.md`
   - `fastlane/Fastfile`
   - `fastlane/metadata/en-US/*`
   - `fastlane/metadata/tr/*`
4. Run the canonical repo verification command before saying the app is release-ready:
   - `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
5. If the request touches packaging, signing, metadata, privacy copy, screenshots, or review notes, also inspect the related `fastlane` and `docs/app-store` files directly.
6. Pass criteria:
   - repo verification passes
   - metadata and review-note files exist for `en-US` and `tr` where expected
   - live release facts come from App Store Connect MCP, not memory
7. Fail criteria:
   - tests fail
   - release facts are stale or inferred without MCP verification
   - required metadata/support/privacy artifacts are missing
