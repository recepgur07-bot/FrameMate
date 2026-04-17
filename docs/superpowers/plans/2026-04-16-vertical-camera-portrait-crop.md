# Vertical Camera Portrait Crop Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dikey kamera modunda Mac kamerasından çekilen videoyu, telefondaki gibi siyah bant olmadan 1080×1920 portrait MP4 olarak dışa aktarmak (Reels/Shorts/TikTok için direkt paylaşılabilir).

**Architecture:** Mac kamerası her zaman 1920×1080 landscape kaydeder. Şu an `videoRotationAngle=90` ile rotasyon metadata'ya bırakılıyor ve export'ta "fit" (letterbox) uygulandığından üst/alt siyah bant oluşuyor. Yeni yaklaşım: rotasyonu capture'dan kaldır, export sırasında landscape kaynağı "resizeAspectFill" semantiğiyle portrait canvasa tam doldur — yüksekliğe göre ölçekle, yatayda kırp (center veya face-based). Auto-reframe dikey modda yalnızca yatay kaydırma (panning) yapar.

**Tech Stack:** AVFoundation, CGAffineTransform, Swift, XCTest

---

## Chunk 1: Capture — rotasyonu kaldır

### Task 1: `CaptureRecorder` — dikey modda 90° rotasyonu durdur

**Files:**
- Modify: `Sources/VideoRecorderApp/CaptureRecorder.swift:315-327`

**Neden:** `videoRotationAngle=90` kameradan landscape piksel verisi alır ve metadata'ya "portrait olarak göster" flag'i ekler. Export sırasında `preferredTransform` uygulandığında içerik 9:16 canvas'a "fit" ile yerleştirilir → siyah bantlar. Çözüm: rotasyonu kaldır, ham 1920×1080 landscape kaydet, export halleder.

- [ ] **Step 1: Testi yaz (failing)**

`Tests/VideoRecorderAppTests/RecordingModeTests.swift` dosyasını aç, aşağıdaki test'i ekle:

```swift
func testVerticalModeDoesNotApplyRotationAtCaptureLayer() {
    // CaptureRecorder'ın vertical1080p modunda videoRotationAngle=0 kullandığını doğrular.
    // applyOrientation private olduğundan davranışı RecordingMode üzerinden test ederiz.
    let mode = RecordingPreset.verticalCamera.recordingMode
    XCTAssertEqual(mode, RecordingMode.vertical1080p)
    // Bu test Step 2'de captureRotationAngle eklenmeden önce compile olmaz — bu doğru TDD davranışıdır.
    // Step 1: test eklenir (compile error = failing), Step 2: property eklenir (test geçer).
    XCTAssertEqual(RecordingMode.vertical1080p.captureRotationAngle, 0)
}
```

- [ ] **Step 2: `RecordingMode`'a `captureRotationAngle` ekle**

`Sources/VideoRecorderApp/RecordingMode.swift` — `renderSize` sonrasına ekle:

```swift
/// Rotation angle to apply at capture layer.
/// Both modes use 0 — vertical mode's portrait crop is handled at export time.
/// Switch exhaustiveness ensures new modes are handled explicitly.
var captureRotationAngle: CGFloat {
    switch self {
    case .horizontal1080p: return 0
    case .vertical1080p:   return 0
    }
}
```

- [ ] **Step 3: Testi çalıştır — geçmeli**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  -only-testing:VideoRecorderAppTests/RecordingModeTests \
  2>&1 | tail -30
```

Expected: `Test Suite 'RecordingModeTests' passed`

- [ ] **Step 4: `CaptureRecorder.applyOrientation` güncelle**

`Sources/VideoRecorderApp/CaptureRecorder.swift` — `applyOrientation(for:)` fonksiyonunu değiştir:

```swift
private func applyOrientation(for mode: RecordingMode) {
    // Rotation is intentionally not applied at the capture layer for any mode.
    // For vertical1080p, portrait crop is handled during export so that the
    // full landscape content is available for face-based horizontal panning.
    let angle: CGFloat = mode.captureRotationAngle  // always 0
    for connection in [movieOutput.connection(with: .video),
                       previewOutput.connection(with: .video)].compacted() {
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
```

`compacted()` yerine `compactMap { $0 }` kullan — Swift'de `.compacted()` yok:

```swift
private func applyOrientation(for mode: RecordingMode) {
    let angle: CGFloat = mode.captureRotationAngle  // always 0
    let connections = [movieOutput.connection(with: .video),
                       previewOutput.connection(with: .video)].compactMap { $0 }
    for connection in connections {
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
```

- [ ] **Step 5: Build — hata yok mu?**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild build -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
git add Sources/VideoRecorderApp/RecordingMode.swift \
        Sources/VideoRecorderApp/CaptureRecorder.swift \
        Tests/VideoRecorderAppTests/RecordingModeTests.swift && \
git commit -m "feat: remove capture-layer rotation — portrait crop handled at export"
```

---

## Chunk 2: AutoReframeEngine — portrait crop hesapla

### Task 2: Portrait-aware crop hesaplama

**Files:**
- Modify: `Sources/VideoRecorderApp/AutoReframe/AutoReframeEngine.swift`
- Modify: `Sources/VideoRecorderApp/AutoReframe/AutoReframeCrop.swift`
- Modify: `Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift`

**Mantık:**
- Kaynak: 1920×1080 landscape, preferredTransform=identity
- Hedef render: 1080×1920 portrait
- Fill scale = 1920/1080 = 1.778 (yüksekliği dolduracak şekilde ölçekle)
- Ölçeklenmiş genişlik = 1920×1.778 = 3413px
- Görünen pencere genişliği = 1080/1.778 = 607.5px
- Normalize: 607.5/1920 = 0.3164
- Auto-reframe: pencereyi yüzün x pozisyonuna göre yatayda kaydır

`AutoReframeCrop` için portrait modu: `width=0.3164, height=1.0, originX=face-based, originY=0`

- [ ] **Step 1: Portrait sabitlerini `AutoReframeCrop`'a ekle — failing test yaz**

`Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift` dosyasına ekle:

```swift
func testPortraitCropWidthIsCorrectRatioForLandscapeSource() {
    // Portrait crop: 1080 hedef genişlik / (1920/1080 fill scale) / 1920 kaynak genişlik
    // = 1080 * 1080 / (1920 * 1920) = (1080/1920)^2 ≈ 0.3164
    let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.5)
    XCTAssertEqual(crop.width, AutoReframeCrop.portraitWidthRatio, accuracy: 0.001)
    XCTAssertEqual(crop.height, 1.0, accuracy: 0.001)
    XCTAssertEqual(crop.originY, 0.0, accuracy: 0.001)
}

func testPortraitCropCenterXFollowsFace() {
    let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.3)
    // centerX of crop must be within the clamped range
    XCTAssertGreaterThanOrEqual(crop.originX, 0)
    XCTAssertLessThanOrEqual(crop.originX + crop.width, 1.0)
    XCTAssertEqual(crop.centerX, 0.3, accuracy: 0.01)
}

func testPortraitCropClampsAtLeftEdge() {
    // Face at far left: crop must not go negative
    let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.05)
    XCTAssertEqual(crop.originX, 0.0, accuracy: 0.001)
}

func testPortraitCropClampsAtRightEdge() {
    // Face at far right: crop must not exceed source width
    let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.95)
    XCTAssertEqual(crop.originX + crop.width, 1.0, accuracy: 0.001)
}

func testPortraitEngineProducesCropForCenteredFace() {
    let analysis = FrameAnalysis(
        faceBoxes: [NormalizedFaceBox(rect: CGRect(x: 0.43, y: 0.20, width: 0.14, height: 0.18))],
        subjectCount: .one,
        headroomRatio: 0.2,
        bottomCoverageRatio: 0.2,
        horizontalGroupCenter: 0.5,
        spacingMetric: 0,
        confidence: 0.95
    )
    let crop = AutoReframeEngine().portraitCrop(for: analysis)
    XCTAssertEqual(crop.height, 1.0, accuracy: 0.001)
    XCTAssertEqual(crop.width, AutoReframeCrop.portraitWidthRatio, accuracy: 0.001)
}

func testPortraitEngineReturnsFullHeightCenterCropForNilAnalysis() {
    let crop = AutoReframeEngine().portraitCrop(for: nil)
    XCTAssertEqual(crop.height, 1.0, accuracy: 0.001)
    XCTAssertEqual(crop.width, AutoReframeCrop.portraitWidthRatio, accuracy: 0.001)
    XCTAssertEqual(crop.centerX, 0.5, accuracy: 0.001)
}
```

- [ ] **Step 2: Test'i çalıştır — FAIL bekleniyor**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  -only-testing:VideoRecorderAppTests/AutoReframeEngineTests \
  2>&1 | tail -20
```

Expected: `error: ... portraitFullHeight ... has no member` (veya benzer)

- [ ] **Step 3: `AutoReframeCrop` — portrait sabitleri ve factory method ekle**

`Sources/VideoRecorderApp/AutoReframe/AutoReframeCrop.swift` dosyasına ekle:

```swift
// MARK: - Portrait crop support

extension AutoReframeCrop {
    /// Normalized width of the portrait crop window in a 1920×1080 landscape source.
    /// Derived from: renderWidth(1080) / fillScale(1920/1080) / sourceWidth(1920)
    ///             = (1080/1920)² ≈ 0.3164
    static let portraitWidthRatio: Double = pow(1080.0 / 1920.0, 2)

    /// Returns a crop that uses the full source height and a portrait-width horizontal window
    /// centered on `centerX` (normalized 0…1 in landscape source coordinates).
    static func portraitFullHeight(centerX: Double) -> AutoReframeCrop {
        let halfWidth = portraitWidthRatio / 2
        let clampedOriginX = (centerX - halfWidth).clamped(to: 0...(1.0 - portraitWidthRatio))
        return AutoReframeCrop(
            originX: clampedOriginX,
            originY: 0,
            width: portraitWidthRatio,
            height: 1.0
        )
    }
}
```

- [ ] **Step 4: `AutoReframeEngine` — `portraitCrop(for:)` ekle**

`Sources/VideoRecorderApp/AutoReframe/AutoReframeEngine.swift` dosyasına yeni fonksiyon ekle:

```swift
/// Returns a portrait-mode crop for a landscape source (1920×1080 → 1080×1920).
/// Shifts the horizontal crop window to keep the face centered.
/// Falls back to center crop when analysis is nil or low-confidence.
func portraitCrop(for analysis: FrameAnalysis?) -> AutoReframeCrop {
    guard let analysis, analysis.confidence >= 0.55,
          analysis.subjectCount == .one,
          let subject = analysis.subjects.first else {
        return .portraitFullHeight(centerX: 0.5)
    }
    return .portraitFullHeight(centerX: subject.faceBox.centerX)
}
```

- [ ] **Step 5: Testleri çalıştır — geçmeli**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  -only-testing:VideoRecorderAppTests/AutoReframeEngineTests \
  2>&1 | tail -20
```

Expected: `Test Suite 'AutoReframeEngineTests' passed`

- [ ] **Step 6: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
git add Sources/VideoRecorderApp/AutoReframe/AutoReframeCrop.swift \
        Sources/VideoRecorderApp/AutoReframe/AutoReframeEngine.swift \
        Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift && \
git commit -m "feat: add portrait crop support to AutoReframeEngine and AutoReframeCrop"
```

---

## Chunk 3: AutoReframeCompositionBuilder — portrait export

### Task 3: Portrait transform — landscape kaynağı portrait canvas'a fill et

**Files:**
- Modify: `Sources/VideoRecorderApp/AutoReframe/AutoReframeCompositionBuilder.swift`

**Mantık:**
Landscape kaynak (1920×1080, preferredTransform=identity) → 1080×1920 portrait render canvas.

Fill scale = renderHeight / sourceHeight = 1920/1080 = 1.778

Her portrait `AutoReframeCrop` için transform:
```
scale = 1920.0 / 1080.0
tx = -crop.originX * sourceWidth * scale
ty = 0
```

`makeVideoComposition` portrait modda `timeline.keyframes.isEmpty` olsa dahi her zaman composition oluşturur (aksi halde export letterbox uygular).

- [ ] **Step 1: Failing test yaz**

`Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift` dosyasına ekle (aynı dosyayı kullanmaya devam):

```swift
func testPortraitFillScaleConstantIsCorrect() {
    // Fill scale: 1920(renderH) / 1080(sourceH)
    XCTAssertEqual(AutoReframeCompositionBuilder.portraitFillScale, 1920.0 / 1080.0, accuracy: 0.001)
}

func testPortraitTransformForCenterCropMapsSourceCenterToRenderCenter() {
    // Center crop (centerX=0.5): source center (960,540) must map to render center (540,960)
    let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.5)
    let t = AutoReframeCompositionBuilder.portraitLayerTransform(for: crop)
    let sourceCenter = CGPoint(x: 960, y: 540).applying(t)
    XCTAssertEqual(sourceCenter.x, 540, accuracy: 1)
    XCTAssertEqual(sourceCenter.y, 960, accuracy: 1)
}

func testPortraitTransformForLeftFaceShiftsWindowLeft() {
    // Face at left (centerX=0.2): crop window starts at left, source left of frame maps to render x~0
    let crop = AutoReframeCrop.portraitFullHeight(centerX: 0.2)
    let t = AutoReframeCompositionBuilder.portraitLayerTransform(for: crop)
    // Left edge of crop window in source: crop.originX * 1920
    let cropLeftSourceX = crop.originX * 1920.0
    let mappedLeft = CGPoint(x: cropLeftSourceX, y: 0).applying(t)
    XCTAssertEqual(mappedLeft.x, 0, accuracy: 2)
}
```

- [ ] **Step 2: Test çalıştır — FAIL bekleniyor**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  -only-testing:VideoRecorderAppTests/AutoReframeEngineTests \
  2>&1 | tail -20
```

Expected: `error: ... portraitFillScale ... has no member`

- [ ] **Step 3: `AutoReframeCompositionBuilder` — portrait static helpers ekle**

`Sources/VideoRecorderApp/AutoReframe/AutoReframeCompositionBuilder.swift` dosyasına ekle (struct'ın içine, mevcut fonksiyonlardan önce):

```swift
// MARK: - Portrait camera export

/// Scale factor that fills a 1080×1920 portrait canvas from a 1920×1080 landscape source.
/// renderHeight(1920) / sourceHeight(1080) = 1.7̄7̄8̄
static let portraitFillScale: CGFloat = 1920.0 / 1080.0

/// Returns the AVCompositionLayerInstruction transform that maps a landscape 1920×1080
/// source track into a 1080×1920 portrait render canvas, using `crop` for horizontal position.
///
/// Math:
///   scale = portraitFillScale = 1.778
///   After scaling: source is 3413×1920, which exactly fills the 1920 canvas height.
///   tx = -crop.originX * 1920 * scale
///   ty = 0 (height fills perfectly, no vertical offset needed)
static func portraitLayerTransform(for crop: AutoReframeCrop) -> CGAffineTransform {
    let scale = portraitFillScale
    let tx = -crop.originX * 1920.0 * scale
    return CGAffineTransform(scaleX: scale, y: scale)
        .concatenating(CGAffineTransform(translationX: tx, y: 0))
}
```

- [ ] **Step 4: Test çalıştır — geçmeli**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  -only-testing:VideoRecorderAppTests/AutoReframeEngineTests \
  2>&1 | tail -20
```

Expected: `Test Suite 'AutoReframeEngineTests' passed`

- [ ] **Step 5: `makeVideoComposition` — `mode` parametresi ekle ve portrait dalını yaz**

`Sources/VideoRecorderApp/AutoReframe/AutoReframeCompositionBuilder.swift` dosyasındaki `makeVideoComposition` fonksiyonu imzasını güncelle ve portrait dalını ekle:

```swift
func makeVideoComposition(
    for asset: AVAsset,
    timeline: AutoReframeTimeline,
    mode: RecordingMode = .horizontal1080p
) async -> AVMutableVideoComposition? {
    // Portrait camera mode: always build a composition (no letterbox fallback)
    if mode == .vertical1080p {
        return await makePortraitVideoComposition(for: asset, timeline: timeline)
    }

    // Existing horizontal path — unchanged
    guard !timeline.keyframes.isEmpty,
          let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
        return nil
    }
    // ... rest of existing code unchanged ...
```

Ardından yeni private fonksiyonu ekle (struct'ın sonuna):

```swift
private func makePortraitVideoComposition(
    for asset: AVAsset,
    timeline: AutoReframeTimeline
) async -> AVMutableVideoComposition? {
    guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
        return nil
    }

    let duration = (try? await asset.load(.duration)) ?? .zero
    guard duration > .zero else { return nil }

    // DEPENDENCY: Chunk 1 must have removed capture-layer rotation first.
    // This function assumes the source track is 1920×1080 landscape (preferredTransform=identity).
    // Guard against accidentally being called on a pre-rotated portrait source.
    let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
    guard naturalSize.width > naturalSize.height else {
        // Source is already portrait or square — landscape assumption violated.
        // Fall back to nil so the export session honours preferredTransform as-is.
        return nil
    }

    let renderSize = RecordingMode.vertical1080p.renderSize  // 1080×1920

    let composition = AVMutableVideoComposition()
    composition.renderSize = renderSize
    composition.frameDuration = CMTime(value: 1, timescale: 30)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

    if timeline.keyframes.isEmpty {
        // No auto-reframe: center crop
        let centerCrop = AutoReframeCrop.portraitFullHeight(centerX: 0.5)
        layerInstruction.setTransform(
            Self.portraitLayerTransform(for: centerCrop),
            at: .zero
        )
    } else {
        // Auto-reframe: keyframe-based horizontal panning
        for keyframe in timeline.keyframes {
            layerInstruction.setTransform(
                Self.portraitLayerTransform(for: keyframe.crop),
                at: keyframe.time
            )
        }
        // Smooth ramps between keyframes
        if timeline.keyframes.count >= 2 {
            for index in 0..<(timeline.keyframes.count - 1) {
                let current = timeline.keyframes[index]
                let next = timeline.keyframes[index + 1]
                let timeRange = CMTimeRange(start: current.time, end: next.time)
                guard timeRange.duration > .zero else { continue }
                layerInstruction.setTransformRamp(
                    fromStart: Self.portraitLayerTransform(for: current.crop),
                    toEnd: Self.portraitLayerTransform(for: next.crop),
                    timeRange: timeRange
                )
            }
        }
    }

    instruction.layerInstructions = [layerInstruction]
    composition.instructions = [instruction]
    return composition
}
```

- [ ] **Step 6: Build — hata yok mu?**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild build -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
git add Sources/VideoRecorderApp/AutoReframe/AutoReframeCompositionBuilder.swift \
        Tests/VideoRecorderAppTests/AutoReframeEngineTests.swift && \
git commit -m "feat: portrait fill export in AutoReframeCompositionBuilder — no letterbox"
```

---

## Chunk 4: RecorderViewModel — portrait mode export'u bağla

### Task 4: `exportMP4` portrait mode için doğru compositoru çağırsın

**Files:**
- Modify: `Sources/VideoRecorderApp/RecorderViewModel.swift`

**Neden:** `exportMP4` şu an `autoReframeCompositionBuilder.makeVideoComposition(for:timeline:)` çağırırken `mode` geçmiyor. `vertical1080p` için portrait path aktive olmuyor.

Ayrıca: `handleRecordingCompletion` portrait için auto-reframe timeline'ını `AutoReframeEngine.portraitCrop(for:)` ile oluşturmalı. Şu an `crop(for:mode:)` kullanılıyor; dikey modda bu kare crop döndürüyor.

- [ ] **Step 1: `exportMP4` — `cameraMode` parametresi ekle**

`RecorderViewModel.swift` içindeki `exportMP4` fonksiyon imzasını güncelle:

```swift
private func exportMP4(
    from sourceURL: URL,
    to destinationURL: URL,
    timeline: AutoReframeTimeline,
    cameraMode: RecordingMode = .horizontal1080p,   // ← YENİ
    systemAudioURL: URL? = nil,
    screenExportMode: RecordingMode? = nil,
    // ... geri kalan parametreler aynı ...
```

Ve fonksiyonun içinde `makeVideoComposition` çağrısını güncelle (screen path değil, camera path):

```swift
// Mevcut kod:
let composition = await autoReframeCompositionBuilder.makeVideoComposition(
    for: exportPackage.asset,
    timeline: timeline
)

// Yeni kod:
let composition = await autoReframeCompositionBuilder.makeVideoComposition(
    for: exportPackage.asset,
    timeline: timeline,
    mode: cameraMode
)
```

- [ ] **Step 2: `handleRecordingCompletion` — portrait için `portraitCrop` kullan**

`RecorderViewModel` içinde auto-reframe recording sırasında `processAutoReframeFrame` veya eşdeğeri çağrıldığında portrait mode için `portraitCrop` kullanılmalı. Şu an `AutoReframeEngine.crop(for:mode:)` kullanılıyor. Bunu güncelle:

`RecorderViewModel.swift` satır **3324** — tam olarak şu satırı bul:

```swift
let targetCrop = autoReframeEngine.crop(for: analysis, mode: selectedMode)
```

Bu satırı şununla değiştir:

```swift
// Mevcut (horizontal için):
let crop = autoReframeEngine.crop(for: analysis, mode: selectedMode)

// Yeni — portrait için ayrı path:
let crop: AutoReframeCrop
if selectedMode == .vertical1080p {
    crop = autoReframeEngine.portraitCrop(for: analysis)
} else {
    crop = autoReframeEngine.crop(for: analysis, mode: selectedMode)
}
```

- [ ] **Step 3: `handleRecordingCompletion` — `cameraMode` geçir**

`handleRecordingCompletion` içindeki `exportMP4` çağrısını güncelle:

```swift
// Mevcut:
let exportResult = try await exportMP4(
    from: captureURL,
    to: finalURL,
    timeline: isAutoReframeEnabled ? autoReframeTimeline.shifted(by: pauseTimeline) : AutoReframeTimeline(),
    systemAudioURL: systemAudioURL,
    pauseTimeline: pauseTimeline
)

// Yeni:
let exportResult = try await exportMP4(
    from: captureURL,
    to: finalURL,
    timeline: isAutoReframeEnabled ? autoReframeTimeline.shifted(by: pauseTimeline) : AutoReframeTimeline(),
    cameraMode: selectedMode,   // ← YENİ
    systemAudioURL: systemAudioURL,
    pauseTimeline: pauseTimeline
)
```

- [ ] **Step 4: Build — hata yok mu?**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild build -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Tüm testleri çalıştır**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  2>&1 | grep -E "passed|failed|error:" | tail -30
```

Expected: Tüm suite'ler `passed`

- [ ] **Step 6: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
git add Sources/VideoRecorderApp/RecorderViewModel.swift && \
git commit -m "feat: wire portrait export — cameraMode passed to composition builder"
```

---

## Chunk 5: Preview — portrait modda doğru live görüntü

### Task 5: `VideoPreviewView` — portrait crop için düzeltilmiş transform

**Files:**
- Modify: `Sources/VideoRecorderApp/VideoPreviewView.swift`

**Neden:** Şu anki `applyCrop()`, `scaleX = 1/crop.width` ve `scaleY = 1/crop.height` kullanıyor. Portrait crop için `width=0.3164, height=1.0` → `scaleX=3.16, scaleY=1.0` — bu x eksenini 3x büyütür, içerik bozulur.

Portrait preview için: `resizeAspectFill` gravity zaten landscape feed'i portrait container'a dolduruyor. Sadece yatay kaydırma (horizontal translation) gerekli.

- [ ] **Step 1: `PreviewContainerView.applyCrop` — portrait ve horizontal ayrımı**

`Sources/VideoRecorderApp/VideoPreviewView.swift` içindeki `applyCrop()` fonksiyonunu güncelle:

```swift
private func applyCrop() {
    // Portrait crop: width << 1, height ≈ 1.0
    // The preview layer's .resizeAspectFill gravity already fills the portrait
    // container with the landscape feed (centering it). We only need a horizontal
    // translation to follow the face. Applying independent x/y scales would
    // distort the aspect ratio.
    let isPortraitCrop = currentCrop.height > 0.95 && currentCrop.width < 0.5

    if isPortraitCrop {
        // With resizeAspectFill in a portrait container, the preview layer fills the
        // container height. The fill scale = bounds.height / 1080.
        // Source pixel delta to shift = (0.5 - centerX) * 1920
        // Mapped to container pixels = delta * (bounds.height / 1080)
        let fillScale = bounds.height / 1080.0
        let horizontalShift = (0.5 - currentCrop.centerX) * 1920.0 * fillScale
        let transform = CGAffineTransform(translationX: horizontalShift, y: 0)
        previewLayer.setAffineTransform(transform)
    } else {
        // Original square-crop behavior for horizontal mode
        let scaleX = 1 / max(currentCrop.width, 0.0001)
        let scaleY = 1 / max(currentCrop.height, 0.0001)
        let translationX = (0.5 - currentCrop.centerX) * bounds.width * scaleX
        let translationY = (0.5 - currentCrop.centerY) * bounds.height * scaleY

        let transform = CGAffineTransform.identity
            .translatedBy(x: translationX, y: translationY)
            .scaledBy(x: scaleX, y: scaleY)

        previewLayer.setAffineTransform(transform)
    }
}
```

- [ ] **Step 2: Build + testler**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  2>&1 | grep -E "passed|failed|error:" | tail -20
```

Expected: `BUILD SUCCEEDED`, tüm testler `passed`

- [ ] **Step 3: Commit**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
git add Sources/VideoRecorderApp/VideoPreviewView.swift && \
git commit -m "fix: portrait preview — use horizontal-only translation, avoid x/y scale distortion"
```

---

## Chunk 6: Uyarı notunu temizle + final build

### Task 6: ContentView'daki "siyah bant" uyarı notunu kaldır

**Files:**
- Modify: `Sources/VideoRecorderApp/ContentView.swift`

Artık siyah bant olmadığından önceki oturumda eklenen uyarı metni gereksiz.

- [ ] **Step 1: `previewCard` içindeki `verticalScreen` uyarısını bul ve kaldır**

`ContentView.swift` içinde:

```swift
// KALDIR — bu blok artık geçersiz:
if viewModel.selectedPreset == .verticalScreen {
    HStack(alignment: .top, spacing: 6) {
        Image(systemName: "exclamationmark.triangle")
            ...
        Text(String(localized: "Mac ekranı yatay olduğundan..."))
            ...
    }
}
```

**Not:** `verticalCamera` için uyarı yoktu, `verticalScreen` (ekran kaydı) için eklenmişti. Bu plan kamera kaydını düzeltiyor; ekran kaydı ayrı bir konudur. Şimdilik sadece `verticalCamera` ile ilgili `previewCard` info metnini güncelle:

`previewCard` içindeki alt notu güncelle — dikey kamera için artık "portrait crop uygulanır" demesi yeterli:

```swift
Text(String(localized: "Önizleme — kayıt \(viewModel.selectedMode.width)×\(viewModel.selectedMode.height) çözünürlükte yapılır"))
```

Bu not zaten doğru bilgiyi veriyor, değişiklik gerekmeyebilir. Build başarılıysa geç.

- [ ] **Step 2: Final tam build + test**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
xcodebuild test -project VideoRecorder.xcodeproj \
  -scheme VideoRecorderApp \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed" | tail -20
```

Expected: Tüm suite'ler `passed`

- [ ] **Step 3: Final commit**

```bash
cd "/Users/recepgur/Desktop/video recorder" && \
git add -A && \
git commit -m "feat: vertical camera portrait crop — landscape source fill-cropped to 1080x1920, no letterbox"
```

---

## Özet — Ne değişti

| Bileşen | Eski | Yeni |
|---|---|---|
| `CaptureRecorder` | `videoRotationAngle=90` → metadata rotation | Rotation yok, ham 1920×1080 kaydeder |
| `AutoReframeCrop` | Sadece kare crop | `portraitFullHeight(centerX:)` factory + `portraitWidthRatio` |
| `AutoReframeEngine` | Sadece kare crop hesaplar | `portraitCrop(for:)` yatay panning için |
| `AutoReframeCompositionBuilder` | Portrait için nil döner → letterbox | `makePortraitVideoComposition` → fill, siyah bant yok |
| `RecorderViewModel` | `makeVideoComposition(for:timeline:)` | `makeVideoComposition(for:timeline:mode:)` |
| `VideoPreviewView` | Portrait crop'ta x/y scale → bozulma | Portrait crop'ta sadece yatay translate |

**Sonuç:** 1080×1920 MP4, tüm alanı dolu, direkt Reels/Shorts/TikTok'a yüklenebilir.
