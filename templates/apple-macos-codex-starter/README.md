# __DISPLAY_NAME__

Codex-ready native macOS SwiftUI starter project.

## Generate The Xcode Project

```bash
xcodegen generate
```

## Build

```bash
xcodebuild build -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'
```

## Test

```bash
xcodebuild test -project __MODULE_NAME__.xcodeproj -scheme __MODULE_NAME__ -destination 'platform=macOS'
```

## Open In Xcode

```bash
open __MODULE_NAME__.xcodeproj
```

Use the shared `__MODULE_NAME__` scheme for local runs, debugging, and archiving.
