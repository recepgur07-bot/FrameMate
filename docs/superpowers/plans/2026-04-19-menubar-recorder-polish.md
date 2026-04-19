# Menu Bar Recorder Polish Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make FrameMate behave like a fast macOS menu bar recorder with auto-hide, richer menu status, launch-at-login, and utility-style app behavior controls.

**Architecture:** Extend the existing app shell instead of replacing it. Add a small preferences layer for app-behavior toggles, wire those preferences into window presentation and activation policy, then expand menu bar state so recording can be managed confidently from the background.

**Tech Stack:** SwiftUI, AppKit, ServiceManagement, XCTest

---

## Chunk 1: Window And App Behavior

### Task 1: Lock the new presentation rules with tests

**Files:**
- Modify: `Tests/VideoRecorderAppTests/MainWindowPresentationPolicyTests.swift`
- Modify: `Sources/VideoRecorderApp/MainWindowPresentation.swift`

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run `swift test --filter MainWindowPresentationPolicyTests` and verify it fails for recording-start hide behavior**
- [ ] **Step 3: Implement minimal policy support for hide-on-start and configurable show-on-stop**
- [ ] **Step 4: Re-run `swift test --filter MainWindowPresentationPolicyTests` and verify it passes**

### Task 2: Add app behavior preferences

**Files:**
- Create: `Sources/VideoRecorderApp/AppBehaviorPreferences.swift`
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift`
- Modify: `Sources/VideoRecorderApp/ContentView.swift`

- [ ] **Step 1: Write failing tests for persisted preference defaults and app-shell decisions**
- [ ] **Step 2: Run the focused tests and verify they fail for missing preferences**
- [ ] **Step 3: Implement persisted behavior settings for auto-hide, show-on-stop, Dock icon mode, and launch-at-login**
- [ ] **Step 4: Re-run focused tests and verify they pass**

## Chunk 2: Menu Bar Utility Controls

### Task 3: Expand menu bar status and quick actions

**Files:**
- Modify: `Tests/VideoRecorderAppTests/MenuBarControllerTests.swift`
- Modify: `Sources/VideoRecorderApp/MenuBarController.swift`
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift`

- [ ] **Step 1: Write failing tests for duration/status text and quick preset actions**
- [ ] **Step 2: Run `swift test --filter MenuBarControllerTests` and verify it fails**
- [ ] **Step 3: Implement richer menu bar state, recording duration display, and preset shortcuts**
- [ ] **Step 4: Re-run `swift test --filter MenuBarControllerTests` and verify it passes**

## Chunk 3: Settings Surface And Verification

### Task 4: Expose utility behavior in Settings

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`

- [ ] **Step 1: Add settings toggles for auto-hide, restore window, Dock icon mode, and launch at login**
- [ ] **Step 2: Verify the settings compile and bind cleanly to the new preferences**

### Task 5: Full verification

**Files:**
- Verify only

- [ ] **Step 1: Run `swift test --filter MainWindowPresentationPolicyTests`**
- [ ] **Step 2: Run `swift test --filter MenuBarControllerTests`**
- [ ] **Step 3: Run `swift test`**
- [ ] **Step 4: Report any remaining risks honestly**
