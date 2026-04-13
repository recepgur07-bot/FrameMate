# Frame Coach Design

**Goal**

Add a keyboard-toggleable framing coach that helps blind or low-vision users position 1-3 people for desk-style talking-head videos using continuous spoken guidance.

**Problem**

The current app can capture video, but it does not help the user achieve a publishable composition before recording. For desk videos this means common issues remain unsolved: subjects are too low or too high in frame, there is too much ceiling or table visible, people are off-center, faces are cropped, or a group is too tight or too spread out.

**First Release Scope**

- `Cmd-D` toggles framing coach on and off.
- Coach works before recording and analyzes the live camera preview.
- Coach supports 1, 2, or 3 visible people.
- Coach speaks short Turkish guidance continuously while active.
- Guidance focuses on desk/talking-head composition quality rather than simple face presence.

**Non-Goals**

- Full scene understanding for arbitrary filming situations.
- Product-shot guidance.
- Per-user custom profiles in the first release.
- Background replacement, auto-zoom, or automatic camera movement.

**Recommended Approach**

Use a hybrid approach:

1. Detect up to 3 faces with `Vision`.
2. Derive lightweight composition heuristics from the preview frame:
   - group horizontal centering
   - subject vertical placement
   - headroom
   - estimated subject scale
   - ceiling-heavy frame
   - desk-heavy frame
   - multi-person spacing balance
3. Convert the strongest problem into one short spoken instruction at a controlled cadence.

This is the best fit for the current app because it is device-local, fast enough for live feedback, and strong enough to handle the real desk-video problems the user described without requiring an overbuilt ML system.

**User Experience**

- User presses `Cmd-D` to enable coach mode.
- App announces that framing coach is active.
- While active, the coach analyzes the preview at a modest interval.
- If framing is off, it speaks one instruction such as:
  - "Biraz sola"
  - "Kamerayı biraz aşağı indir"
  - "Biraz uzaklaş"
  - "Tavan fazla görünüyor"
  - "Masa çok görünüyor"
  - "Ortadasınız, kadraj uygun"
- Repeated identical guidance is throttled so it does not become noisy.
- Pressing `Cmd-D` again disables the coach and silences future prompts.

**Architecture**

Split the feature into focused units:

- `FrameAnalysisService`
  - accepts a video frame
  - runs face detection
  - computes composition metrics
  - returns a structured analysis result

- `FrameCoachingEngine`
  - converts analysis into a single highest-priority coaching instruction
  - applies thresholds and repetition throttling

- `FrameCoachViewModelState`
  - stores whether coach mode is active
  - stores the most recent instruction
  - coordinates analysis timing

- `SpeechCuePlayer`
  - speaks coaching instructions
  - suppresses repeated utterances within a cooldown window

- `Preview frame tap`
  - attaches to existing camera preview/capture flow
  - provides frames for analysis without disturbing recording

**Data Flow**

1. Preview frame arrives from capture pipeline.
2. Analysis service detects faces and computes framing metrics.
3. Coaching engine ranks issues by severity.
4. View model updates current coach state.
5. Speech player speaks only if instruction changed or cooldown expired.

**Composition Rules for First Release**

Single person:
- face should be near horizontal center
- eyes/face region should sit slightly above frame center
- moderate headroom
- avoid too much empty top space
- avoid too much visible desk at bottom

Two people:
- group center should align to frame center
- both faces should remain comfortably inside safe margins
- spacing should be balanced
- avoid one person dominating frame scale

Three people:
- group should remain centered
- outside faces should not be too close to frame edges
- subjects should have similar scale when seated at same table

**Feedback Priority**

The coach should speak only the single most important correction at a time. Recommended priority:

1. no face / missing faces
2. subjects cropped or near edge
3. too high / too low framing
4. too close / too far
5. too much ceiling / too much desk
6. lateral centering
7. spacing balance
8. framing is good

**Error Handling**

- If no usable frame is available, say nothing.
- If face detection is unstable for a brief moment, keep last instruction rather than flickering.
- If lighting is too poor to detect faces reliably, emit a sparse fallback instruction such as "Yüz algılanamıyor".

**Testing Strategy**

- unit tests for metric-to-instruction mapping
- unit tests for instruction throttling
- unit tests for 1/2/3-person composition decisions using synthetic analysis inputs
- integration tests for toggle state and command shortcut wiring

**Future Extensions**

- settings for feedback style and cadence
- presets such as single speaker / two-person podcast / three-person desk panel
- optional haptic/audio-tone feedback
- recording-time coach mode
