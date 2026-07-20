---
name: xcode-smoke-check
description: Use when verifying project, workflow, build, test, or CI-facing changes in this macOS Xcode repo.
---

# Xcode Smoke Check

1. Confirm the repo root contains `__MODULE_NAME__.xcodeproj` and the canonical scheme is `__MODULE_NAME__`.
2. Treat these as the canonical commands:
   - `xcodebuild build -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'`
   - `xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'`
3. If the change only affects workflow docs, skills, or repo automation, run at minimum:
   - `xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS' -only-testing:__MODULE_NAME__ProjectTests/WorkflowConfigurationTests`
4. If the change affects app behavior, project wiring, or resources, run the full canonical suite.
5. Report warnings separately when tests still pass.
