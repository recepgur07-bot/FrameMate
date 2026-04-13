# Cursor Highlight Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional cursor highlight effect to screen and window exports, with a spotlight that follows the pointer and pulse rings on clicks.

**Architecture:** Track normalized cursor samples during screen/window recordings, then render cursor decoration layers during export inside the existing screen composition builder. Keep the feature off by default and gracefully fall back when tracking data is unavailable.

**Tech Stack:** SwiftUI, AppKit, AVFoundation, CoreAnimation, ScreenCaptureKit, XCTest

---

## Chunk 1: Data And TDD

### Task 1: Add failing tests for cursor defaults and geometry

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/ScreenCameraOverlayCompositionBuilderTests.swift`

- [ ] Write a failing test proving `Imleci vurgula` defaults to `false`
- [ ] Write a failing test proving cursor samples map into the expected render-space position
- [ ] Run the focused tests and verify the new assertions fail for the expected reason

### Task 2: Add cursor timeline models

**Files:**
- Create: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/CursorHighlightTimeline.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ScreenRecording.swift`

- [ ] Add `CursorSample`, `CursorClickEvent`, and `CursorHighlightTimeline`
- [ ] Extend screen/window options with geometry needed for cursor normalization
- [ ] Re-run the focused tests and get them green with minimal implementation

## Chunk 2: Runtime Tracking

### Task 3: Track cursor movement and clicks during screen recordings

**Files:**
- Create: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/CursorHighlightRecorder.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] Write a failing test for screen recording start/stop that expects cursor tracking to start and stop when enabled
- [ ] Implement a main-thread cursor tracker using periodic sampling plus global mouse-down monitors
- [ ] Store the pending timeline for the current recording
- [ ] Re-run focused tests until they pass

## Chunk 3: Export Decoration

### Task 4: Render cursor highlight in screen export

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ScreenCameraOverlayCompositionBuilder.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/ScreenCameraOverlayCompositionBuilderTests.swift`

- [ ] Write a failing test for cursor decoration layer creation
- [ ] Add cursor spotlight and click pulse layer generation
- [ ] Merge cursor layers with existing overlay decoration logic
- [ ] Re-run focused tests until they pass

## Chunk 4: UI And Verification

### Task 5: Add the toggle and wire it through

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ContentView.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] Add `Imleci vurgula` under screen/window controls
- [ ] Keep the default off
- [ ] Ensure disabled mode preserves current behavior

### Task 6: Regenerate, build, and test

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/project.yml` only if needed

- [ ] Run `xcodegen generate`
- [ ] Run `xcodebuild build -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- [ ] Run `xcodebuild test -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- [ ] Confirm focused cursor tests and the full suite are green
