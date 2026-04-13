# Mode-Based Recording Hub Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uygulamayı 4 ana kayıt moduna taşıyarak klavye dostu ve mod bazlı bir kayıt merkezi haline getirmek.

**Architecture:** Yeni bir `RecordingPreset` katmanı eklenecek ve mevcut kamera/ekran altyapısı bunun üstünde orkestre edilecek. Kamera ve ekran kaydı motorları korunacak; view model seçili preset üzerinden kaynak, yön ve görünür kontrol setini türetecek. SwiftUI yüzeyi ile menü komutları bu preset modeliyle beslenecek.

**Tech Stack:** SwiftUI, Observation, AVFoundation, ScreenCaptureKit, XCTest

---

## Chunk 1: Preset Model ve View Model Türetmeleri

### Task 1: Yeni preset tiplerini ekle

**Files:**
- Create: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecordingPreset.swift`
- Create: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ScreenCaptureSource.swift`
- Test: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecordingPresetTests.swift`

- [ ] **Step 1: Yazılacak davranış testini ekle**
- [ ] **Step 2: Testi çalıştır ve eksik tipler nedeniyle kırıldığını doğrula**
- [ ] **Step 3: `RecordingPreset` ve `ScreenCaptureSource` tiplerini minimal olarak ekle**
- [ ] **Step 4: Testi tekrar çalıştır ve geçtiğini doğrula**

### Task 2: View model preset türetmelerini ekle

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Preset bazlı türetmeleri doğrulayan failing testleri yaz**
- [ ] **Step 2: `selectedPreset`, `selectedScreenCaptureSource`, görünürlük ve aktif kaynak/mode türetmelerini ekle**
- [ ] **Step 3: Preset değişiminde cihaz/izin yenileme akışını bağla**
- [ ] **Step 4: İlgili testleri çalıştır**

## Chunk 2: UI ve Menü Akışı

### Task 3: Ana ekranı mod bazlı hale getir

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/ContentView.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: View model üzerinden UI görünürlük durumlarını test et**
- [ ] **Step 2: 4 modlu ana seçim yüzeyini ekle**
- [ ] **Step 3: Kamera ve ekran alanlarını preset bazlı göster/gizle**
- [ ] **Step 4: Ekran presetlerinde mikrofon seçimini görünür kıl**
- [ ] **Step 5: İlgili testleri çalıştır**

### Task 4: Menü ve klavye kısayollarını preset yapısına taşı

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/VideoRecorderApp.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Menü davranışını kapsayan küçük view model testlerini ekle**
- [ ] **Step 2: `Cmd-1 ... Cmd-4` mod seçim komutlarını ekle**
- [ ] **Step 3: `Cmd-R` kayıt akışını koru**
- [ ] **Step 4: Kamera presetlerinde kadraj koçu komutunu görünür bırak**
- [ ] **Step 5: Testleri çalıştır**

## Chunk 3: Durum Metinleri ve Doğrulama

### Task 5: Durum ve izin metinlerini preset odaklı hale getir

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/Sources/VideoRecorderApp/RecorderViewModel.swift`
- Modify: `/Users/recepgur/Desktop/video recorder/Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] **Step 1: Yatay/dikey kamera ve ekran presetleri için beklenen durum metinlerini test et**
- [ ] **Step 2: `makeStatusText` ve izin metinlerini preset bazlı sadeleştir**
- [ ] **Step 3: Ekran alt kaynağı `tam ekran / pencere` için metinleri koru**
- [ ] **Step 4: Testleri çalıştır**

### Task 6: Tam doğrulama

**Files:**
- Modify: `/Users/recepgur/Desktop/video recorder/README.md` (gerekirse kısa kullanım notu)

- [ ] **Step 1: `xcodegen generate` çalıştır**
- [ ] **Step 2: `xcodebuild -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS' build` çalıştır**
- [ ] **Step 3: `xcodebuild test -project '/Users/recepgur/Desktop/video recorder/VideoRecorder.xcodeproj' -scheme VideoRecorderApp -destination 'platform=macOS'` çalıştır**
- [ ] **Step 4: Gerekirse README’ye yeni kısayolları ekle**
