# Frame Coach Framing Revision Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make framing guidance mode-aware, replace weak top/bottom heuristics with talking-head composition rules, and improve two-person balance guidance.

**Architecture:** Extend the frame-analysis model with scale and imbalance metrics, then make the coaching engine choose instructions using separate horizontal and vertical talking-head profiles. Keep the capture pipeline unchanged apart from passing the selected recording mode into coach decisions through the view model.

**Tech Stack:** Swift, SwiftUI, AVFoundation, Vision, XCTest

---

## Chunk 1: Mode-Aware Coaching Rules

### Task 1: Add failing tests for horizontal and vertical framing expectations

**Files:**
- Modify: `Tests/VideoRecorderAppTests/FrameCoachingEngineTests.swift`

- [ ] **Step 1: Write failing tests**
- [ ] **Step 2: Run `swift test --filter FrameCoachingEngineTests` and verify the new tests fail for missing mode-aware logic**
- [ ] **Step 3: Implement minimal model and engine changes**
- [ ] **Step 4: Run `swift test --filter FrameCoachingEngineTests` and verify they pass**

### Task 2: Add failing tests for two-person scale imbalance and depth imbalance wording

**Files:**
- Modify: `Tests/VideoRecorderAppTests/FrameCoachingEngineTests.swift`

- [ ] **Step 1: Write failing tests for left/right person scale mismatch**
- [ ] **Step 2: Run `swift test --filter FrameCoachingEngineTests` and verify failure**
- [ ] **Step 3: Implement minimal coaching rule for person-specific imbalance**
- [ ] **Step 4: Run `swift test --filter FrameCoachingEngineTests` and verify pass**

## Chunk 2: View Model Wiring

### Task 3: Pass selected recording mode into coaching decisions

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`

- [ ] **Step 1: Add failing test proving current mode influences spoken guidance**
- [ ] **Step 2: Run `swift test --filter RecorderViewModelFrameCoachTests` and verify failure**
- [ ] **Step 3: Implement the smallest wiring change**
- [ ] **Step 4: Run `swift test --filter RecorderViewModelFrameCoachTests` and verify pass**

## Chunk 3: Verification

### Task 4: Run full verification

**Files:**
- Modify as needed based on failures

- [ ] **Step 1: Run `swift test --filter FrameCoachingEngineTests`**
- [ ] **Step 2: Run `swift test --filter RecorderViewModelFrameCoachTests`**
- [ ] **Step 3: Run `swift test`**

