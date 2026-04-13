# Keyboard Shortcut Overlay Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional keyboard shortcut overlay to screen and window exports so meaningful shortcuts appear briefly on video.

**Architecture:** Record timestamped shortcut labels during screen/window capture, then render bottom-center shortcut cards in the existing screen export decoration pipeline. Keep the feature off by default and ignore plain typing.

**Tech Stack:** SwiftUI, AppKit, AVFoundation, CoreAnimation, XCTest

---

## Chunk 1: Timeline And TDD

### Task 1: Add failing tests for defaults and shortcut filtering

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`
- Create: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/KeyboardShortcutFormatterTests.swift`

- [ ] Add a failing test proving the shortcut overlay toggle defaults to `false`
- [ ] Add formatter tests for a valid shortcut label and ignored plain typing
- [ ] Run focused tests and confirm they fail for the right reason

### Task 2: Add shortcut timeline models and formatter

**Files:**
- Create: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/KeyboardShortcutTimeline.swift`

- [ ] Add `KeyboardShortcutEvent` and `KeyboardShortcutTimeline`
- [ ] Add a formatter that returns labels only for shortcut-like combinations
- [ ] Re-run focused tests and get them green

## Chunk 2: Runtime Tracking

### Task 3: Track shortcut events during screen recordings

**Files:**
- Create: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/KeyboardShortcutRecorder.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/TestSupport.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Add a failing test for screen recording start/stop that expects the shortcut tracker to start and stop when enabled
- [ ] Implement a global key-down monitor that records only qualifying shortcuts
- [ ] Wire the pending shortcut timeline into the active screen recording flow
- [ ] Re-run focused tests until green

## Chunk 3: Export Decoration

### Task 4: Render shortcut cards in screen export

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ScreenCameraOverlayCompositionBuilder.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/ScreenCameraOverlayCompositionBuilderTests.swift`

- [ ] Add a failing test proving shortcut events create export decoration layers
- [ ] Render bottom-center shortcut cards with fade timing
- [ ] Keep cursor and camera decoration working in the same animation tool
- [ ] Re-run focused tests until green

## Chunk 4: UI And Verification

### Task 5: Add the toggle and final verification

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ContentView.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] Add `Klavye kisayollarini goster` to screen/window controls
- [ ] Keep the default off
- [ ] Run `xcodegen generate`
- [ ] Run `xcodebuild build -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- [ ] Run `xcodebuild test -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
