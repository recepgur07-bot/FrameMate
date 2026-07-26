# Reviewer: antigravity (r1)

Sources inspected (read-only):
- `Sources/VideoRecorderApp/FrameCoach/CaptureCoachingEngine.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachingEngine.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachingProfile.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCue.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCueResolver.swift`
- `Sources/VideoRecorderApp/FrameCoach/SpatialCoachCuePlayer.swift`
- `Sources/VideoRecorderApp/FrameCoach/SpeechCuePlayer.swift`
- `Sources/VideoRecorderApp/FrameCoach/RecordingElapsedTimeAnnouncer.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameAnalysis.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameAnalysisService.swift`
- `Sources/VideoRecorderApp/FrameCoach/FrameLightingAnalyzer.swift`
- `Sources/VideoRecorderApp/RecorderViewModel.swift`
- `Sources/VideoRecorderApp/ContentView.swift`
- `Sources/VideoRecorderApp/CameraOverlayRecorder.swift`
- `Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`

Running screen / device / VoiceOver runtime session: **doğrulanamadı** (no live UI execution session or physical/simulator VoiceOver runtime environment was accessible in this static analysis pass).

## Sonuç

Conditional approval. The `FrameCoach` sub-system demonstrates a coherent design for spatial camera guidance tailored for blind and low-vision users. Key strengths include role assignment per subject (`FrameSubjectRole`), profile-driven framing rules (`FrameCoachingProfile`), dual feedback delivery (spoken announcements via `SpeechCuePlayer` and continuous spatial audio tones via `SpatialCoachCuePlayer`), and explicit debounce mechanisms (3-miss face loss threshold, 3-second "locked good" suppression window).

However, static analysis reveals structural defects and edge-case gaps:
1. Multi-person logic is incomplete for 3 people, dropping overlap (`overlapInstruction`) and scale imbalance (`scaleImbalanceInstruction`) checks entirely when `subjectCount == .three`.
2. Subject-count transitions lack hysteresis, risking rapid alternating announcements (e.g. `"Bir kişi görünüyor"` <-> `"İki kişi görünüyor"`) under noisy face detection.
3. Inconsistent "no face" strings (`"Yüz algılanamıyor, kameraya bak"` vs `"Yüz algılanamıyor"`) degrade voice guidance clarity.
4. Core control flow relies on localized string equality (`"kadraj uygun"`, `"kadraj dengeli"`) across multiple files rather than strongly typed enum/struct state signals.
5. Modern Apple accessibility capabilities (Haptics via `NSHapticFeedbackManager`, Vision body/pose detection, VoiceOver speech pacing/SSML markers) remain unutilized.

## Kritik bulgular

1. **Multi-person rules bypass 3-person scenes (Accessibility / Edge case defect)**:
   In `FrameCoachingEngine.swift`, `overlapInstruction` and `scaleImbalanceInstruction` both explicitly guard `analysis.subjectCount == .two`. When 3 people are in frame (`.three`), these rules are skipped entirely. If one person in a 3-person scene is covered/behind another (`overlapRatio >= 0.45`), or standing significantly closer to the camera (`widthRatio >= 1.90`), no specific coaching guidance is spoken.

2. **Subject count transitions lack debounce hysteresis (Speech repetition defect)**:
   In `RecorderViewModel.swift` (`processCaptureCoachAnalysis`), `lastAnnouncedSubjectCount` triggers an immediate announcement (`"Bir kişi görünüyor..."` or `"İki kişi görünüyor..."`) whenever `analysis.subjectCount` changes. If a face detection flickers near the detection boundary, `subjectCount` alternates between `.one` and `.two` on consecutive frames, causing repeated announcements without any time threshold or hysteresis.

3. **Inconsistent "missing face" guidance strings (VoiceOver UX defect)**:
   Three separate locations handle face absence:
   - `CaptureCoachingEngine.swift:31`: `"Yüz algılanamıyor, kameraya bak"`
   - `FrameCoachingEngine.swift:15`: `"Yüz algılanamıyor, kameraya bak"`
   - `RecorderViewModel.swift:1703`: `"Yüz algılanamıyor"`
   When a blind user experiences brief face loss (after the 3-miss debounce), `RecorderViewModel.swift` posts `"Yüz algılanamıyor"`, omitting the helpful actionable instruction `"kameraya bak"`.

4. **Fragile localized-string equality for state checks (Architecture defect)**:
   - `RecorderViewModel.swift:1728`: `let isGood = guidance == String(localized: "kadraj uygun") || guidance == String(localized: "kadraj dengeli")`
   - `FrameCoachSpatialCueResolver.swift:23-24`: compares `normalized` against localized `"kadraj uygun"` and `"kadraj dengeli"`.
   Coupling control logic (locking to good framing, spatial cue centering, frequency throttling) to translated UI strings creates fragile runtime behavior if localization catalogs or phrasing change.

5. **Face count hard cap of 3 silently discards extra subjects**:
   `FrameAnalysisService.swift` applies `.prefix(3)` to Vision face detections. If 4 or more people are in front of the camera, `subjectCount` resolves to `.three` (`FrameSubjectCount.three`), and extra subjects are silently dropped. The system announces `"Üç kişi görünüyor"`, providing inaccurate information to a blind user.

6. **State machine logic leaked into `RecorderViewModel`**:
   `RecorderViewModel.swift` directly manages `consecutiveMissingFaceAnalyses`, `lastGoodFrameAt`, `lastGoodInstruction`, `lastAnnouncedSubjectCount`, and `isHardFrameCoachInstruction`. This clutter impairs testability and separates coaching state from `FrameCoachingEngine`.

## Onaylanan kararlar

- **3-Miss Face Loss Debounce**: Requiring 3 consecutive `nil` frame analyses in `RecorderViewModel.swift` before declaring face loss effectively suppresses transient Vision drops.
- **3-Second "Locked Good" Window**: Suppressing minor advisory nudges for 3 seconds after a good frame maintains stability for blind users making small adjustments.
- **Dual Cue Channel Design**: Combining spoken VoiceOver/AVSpeech instructions with continuous spatial audio tones (`SpatialCoachCuePlayer`) allows users to orient visually/auditorily without constant speech chatter.
- **Profile-Based Framing Rules**: `FrameCoachingProfile` (`.singleDeskSpeaker`, `.twoPersonPodcast`, `.verticalSocialVideo`, `.verticalConversation`, `.screenGuide`) appropriately adapts distance, headroom, and bottom coverage thresholds based on the recording context.

## Riskli varsayımlar

- **VoiceOver Audio Priority and Overlap**: Assumed that `NSAccessibility.post(..., priority: .high)` in `SystemAccessibilityAnnouncer` cleanly interrupts or queues over `RecordingElapsedTimeAnnouncer` (which posts at 30s intervals with `.medium` priority) and system VoiceOver notifications. Live runtime behavior is **doğrulanamadı**.
- **Localization Catalog Alignment**: Assumed that `isHardFrameCoachInstruction`'s English keyword list (`"not fully in frame"`, `"further back"`, `"closer to the camera"`) matches localized strings in English locale runs. Because string catalogs (`.xcstrings`) were not inspected, this is **doğrulanamadı**.
- **Fixed Vision Confidence**: Assumed that hardcoding `confidence: 0.9` in `FrameAnalysisService.swift` is an acceptable stub for Vision face confidence. If Vision produces low-confidence false positives, they will be treated as high-confidence faces.

## Doğrulama listesi

- [ ] Verify multi-person framing behavior with 3 subjects on a physical device / simulator to test overlap and distance responses (**doğrulanamadı** in static pass).
- [ ] Test live VoiceOver audio concurrency when `RecordingElapsedTimeAnnouncer` triggers during a `FrameCoach` instruction (**doğrulanamadı** in static pass).
- [ ] Check `.xcstrings` localization catalog to confirm English translation matches for `isHardFrameCoachInstruction`.
- [ ] Verify subject count stability when 2 people move near camera boundaries.
- [ ] Run `xcodebuild test -project VideoRecorder.xcodeproj -scheme FrameMate -destination 'platform=macOS'` to confirm all existing tests pass (**doğrulanamadı** in static pass, code untouched).

## Önerilen plan düzeltmeleri

As this is a review-only task with no active implementation plan, these are recommended follow-up improvements for future implementation tasks:

1. **Refactor Guidance Result into a Typed Struct**:
   Modify `FrameCoachingEngine` to return a structured result (e.g. containing `instruction: String`, `isBalanced: Bool`, `severity: GuidanceSeverity`) to eliminate string equality checks (`"kadraj uygun"`, `"kadraj dengeli"`) in `RecorderViewModel` and `FrameCoachSpatialCueResolver`.

2. **Extend Multi-Person Rules to 3-Person Framing**:
   Update `overlapInstruction` and `scaleImbalanceInstruction` in `FrameCoachingEngine.swift` to handle `.three` subject counts, evaluating pairwise overlap and relative face sizes across all detected subjects.

3. **Unify Face Loss Strings**:
   Standardize missing face notifications across `CaptureCoachingEngine`, `FrameCoachingEngine`, and `RecorderViewModel` to a single constant: `String(localized: "Yüz algılanamıyor, kameraya bak")`.

4. **Add Hysteresis to Subject Count Announcements**:
   Require a stable subject count across N consecutive frames (e.g., 3-5 frames) before updating `lastAnnouncedSubjectCount` to prevent flickering announcements.

5. **Leverage macOS Haptics and Modern Apple Accessibility APIs**:
   Integrate `NSHapticFeedbackManager` (or trackpad haptics on supported Mac hardware) for center-confirmation alignment, and explore Vision body pose APIs (`VNDetectHumanBodyPoseRequest`) for head/shoulder framing accuracy.
