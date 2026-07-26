# Reviewer: claude (r1)

Sources inspected (read-only, full file contents unless noted):
`Sources/VideoRecorderApp/FrameCoach/CaptureCoachingEngine.swift`,
`Sources/VideoRecorderApp/FrameCoach/FrameCoachingEngine.swift`,
`Sources/VideoRecorderApp/FrameCoach/FrameCoachingProfile.swift`,
`Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCue.swift`,
`Sources/VideoRecorderApp/FrameCoach/FrameCoachSpatialCueResolver.swift`,
`Sources/VideoRecorderApp/FrameCoach/SpatialCoachCuePlayer.swift`,
`Sources/VideoRecorderApp/FrameCoach/SpeechCuePlayer.swift`,
`Sources/VideoRecorderApp/FrameCoach/RecordingElapsedTimeAnnouncer.swift`,
`Sources/VideoRecorderApp/FrameCoach/FrameAnalysis.swift`,
`Sources/VideoRecorderApp/FrameCoach/FrameAnalysisService.swift`,
`Tests/VideoRecorderAppTests/RecorderViewModelFrameCoachTests.swift`, and the
relevant sections of `Sources/VideoRecorderApp/RecorderViewModel.swift`
(preview-frame wiring, `processCaptureCoachAnalysis`, settings enums,
`automaticFrameCoachingProfile`). No simulator/device session was run in this
pass — VoiceOver announcement *timing/interruption behavior on a real device*
is **not verified**, only the source-level logic that decides what gets
spoken and when.

## Sonuç

Koşullu onay. The Frame Coach architecture (Vision face detection →
`FrameAnalysis` → `FrameCoachingEngine` rule waterfall → `SpeechCuePlayer`
dedupe/throttle → VoiceOver/`AVSpeechSynthesizer` output, plus an independent
spatial-audio side channel) is coherent and already has meaningfully
sophisticated debounce logic purpose-built for blind users (3-frame face-loss
tolerance, a 3-second "locked to good" suppression window, subject-count-change
bypass). It is not code that needs a rewrite. But there are concrete
correctness/consistency defects (dead code paths, two different "no face"
strings, string-equality used as a semantic signal in three places) and real
gaps against current Apple accessibility capabilities that should be
addressed before calling this feature "done" for blind users specifically.

## Kritik bulgular

1. **Inconsistent "no face" announcement text (accessibility-facing, high
   priority).** Three different code paths speak three different strings for
   what a user experiences as the same event:
   - `CaptureCoachingEngine.swift` (nil `frameAnalysis`): `"Yüz algılanamıyor, kameraya bak"`.
   - `FrameCoachingEngine.swift` (low-confidence/no-face guard): the same
     `"Yüz algılanamıyor, kameraya bak"`, defined as a separate literal.
   - `RecorderViewModel.swift` (after 3 consecutive nil analyses,
     `currentFrameCoachInstruction = "Yüz algılanamıyor"`): a **shorter**
     string missing the `"kameraya bak"` ("look at the camera") actionable
     suffix.
   For a sighted user this is a cosmetic inconsistency; for a blind user
   relying entirely on the spoken phrase for what to do next, the version
   that drops the actionable instruction is the one that actually reaches
   them after brief face loss (the 3-miss debounce path), which is the more
   common real-world case (user shifts, phone moves). Recommend one shared
   constant/string used by all three sites.

2. **`FrameCoachingEngine`'s low-confidence guard is dead code.**
   `FrameAnalysisService.analyze` hardcodes `confidence: 0.9` for every
   analysis it produces and only ever builds a `FrameAnalysis` when at least
   one face was found — so the guard `analysis.confidence > 0.3,
   analysis.faceCount > 0` at `FrameCoachingEngine.swift:14` can never fail in
   production. This suggests `confidence` was meant to come from Vision's
   real per-detection confidence and the wiring was never finished. Low
   priority for behavior today (harmless dead code) but worth fixing before
   trusting "confidence" as a future gating mechanism — right now a genuinely
   low-confidence, borderline face detection is coached with full confidence
   as if it were certain, which could produce a confusing "kadraj uygun"
   announcement for a frame the model barely detected a face in.

3. **The entire `.advisory` distance-severity branch in
   `FrameCoachingEngine.distanceInstruction` is unreachable.** Every profile's
   `.one`-subject case sets `advisoryWidthThreshold`/`advisoryHeightThreshold`
   to `nil`, and the `.two`/`.three` cases never populate an advisory branch
   at all — so the "soft" distance nudge this code appears designed to
   produce never fires for any subject count or profile. Either finish this
   (soft nudges before the "severe" too-close/too-far message would likely
   *reduce* unnecessary sudden hard corrections, which is directly relevant
   to the "gereksiz rastgele tekrarlar" question below) or remove the dead
   branch.

4. **"Is this the balanced/good state" is inferred by localized-string
   equality in three independent places**, not from a structured signal
   returned by `FrameCoachingEngine`:
   - `RecorderViewModel.swift`: `guidance == String(localized: "kadraj uygun")
     || guidance == String(localized: "kadraj dengeli")`.
   - `FrameCoachSpatialCueResolver.swift`: a similar lowercase string
     comparison for `confirmsCentered`.
   This is fragile — any future wording tweak to `FrameCoachingEngine`'s
   balanced-state strings silently breaks the "locked to good" 3-second
   suppression window, the periodic reassurance repeat-shortening, and the
   spatial-cue "confirms centered" tone, with no compiler warning. For an
   accessibility-critical suppression mechanism, this should be a typed
   result (e.g. `FrameCoachInstruction { text, isBalanced }`) rather than a
   string comparison.

5. **Multi-person (2–3) coverage is real but has an untested gap: the
   `.three` path and the two-person "overlap"/"scale imbalance" rules have no
   direct test coverage.** `RecorderViewModelFrameCoachTests.swift` exercises
   `.one` and `.two` subject counts (including automatic profile switching
   for horizontal vs. vertical two-person framing) but never constructs a
   3-person `FrameAnalysis`, and never drives `overlapInstruction` (`"%@
   arkada kalmış, biraz yana açılsın"`) or `scaleImbalanceInstruction` (`"%@
   kameraya daha yakın, biraz geri gelsin"`) — both of which name a specific
   person via `FrameSubjectRole.label` (`"soldaki kişi"`/`"sağdaki kişi"`/
   `"ortadaki kişi"`) and are exactly the kind of rule a blind user filming
   two people would most need verified as unambiguous and not misfiring.
   Given the user's explicit question about "bir kişi iki kişi olunca gerekli
   tüm tedbirler alınmış mı," the *design* answer is yes (extensive
   count-aware branching exists — see `plan.md`/brief §3 in the shared
   scope), but the *verification* answer is currently incomplete for 3 people
   and for the two most name-specific 2-person rules.

6. **`isHardFrameCoachInstruction`'s English keyword list
   (`RecorderViewModel.swift`) likely never matches anything.** Every
   guidance string actually produced by `FrameCoachingEngine`/
   `CaptureCoachingEngine` in the read source is a Turkish literal (e.g.
   `"çok yakınsın, biraz uzaklaş — omuzların ve göğsün de görünsün"`,
   `"Çok uzaktasınız, ikiniz de biraz yaklaşın"`). The English substrings
   guarded for (`"not fully in frame"`, `"further back"`, `"closer to the
   camera"`, `"too close"`, `"too far"`) do not correspond to any string
   literal found in these files. **Doğrulanamadı**: whether `String(localized:)`
   resolves to these English phrases under an English system locale via a
   `.xcstrings`/`.strings` catalog was not checked (no localization catalog
   was read in this pass) — if it does not, the "hard instruction" gate
   silently fails to protect English-locale users from the "locked to good"
   suppression swallowing a genuinely urgent too-close/too-far correction.
   This should be confirmed against the actual localization catalog before
   release.

## Onaylanan kararlar

- The debounce architecture is well-reasoned for a blind-user audience
  specifically, not generic UX polish: the code's own Turkish comments state
  the intent explicitly — 3-consecutive-miss tolerance before announcing
  face loss ("Yüz kaybolunca kısa aralıkla tekrar et (2s) — kör kullanıcı
  hızlıca uyarılmalı"), and the 3-second "locked to good" window ("3 saniye:
  kör kullanıcı pozisyon değişikliğini hızlıca öğrenmeli"). These are
  reasonable, deliberately-tuned values, not arbitrary magic numbers.
- Subject-count changes are correctly treated as unconditionally
  announcement-worthy (bypassing the "locked good" suppression), which is
  the right call — a blind user needs to know immediately when a second
  person enters frame regardless of whether the current framing already
  reads as "good."
- The periodic "still in good position" reassurance repeat (forced 2s
  interval while `isGood`) is a sound design choice for a user who has no
  visual confirmation that nothing has silently gone wrong.
- Automatic profile switching (`automaticFrameCoachingProfile`) based on both
  subject count and recording mode/preset (desk speaker vs. two-person
  podcast vs. vertical conversation vs. screen-guide) is a reasonable and
  already fairly thorough design surface, not something that needs
  architectural rework.

## Riskli varsayımlar

- It is assumed (not verified in this pass) that `String(localized:)` for the
  guidance strings resolves correctly and *distinctly* for whatever
  additional languages the app ships (the English keyword list in
  `isHardFrameCoachInstruction` implies at least English is expected) — see
  Kritik bulgu 6. If unverified, silent behavior differences between locales
  are possible specifically in the accessibility-critical "hard instruction"
  gate.
- It is assumed that `VNDetectFaceRectanglesRequest`-based face detection
  (capped to top-3 by area in `FrameAnalysisService`) is an adequate proxy
  for "how many people are in frame" for this feature's purposes. This
  reviewer did not verify behavior with occluded faces, profile/side-facing
  faces, or more than 3 people in frame (a 4th+ person is silently dropped
  from `subjectCount` entirely, which could cause the coach to describe a
  4-person scene as if only 3 people were present) — flagged as
  **doğrulanamadı** without a live camera/simulator session.
- It is assumed the hardcoded `confidence: 0.9` in `FrameAnalysisService` is
  intentional placeholder behavior rather than an oversight; no code comment
  clarifies which. Given Kritik bulgu 2, this is worth an explicit decision
  either way rather than leaving it ambiguous.
- Real end-to-end VoiceOver announcement behavior (interruption vs. queueing
  when `NSAccessibility.post(..., priority: .high)` fires while VoiceOver is
  already speaking something else, e.g. system UI) was **not verified** on
  device/simulator in this review pass — this matters directly for the
  user's "yönlendirme anlaşılır mı" question, since overlapping/interrupted
  announcements would be a real source of confusion that static code reading
  cannot detect.

## Doğrulama listesi

- [ ] Confirm on a real VoiceOver-enabled device/simulator session whether
  overlapping announcements (Frame Coach speech vs. `RecordingElapsedTimeAnnouncer`'s
  30s elapsed-time announcement vs. system VoiceOver chatter) ever step on
  each other or get dropped/queued unpredictably — **doğrulanamadı** in this
  pass (no device/simulator access exercised).
- [ ] Confirm whether `isHardFrameCoachInstruction`'s English keyword list
  actually matches real localized runtime strings (check the `.xcstrings`/
  localization catalog) — **doğrulanamadı** in this pass.
- [ ] Add or confirm test coverage for the `.three` subject-count path and
  for `overlapInstruction`/`scaleImbalanceInstruction` directly (currently
  only reachable indirectly and untested per `RecorderViewModelFrameCoachTests.swift`
  as read).
- [ ] Verify with a 4th person deliberately in frame whether the silent
  cap-at-3 behavior in `FrameAnalysisService` (`prefix(3)`) produces a
  misleading "Üç kişi görünüyor" announcement that a blind user could not
  otherwise catch, since they cannot see the omitted 4th face.
- [ ] Decide and document whether `FrameAnalysisService.confidence` should
  be wired to Vision's real detection confidence or removed as a field if
  it will remain a constant.

## Önerilen plan düzeltmeleri

This task has no implementation plan (review-only per `brief.md`/`plan.md`),
so the following are suggested *follow-up work items* for a future
implementation task rather than plan edits to this task:

1. Unify the three "no face" strings into a single shared constant so the
   phrase a user hears is identical regardless of which code path detected
   the missing face; keep the actionable `"kameraya bak"` suffix in all
   cases (see Kritik bulgu 1).
2. Replace the localized-string-equality "is balanced" checks in
   `RecorderViewModel` and `FrameCoachSpatialCueResolver` with a typed field
   returned by `FrameCoachingEngine` (e.g. `isBalanced: Bool` alongside the
   text), removing a fragility that currently spans two files and an
   accessibility-critical suppression window (Kritik bulgu 4).
3. Either wire real per-detection confidence into `FrameAnalysisService` or
   remove the now-dead low-confidence guard and the unreachable `.advisory`
   distance branch in `FrameCoachingEngine`, so the code doesn't carry logic
   that looks load-bearing but cannot execute (Kritik bulgu 2, 3).
4. Add direct unit tests for `.three` subject count and for
   `overlapInstruction`/`scaleImbalanceInstruction`, and consider a
   dedicated test target for `FrameCoachingEngine`/`FrameCoachSpatialCueResolver`
   in isolation rather than only exercising them indirectly through
   `RecorderViewModel` (Kritik bulgu 5).
5. As a genuinely new capability worth scoping separately (this is a
   forward-looking suggestion, not a defect): evaluate Apple's newer
   accessibility-relevant APIs for this feature specifically —
   `AXSpeechAttendedSpeaker`/Personal Voice for a more natural announcement
   voice, System-level Live Speech/Sound Recognition as a secondary
   confirmation channel, and richer `AVSpeechSynthesizer` SSML-like pacing
   controls — none of which are currently used; the app instead relies
   entirely on `NSAccessibility.post(.announcementRequested)` and a plain
   `AVSpeechSynthesizer.speak` at a fixed `rate = 0.45`. This is an
   opportunity area, not a current defect.
