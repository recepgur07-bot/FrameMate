# Frame Coach Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `Cmd-D` framing coach that gives continuous spoken guidance for 1-3 person desk-style video composition before recording.

**Architecture:** Analyze preview frames with a dedicated analysis service, convert the resulting composition metrics into one high-priority spoken cue, and wire that state into the existing macOS recorder UI and command system. Keep face detection, coaching decisions, and speech playback in separate focused units so the heuristics can evolve without destabilizing capture behavior.

**Tech Stack:** Swift, SwiftUI, AVFoundation, Vision, AppKit accessibility/speech APIs, XCTest

---

## Chunk 1: Core Analysis and Coaching Decisions

### Task 1: Add frame-analysis domain types

**Files:**
- Create: `Sources/VideoRecorderApp/FrameCoach/FrameAnalysis.swift`
- Test: `Tests/VideoRecorderAppTests/FrameCoachingEngineTests.swift`

- [ ] **Step 1: Write the failing tests for analysis-driven coaching inputs**

Create tests that express analysis inputs for:
- one centered subject with good framing
- subject too low
- subject too high
- subject too far left/right
- desk too visible
- ceiling too visible
- two people off-center
- three people too wide

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter FrameCoachingEngineTests`
Expected: FAIL because the analysis/coaching types do not exist yet.

- [ ] **Step 3: Add minimal analysis model types**

Implement small immutable types for:
- normalized face boxes
- subject count
- headroom ratio
- bottom coverage ratio
- horizontal group center
- spacing metric
- analysis confidence

- [ ] **Step 4: Run the focused tests to verify compile progress**

Run: `swift test --filter FrameCoachingEngineTests`
Expected: FAIL in the coaching engine behavior, not because model types are missing.

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/FrameCoach/FrameAnalysis.swift Tests/VideoRecorderAppTests/FrameCoachingEngineTests.swift
git commit -m "test: add frame coach analysis types"
```

### Task 2: Implement coaching decision engine

**Files:**
- Create: `Sources/VideoRecorderApp/FrameCoach/FrameCoachingEngine.swift`
- Modify: `Tests/VideoRecorderAppTests/FrameCoachingEngineTests.swift`

- [ ] **Step 1: Extend tests to assert exact instruction outcomes**

Expected Turkish outputs should cover:
- `Kadraj uygun`
- `Biraz sola`
- `Biraz sağa`
- `Kamerayı biraz yukarı al`
- `Kamerayı biraz aşağı indir`
- `Biraz uzaklaş`
- `Biraz yaklaş`
- `Tavan fazla görünüyor`
- `Masa çok görünüyor`
- `İkinci kişi kadraja tam girmiyor`
- `Grup çok dağınık`

- [ ] **Step 2: Run tests and verify they fail for missing engine logic**

Run: `swift test --filter FrameCoachingEngineTests`
Expected: FAIL with unimplemented coaching decision behavior.

- [ ] **Step 3: Implement the minimal rule engine**

Add:
- priority ordering
- thresholds
- single-instruction output
- person-count-aware rules for 1, 2, and 3 people

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter FrameCoachingEngineTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/FrameCoach/FrameCoachingEngine.swift Tests/VideoRecorderAppTests/FrameCoachingEngineTests.swift
git commit -m "feat: add frame coaching decision engine"
```

## Chunk 2: Speech Throttling and Live Coach State

### Task 3: Add speech throttling abstraction

**Files:**
- Create: `Sources/VideoRecorderApp/FrameCoach/SpeechCuePlayer.swift`
- Test: `Tests/VideoRecorderAppTests/SpeechCuePlayerTests.swift`

- [ ] **Step 1: Write failing tests for repetition control**

Cover:
- first instruction is spoken
- identical instruction is suppressed during cooldown
- changed instruction is spoken immediately
- disabled coach prevents speech

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter SpeechCuePlayerTests`
Expected: FAIL because the speech player does not exist.

- [ ] **Step 3: Implement minimal speech cue player**

Use a protocol-backed speaker dependency so tests can observe emitted utterances without invoking system speech.

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter SpeechCuePlayerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/FrameCoach/SpeechCuePlayer.swift Tests/VideoRecorderAppTests/SpeechCuePlayerTests.swift
git commit -m "feat: add throttled speech cue player"
```

### Task 4: Add frame coach coordinator state to the recorder view model

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`

- [ ] **Step 1: Write failing tests for coach toggle behavior**

Cover:
- `Cmd-D` state toggles on and off
- enabling the coach updates status/announcement state
- disabling the coach silences future instructions
- coach does not speak when recording state forbids it, if that is the chosen rule

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter RecorderViewModelFrameCoachTests`
Expected: FAIL because framing coach state is not present.

- [ ] **Step 3: Implement minimal view model state**

Add:
- `isFrameCoachEnabled`
- `currentFrameCoachInstruction`
- dependencies for coaching engine and speech player
- a public toggle method

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter RecorderViewModelFrameCoachTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/RecorderViewModel.swift Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift
git commit -m "feat: add frame coach state to recorder view model"
```

## Chunk 3: Preview Analysis Pipeline

### Task 5: Add a preview-frame analysis service

**Files:**
- Create: `Sources/VideoRecorderApp/FrameCoach/FrameAnalysisService.swift`
- Test: `Tests/VideoRecorderAppTests/FrameAnalysisServiceTests.swift`

- [ ] **Step 1: Write failing tests around service orchestration**

Do not try to unit-test Vision directly. Test:
- no frame produces no result
- detected face boxes are normalized into analysis input
- unsupported counts degrade gracefully

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter FrameAnalysisServiceTests`
Expected: FAIL because the service does not exist.

- [ ] **Step 3: Implement the minimal service wrapper**

Encapsulate:
- `Vision` face rectangle request
- normalized coordinate conversion
- heuristic metrics for top/bottom composition

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter FrameAnalysisServiceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/FrameCoach/FrameAnalysisService.swift Tests/VideoRecorderAppTests/FrameAnalysisServiceTests.swift
git commit -m "feat: add frame analysis service"
```

### Task 6: Expose preview frames from the capture pipeline

**Files:**
- Modify: `Sources/VideoRecorderApp/CaptureRecorder.swift`
- Modify: `Sources/VideoRecorderApp/VideoPreviewView.swift`
- Test: `Tests/VideoRecorderAppTests/CaptureRecorderFrameFeedTests.swift`

- [ ] **Step 1: Write failing tests for non-recording frame delivery hooks**

Cover:
- coordinator can subscribe to preview frames
- frame feed does not break existing recording flow
- frame feed can be enabled/disabled

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter CaptureRecorderFrameFeedTests`
Expected: FAIL because no frame-feed abstraction exists.

- [ ] **Step 3: Implement the smallest frame-feed mechanism**

Prefer a dedicated callback/protocol for preview sample buffers rather than mixing analysis logic into `CaptureRecorder`.

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter CaptureRecorderFrameFeedTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/CaptureRecorder.swift Sources/VideoRecorderApp/VideoPreviewView.swift Tests/VideoRecorderAppTests/CaptureRecorderFrameFeedTests.swift
git commit -m "feat: expose preview frames for frame coach"
```

## Chunk 4: App Wiring and Accessibility UX

### Task 7: Wire analysis results into live spoken guidance

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`

- [ ] **Step 1: Write failing integration-style tests for analysis-to-speech flow**

Cover:
- analysis result reaches coaching engine
- highest-priority instruction becomes current coach instruction
- speech player receives throttled cues

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter RecorderViewModelFrameCoachTests`
Expected: FAIL because live analysis is not connected.

- [ ] **Step 3: Implement minimal wiring**

Add:
- preview frame callback handling
- background-safe analysis dispatch
- main-actor state updates for spoken instructions

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter RecorderViewModelFrameCoachTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/RecorderViewModel.swift Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift
git commit -m "feat: wire live frame analysis into coaching"
```

### Task 8: Add `Cmd-D` command and visible coach state

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Modify: `Sources/VideoRecorderApp/VideoRecorderApp.swift`
- Test: `Tests/VideoRecorderAppTests/FrameCoachCommandTests.swift`

- [ ] **Step 1: Write failing tests for command and state exposure**

Cover:
- `Cmd-D` toggles frame coach
- menu title reflects enabled/disabled state
- visible status text reflects current coach state

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `swift test --filter FrameCoachCommandTests`
Expected: FAIL because the command and UI state are not present.

- [ ] **Step 3: Implement minimal UI wiring**

Add:
- command menu action
- accessibility-friendly label for coach status
- optional on-screen text of the latest instruction

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift test --filter FrameCoachCommandTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/VideoRecorderApp/ContentView.swift Sources/VideoRecorderApp/VideoRecorderApp.swift Tests/VideoRecorderAppTests/FrameCoachCommandTests.swift
git commit -m "feat: add frame coach command and ui state"
```

## Chunk 5: End-to-End Verification

### Task 9: Run full automated verification

**Files:**
- Modify as needed based on failures from prior tasks

- [ ] **Step 1: Run all Swift Package tests**

Run: `swift test`
Expected: PASS

- [ ] **Step 2: Run Xcode targeted tests for frame coach**

Run: `xcodebuild test -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS' -only-testing:VideoRecorderAppTests/RecorderViewModelTests`
Expected: PASS

- [ ] **Step 3: Run broader Xcode test suite**

Run: `xcodebuild test -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS'`
Expected: PASS or, if the host app lingers in the harness, PASS with a documented cleanup step.

- [ ] **Step 4: Perform manual accessibility smoke test**

Verify manually:
- `Cmd-D` enables coach
- user hears guidance
- repeated same guidance is throttled
- turning coach off stops announcements
- recording still works

- [ ] **Step 5: Commit final stabilization changes**

```bash
git add Sources Tests VideoRecorder.xcodeproj docs/superpowers/specs/2026-04-08-frame-coach-design.md docs/superpowers/plans/2026-04-08-frame-coach.md
git commit -m "feat: add framing coach for desk video composition"
```
