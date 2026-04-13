# Screen Camera Overlay Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ekran kaydi modlarina kamera kutusu ozelligi eklemek ve bunu MP4 export asamasinda videoya birlestirmek.

**Architecture:** Ekran kaydi ana asset olarak kalacak. Kamera kutusu icin ayri bir hafif capture recorder gecici video uretecek. Export sirasinda yeni bir composition builder bu iki asset'i sabit boyutlu picture-in-picture olarak birlestirecek.

**Tech Stack:** SwiftUI, AVFoundation, ScreenCaptureKit, XCTest

---

## Chunk 1: Models And ViewModel Wiring

### Task 1: Overlay position modelini ekle

**Files:**
- Create: `Sources/VideoRecorderApp/ScreenCameraOverlayPosition.swift`
- Test: `Tests/VideoRecorderAppTests/ScreenCameraOverlayPositionTests.swift`

- [ ] Step 1: Position enum ve label/geometry anchor bilgisini yaz
- [ ] Step 2: Position enum testlerini ekle
- [ ] Step 3: Testleri calistir

### Task 2: View model'e overlay state ekle

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Step 1: `isScreenCameraOverlayEnabled` ve `selectedScreenCameraOverlayPosition` ekle
- [ ] Step 2: Ekran modlarinda kamera secimi / konum secimi gorunurlugunu ekle
- [ ] Step 3: View model gorunurluk testlerini ekle
- [ ] Step 4: Hedef testleri calistir

## Chunk 2: Overlay Capture

### Task 3: Hafif kamera overlay recorder ekle

**Files:**
- Create: `Sources/VideoRecorderApp/CameraOverlayRecorder.swift`
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `Tests/VideoRecorderAppTests/TestSupport.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Step 1: Video-only capture protocol ve implementasyonu ekle
- [ ] Step 2: View model'e inject et ve screen recording start/stop akisina bagla
- [ ] Step 3: Mock recorder ekle
- [ ] Step 4: Overlay acik/kapali start testlerini ekle
- [ ] Step 5: Hedef testleri calistir

## Chunk 3: Export Composition

### Task 4: Overlay composition builder ekle

**Files:**
- Create: `Sources/VideoRecorderApp/ScreenCameraOverlayCompositionBuilder.swift`
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/ScreenCameraOverlayCompositionBuilderTests.swift`

- [ ] Step 1: Screen + overlay asset composition mantigini yaz
- [ ] Step 2: View model export akisini overlay destekleyecek sekilde guncelle
- [ ] Step 3: Position geometry/composition testlerini ekle
- [ ] Step 4: Hedef testleri calistir

## Chunk 4: Verification

### Task 5: Tam dogrulama

**Files:**
- Modify if needed: implementation files above

- [ ] Step 1: `xcodebuild build -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS'`
- [ ] Step 2: `xcodebuild test -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS'`
- [ ] Step 3: Son kalan hata veya test sorunlarini duzelt
