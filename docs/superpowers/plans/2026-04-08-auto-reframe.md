# Auto Reframe Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tek kişilik çekimlerde canlı önizlemeyi ve kayıt sonrası MP4 çıktısını yumuşak dijital crop ile otomatik yeniden kadrajlamak.

**Architecture:** `FrameAnalysis` çıktısı `AutoReframeEngine` tarafından normalize crop rect'e çevrilecek. `RecorderViewModel` bu crop'u `AutoReframeSmoother` ile yumuşatıp hem `VideoPreviewView`'e aktaracak hem de kayıt sırasında zaman damgalı bir timeline'a yazacak. Kayıt bitince timeline'dan `AVMutableVideoComposition` üretilip mevcut export hattısında MP4'e uygulanacak.

**Tech Stack:** Swift, SwiftUI, AVFoundation, XCTest

---

## Chunk 1: Core Model And Engine

### Task 1: Crop modelini ekle

**Files:**
- Create: `Sources/VideoRecorderApp/AutoReframe/AutoReframeCrop.swift`
- Test: `Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift`

- [ ] `AutoReframeCrop` modelini oluştur
- [ ] `fullFrame`, `clamped`, `interpolated` yardımcılarını ekle
- [ ] Modeli testte kullan

### Task 2: Auto reframe motorunu yaz

**Files:**
- Create: `Sources/VideoRecorderApp/AutoReframe/AutoReframeEngine.swift`
- Test: `Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift`

- [ ] Tek kişi için hedef crop hesabını yaz
- [ ] Yatay ve dikey mod eşiklerini ayır
- [ ] Çok kişi ve düşük güven için full-frame dönüşünü test et

## Chunk 2: Smoothing And View Model

### Task 3: Crop yumuşatıcısını ekle

**Files:**
- Create: `Sources/VideoRecorderApp/AutoReframe/AutoReframeSmoother.swift`
- Test: `Tests/VideoRecorderAppTests/AutoReframeSmootherTests.swift`

- [ ] Exponential smoothing uygulayan yapı ekle
- [ ] Full-frame'e dönüş davranışını ekle
- [ ] Geçişlerin sıçramadığını test et

### Task 4: RecorderViewModel entegrasyonu

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] `isAutoReframeEnabled` ve `currentAutoReframeCrop` durumlarını ekle
- [ ] Preview frame analizini auto-reframe ile paylaş
- [ ] Auto-reframe açıkken crop üretildiğini test et

## Chunk 3: Preview UI

### Task 5: Önizleme görünümüne crop uygula

**Files:**
- Modify: `Sources/VideoRecorderApp/VideoPreviewView.swift`
- Modify: `Sources/VideoRecorderApp/ContentView.swift`

- [ ] `VideoPreviewView` bileşenini crop alacak şekilde genişlet
- [ ] Preview layer transform hesabını ekle
- [ ] UI'ya tek bir aç/kapat kontrolü ekle

## Chunk 4: Verification

### Task 6: Recording timeline altyapısını ekle

**Files:**
- Create: `Sources/VideoRecorderApp/AutoReframe/AutoReframeTimeline.swift`
- Create: `Sources/VideoRecorderApp/AutoReframe/AutoReframeCompositionBuilder.swift`
- Test: `Tests/VideoRecorderAppTests/AutoReframeTimelineTests.swift`

- [ ] Timeline modelini ve anahtar kare ekleme mantığını yaz
- [ ] Composition builder ile zaman bazlı transform üret
- [ ] Fallback durumlarını test et

### Task 7: Export hattısını auto-reframe ile bağla

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] Kayıt başında timeline sıfırla
- [ ] Analiz geldikçe crop anahtar karelerini timeline'a yaz
- [ ] Export sırasında composition varsa uygula, yoksa normal export'a düş

### Task 8: Tüm testleri çalıştır

**Files:**
- Test: `Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift`
- Test: `Tests/VideoRecorderAppTests/AutoReframeSmootherTests.swift`
- Test: `Tests/VideoRecorderAppTests/AutoReframeTimelineTests.swift`
- Test: `Tests/VideoRecorderAppTests/RecorderViewModelTests.swift`

- [ ] `swift test --filter AutoReframeEngineTests`
- [ ] `swift test --filter AutoReframeSmootherTests`
- [ ] `swift test --filter AutoReframeTimelineTests`
- [ ] `swift test --filter RecorderViewModelTests`
- [ ] `swift test`
