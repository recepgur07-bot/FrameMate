# Audio Mix Controls Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mikrofon ve sistem sesi icin temel seviye kontrolleri eklemek ve kamera export hattisinda bu seviyeleri gercekten uygulamak.

**Architecture:** View model ses seviye durumunu tutar. Yeni bir audio mix builder export composition uzerinde mikrofon ve sistem sesi track'lerine ayri volume parametreleri uygular. SwiftUI yuzeyi bu iki ayari kayit moduna gore gosterir.

**Tech Stack:** Swift, SwiftUI, AVFoundation, AVAssetExportSession

---

### Task 1: Audio Mix Builder

**Files:**
- Create: `Sources/VideoRecorderApp/RecordingAudioMixBuilder.swift`
- Test: `Tests/VideoRecorderAppTests/RecordingAudioMixBuilderTests.swift`

- [ ] Step 1: Builder testlerini yaz
- [ ] Step 2: Fail ettigini dogrula
- [ ] Step 3: Minimal builder implementasyonunu ekle
- [ ] Step 4: Builder testlerini tekrar calistir

### Task 2: Recorder View Model Export Mix

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`

- [ ] Step 1: Ses seviyesi state'lerini ekle
- [ ] Step 2: Kamera export composition'ini audio mix ile dondur
- [ ] Step 3: Export session'a audio mix bagla
- [ ] Step 4: Mevcut recorder testlerini calistir

### Task 3: UI Controls

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`

- [ ] Step 1: Mikrofon seviye slider'ini ekle
- [ ] Step 2: Sistem sesi seviye slider'ini ekle
- [ ] Step 3: Etiketleri ve erisilebilir metinleri netlestir

### Task 4: Verification

**Files:**
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Step 1: Gerekli status/regresyon testlerini guncelle
- [ ] Step 2: `xcodebuild build` calistir
- [ ] Step 3: `xcodebuild test` calistir
