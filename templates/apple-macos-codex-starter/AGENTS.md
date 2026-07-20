# __DISPLAY_NAME__ Agent Guide

## Repo Shape

- Native macOS SwiftUI application starter with Codex-first workflow defaults.
- Main Xcode project: `__MODULE_NAME__.xcodeproj`
- Canonical scheme: `__MODULE_NAME__`
- Main app sources: `Sources/App`
- App tests: `Tests/AppTests`
- Repo workflow tests: `Tests/ProjectTests`
- Release automation: `fastlane`

## Canonical Commands

- Generate or refresh the Xcode project after editing `project.yml`: `xcodegen generate`
- Open in Xcode: `open __MODULE_NAME__.xcodeproj`
- Build: `xcodebuild build -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'`
- Full test suite: `xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'`
- Workflow verification tests: `xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS' -only-testing:__MODULE_NAME__ProjectTests/WorkflowConfigurationTests`

Do not treat `swift build` or `swift test` as canonical for this Xcode-first app template.

## Working Rules

- Read this file before changing code, docs, or automation.
- Use Plan mode for medium, ambiguous, or multi-file work before implementation.
- Explore the live project state before asking the user questions.
- Implement only after the approach is stable.
- Run the repo-standard verification command before claiming success.
- For review requests, list findings first with file references.

## Tool Routing

- Use Browser only for browser-native or local HTML artifacts, not as the default verification tool for the native macOS app.
- Use GitHub MCP for PR, issue, and review metadata instead of shell-only workarounds.
- Use App Store Connect MCP for App Store or TestFlight facts instead of memory.
- Use subagents only for clearly parallel exploration or review tasks.
- Use Node REPL only when a real JavaScript runtime is needed.

## Definition Of Done

- Workflow and automation changes keep `WorkflowConfigurationTests` green.
- Behavior changes should run the full canonical test suite unless the user explicitly asks for a narrower pass.
- If `xcodebuild` emits system-service warnings while tests still pass, mention the warnings in the final summary instead of hiding them.
