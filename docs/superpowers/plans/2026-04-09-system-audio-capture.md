# System Audio Capture Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ekran ve pencere kayıtlarına isteğe bağlı sistem sesi eklemek, aynı kontrolü tüm modlarda görünür hale getirmek ve kamera modlarında mevcut sınırı açıkça anlatmak.

**Architecture:** Ortak toggle durumu `RecorderViewModel` içinde tutulacak. `ScreenRecordingProviding` ve `ScreenRecorder`, ScreenCaptureKit `capturesAudio` özelliğini kullanacak şekilde genişletilecek. UI toggle'ı her modda gösterecek, ama gerçek kayıt davranışı ilk aşamada ekran ailesinde aktif olacak.

**Tech Stack:** SwiftUI, ScreenCaptureKit, AVFoundation, XCTest

---

### Task 1: Shared state ve UI kontrolünü ekle

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] `isSystemAudioEnabled` durumunu ekle
- [ ] Toggle'ı tüm modlarda görünür yap
- [ ] Kamera modunda açık sınır mesajını durum metnine ekle
- [ ] İlgili testleri çalıştır

### Task 2: Screen recording protokolünü genişlet

**Files:**
- Modify: `Sources/VideoRecorderApp/ScreenRecording.swift`
- Modify: `Tests/VideoRecorderAppTests/TestSupport.swift`

- [ ] `includeSystemAudio` parametresini protokole ekle
- [ ] Mock screen recorder'ı yeni parametreyi izleyecek şekilde güncelle

### Task 3: Screen recorder'a gerçek sistem sesi desteği ekle

**Files:**
- Modify: `Sources/VideoRecorderApp/ScreenRecorder.swift`
- Test: `Tests/VideoRecorderAppTests/ScreenRecorderTests.swift`

- [ ] `SCStreamConfiguration.capturesAudio` desteğini ekle
- [ ] mikrofon ve sistem sesinin birlikte çalıştığı config testlerini ekle

### Task 4: View model recording akışını bağla

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] ekran/pencere kaydı başlatırken `includeSystemAudio` değerini geçir
- [ ] durum metnini ses kombinasyonlarına göre iyileştir
- [ ] testleri güncelle

### Task 5: Verification

**Files:**
- Modify: `Tests/VideoRecorderAppTests/ScreenRecorderTests.swift`
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] `xcodebuild build -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS'`
- [ ] `xcodebuild test -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS'`
- [ ] Gerçek dünya smoke test için kısa not bırak
