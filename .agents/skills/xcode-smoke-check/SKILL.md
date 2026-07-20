---
name: xcode-smoke-check
description: Use when verifying this repo after workflow, build, test, project, or CI-facing changes, especially when you need the canonical FrameMate smoke check.
---

# FrameMate Xcode Smoke Check

1. Confirm the repo root is the FrameMate project and the shared scheme is `FrameMate`.
2. Treat these as the canonical commands for this repo:
   - `xcodebuild build -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
   - `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
3. If the change only affects repo workflow docs, skills, or project automation, run at minimum:
   - `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS' -only-testing:FrameMateProjectTests/XcodeProjectConfigurationTests`
4. If the change affects app behavior, project wiring, resources, or release packaging, run the full canonical test suite.
5. Pass criteria:
   - command exits successfully
   - targeted or full tests report zero failures
   - no stale recommendation to use `swift build`, `swift test`, or the `VideoRecorderApp` scheme remains in newly touched workflow files
6. Fail criteria:
   - missing shared scheme
   - any `xcodebuild` failure
   - failing tests
   - touched workflow docs still point to stale commands
7. If service-level macOS warnings appear during tests but XCTest passes, report the warnings separately and do not mislabel them as test failures.
