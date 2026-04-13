# Screen Recording Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mevcut macOS video recorder uygulamasına ilk faz ekran kaydı desteği eklemek: tam ekran, pencere ve mikrofon sesli MP4 kayıt.

**Architecture:** Mevcut kamera kayıt hattısı korunacak; bunun yanına `ScreenCaptureKit` tabanlı ayrı bir ekran kayıt servisi eklenecek. `RecorderViewModel`, seçilen kayıt kaynağına göre kamera veya ekran kayıt motorunu kullanacak ve ortak durum akışını yönetecek.

**Tech Stack:** SwiftUI, AVFoundation, ScreenCaptureKit, XCTest

---

## Chunk 1: Source Model and View Model Wiring

### Task 1: Kayıt kaynağı modelini ekle

**Files:**
- Create: `Sources/VideoRecorderApp/RecordingSource.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Kaynak modeli için test beklentisini yaz**
- [ ] **Step 2: `RecordingSource` enum'unu ekle**
- [ ] **Step 3: Kaynak etiketlerini ve erişilebilir metinleri tanımla**
- [ ] **Step 4: İlgili testleri çalıştır**

### Task 2: View model'e ekran kayıt durumu ekle

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Başarısız test yaz**
- [ ] **Step 2: `selectedRecordingSource`, ekran/pencere listeleri ve seçim alanlarını ekle**
- [ ] **Step 3: Kaynağa göre `canStartRecording` ve durum metnini güncelle**
- [ ] **Step 4: Testleri çalıştır**

## Chunk 2: Screen Recording Abstraction

### Task 3: Ekran kayıt protokolünü ve modellerini ekle

**Files:**
- Create: `Sources/VideoRecorderApp/ScreenRecording.swift`
- Test: `Tests/VideoRecorderAppTests/TestSupport.swift`

- [ ] **Step 1: Ekran, pencere ve izin durumlarını temsil eden modelleri tasarla**
- [ ] **Step 2: Screen recording protokolünü ekle**
- [ ] **Step 3: Test stub'larını genişlet**
- [ ] **Step 4: Testleri çalıştır**

### Task 4: ScreenCaptureKit tabanlı recorder iskeletini ekle

**Files:**
- Create: `Sources/VideoRecorderApp/ScreenRecorder.swift`
- Modify: `project.yml`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Boş ama derlenen `ScreenRecorder` yapısını ekle**
- [ ] **Step 2: paylaşılabilir içerik yükleme metotlarını ekle**
- [ ] **Step 3: izin kontrolü için temel yardımcıları ekle**
- [ ] **Step 4: Derleme doğrulaması yap**

## Chunk 3: UI Integration

### Task 5: Kayıt kaynağı ve seçim kontrollerini ekle

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Kaynak seçiciyi ekle**
- [ ] **Step 2: Kaynağa göre kamera/ekran/pencere kontrollerini koşullu göster**
- [ ] **Step 3: erişilebilir açıklamaları ekle**
- [ ] **Step 4: Testleri çalıştır**

## Chunk 4: Recording Flow

### Task 6: View model'de source-aware kayıt başlat/durdur

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Kamera ve ekran için ayrık start/stop yolları tanımla**
- [ ] **Step 2: ekran kaydında kamera seçimi zorunluluğunu kaldır**
- [ ] **Step 3: ekran kaydı tamamlanınca mevcut MP4 export akışına bağla**
- [ ] **Step 4: Testleri çalıştır**

### Task 7: Screen recorder ile gerçek kayıt akışını bağla

**Files:**
- Modify: `Sources/VideoRecorderApp/ScreenRecorder.swift`
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: ekran veya pencere seçimine göre SCStream kur**
- [ ] **Step 2: mikrofon sesli kayıt writer hattısını bağla**
- [ ] **Step 3: stop anında dosyayı finalize et**
- [ ] **Step 4: Build ve test çalıştır**

## Chunk 5: Verification

### Task 8: Son doğrulama

**Files:**
- Modify: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: `swift test` çalıştır**
- [ ] **Step 2: `xcodebuild -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS' build` çalıştır**
- [ ] **Step 3: `xcodebuild test -project VideoRecorder.xcodeproj -scheme VideoRecorderApp -destination 'platform=macOS'` çalıştır**
- [ ] **Step 4: Çıktıları kontrol et ve kalan riskleri not et**
