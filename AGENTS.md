# FrameMate Agent Guide

## Repo Shape

- Native macOS SwiftUI application for local screen, camera, and audio recording.
- Main Xcode project: `VideoRecorder.xcodeproj`
- Canonical scheme: `FrameMate`
- Main app sources: `Sources/VideoRecorderApp`
- Unit tests: `Tests/VideoRecorderAppTests`
- Repo and workflow verification tests: `Tests/VideoRecorderProjectTests`
- Release and store assets: `fastlane`, `docs/app-store`, `docs/ReleaseRiskMatrix.md`

## Canonical Commands

- Open in Xcode: `open VideoRecorder.xcodeproj`
- Build: `xcodebuild build -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
- Full test suite: `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'`
- Targeted project workflow tests: `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS' -only-testing:FrameMateProjectTests/XcodeProjectConfigurationTests`

Do not treat old `swift test`, `swift build`, or `VideoRecorderApp` scheme references as canonical. Historical specs and plans in `docs/superpowers/` may still contain stale commands from earlier project phases. Prefer the live Xcode project, shared scheme, README, and this file.

## Working Rules

- Read this file before touching code, docs, skills, or release metadata.
- Use Plan mode for medium, ambiguous, or multi-file work before implementation.
- Explore the repo and current project state before asking the user questions.
- Implement only after the approach is stable.
- Run the repo-standard verification command before claiming success.
- For review requests, list findings first, ordered by severity, with file references.

## Safety

- This repo may be dirty when a task starts. Never revert or overwrite unrelated user changes.
- Prefer adding narrow, focused changes over large repo-wide rewrites.
- If repo docs conflict with the live project, trust the live project and update the docs.

## Tool Routing

- Use Browser only for local web assets or HTML artifacts such as `docs/app-store/support.html`, `docs/app-store/privacy-policy.html`, or screenshot/contact-sheet style pages. Browser is not the default verification path for the native macOS windowed app.
- Use GitHub MCP for pull request, issue, comment, or review metadata instead of shell-only workarounds.
- Use App Store Connect MCP for App Store and TestFlight facts instead of memory.
- Use subagents only for clearly parallel exploration or review tasks.
- Use Node REPL only when a real JavaScript runtime is needed.

## Definition Of Done

- Workflow, docs, and repo automation changes must keep `FrameMateProjectTests/XcodeProjectConfigurationTests` green.
- Behavior changes should run the full canonical test suite unless the user explicitly asks for a narrower pass.
- If `xcodebuild` emits system-service warnings while tests still pass, mention the warnings in the final summary instead of hiding them.
