# Hybrid Recording Flow Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hybrid main-window plus menu-bar workflow with completion actions and configurable output folders.

**Architecture:** Keep recording and export logic in `RecorderViewModel`, add lightweight persisted output-directory state, and surface post-save actions through a dedicated completion sheet. Upgrade the menu bar controller into a persistent status item that reflects recording state and exposes last-recording actions.

**Tech Stack:** SwiftUI, AppKit, AVFoundation, XCTest

---

## Chunk 1: Output Directory And Completion State

### Task 1: Persist the default output directory

**Files:**
- Modify: `Sources/VideoRecorderApp/RecordingFileNamer.swift`
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecordingFileNamerTests.swift`

- [ ] Step 1: Write tests for custom output directories and stable naming.
- [ ] Step 2: Add an initializer that accepts a concrete output directory.
- [ ] Step 3: Load and persist the preferred output directory in the view model.
- [ ] Step 4: Use the preferred directory when preparing capture and export URLs.
- [ ] Step 5: Run focused file-namer and view-model tests.

### Task 2: Add completion-sheet state and file actions

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Step 1: Add a view-model model for a completed recording.
- [ ] Step 2: Set that state only after successful export completion.
- [ ] Step 3: Add actions for open, reveal, rename, save-as, and dismiss.
- [ ] Step 4: Inject file-opening and panel behaviors for testability.
- [ ] Step 5: Run focused completion-state tests.

## Chunk 2: User Interface

### Task 3: Present the completion sheet and output-folder settings UI

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Step 1: Add a completion sheet bound to the new view-model state.
- [ ] Step 2: Surface the output folder in Settings with a “choose folder” action.
- [ ] Step 3: Keep the current main recording surface unchanged except for the new completion UX.
- [ ] Step 4: Run focused recorder view-model tests.

## Chunk 3: Persistent Menu Bar Workflow

### Task 4: Upgrade the status item into a persistent hybrid control surface

**Files:**
- Modify: `Sources/VideoRecorderApp/MenuBarController.swift`
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift`
- Test: `Tests/VideoRecorderAppTests/MenuBarControllerTests.swift`

- [ ] Step 1: Make the menu bar item install once and update dynamically.
- [ ] Step 2: Add menu actions for toggle, show window, open last recording, reveal in Finder, settings, and quit.
- [ ] Step 3: Pulse only while recording and use an idle icon otherwise.
- [ ] Step 4: Keep the app alive after the main window closes.
- [ ] Step 5: Run focused menu-bar tests and a targeted app build.

## Chunk 4: Verification

### Task 5: Verify end-to-end behavior

**Files:**
- Modify only if needed based on verification failures

- [ ] Step 1: Run targeted XCTest suites for file naming, menu bar, and recorder view model.
- [ ] Step 2: Run `xcodebuild build` for the app target.
- [ ] Step 3: Summarize any remaining manual smoke checks around recording completion and Finder actions.
