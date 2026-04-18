# Spatial Frame Coach Audio Design

## Goal

Add an optional spatial audio layer to Frame Coach so users can feel direction through sound while keeping the existing spoken guidance and VoiceOver behavior intact.

## Product Shape

The existing Frame Coach remains the primary feature. Spatial audio becomes a companion mode that can be turned on from Settings.

Recommended first release:

- Spatial direction sound can be off, tone-only, or tone plus speech.
- Horizontal movement is represented by stereo position:
  - move right: cue comes from the right
  - move left: cue comes from the left
  - centered: cue comes from the center
- Vertical movement uses pitch or rhythm:
  - move up: higher short cue
  - move down: lower short cue
- A centered/good frame produces a short centered confirmation cue.
- VoiceOver announcements continue to use the existing accessibility announcement path.

This keeps the feature useful for blind and low-vision users while avoiding a noisy or confusing first version.

## Non-Goals

- Do not replace VoiceOver.
- Do not record coach sounds into the exported video.
- Do not require headphones, though stereo cues will work best with headphones.
- Do not add a full 3D game audio engine in the first release.
- Do not change the current Frame Coach composition rules.

## Architecture

The feature should be added as a separate audio cue layer next to `SpeechCuePlayer`.

Existing flow:

1. Preview frame arrives.
2. `FrameAnalysisService` returns face and framing metrics.
3. `CaptureCoachingEngine` / `FrameCoachingEngine` returns one spoken guidance string.
4. `SpeechCuePlayer` speaks or announces the guidance.

New flow:

1. Preview frame arrives.
2. Existing analysis and spoken guidance continue unchanged.
3. A new direction resolver converts `FrameAnalysis` plus guidance into a structured cue.
4. A new spatial cue player plays short non-speech audio feedback if enabled.

## Components

- `FrameCoachSpatialAudioMode`
  - User preference for off, tones only, or tones plus speech.

- `FrameCoachSpatialCue`
  - Structured value describing cue direction, severity, and centered state.

- `FrameCoachSpatialCueResolver`
  - Converts `FrameAnalysis`, selected mode, and final guidance into a cue.
  - Should be deterministic and heavily unit tested.

- `SpatialCuePlaying`
  - Protocol for cue playback.

- `SpatialCoachCuePlayer`
  - Plays short generated tones with stereo pan and pitch variation.
  - Owns cooldown and dedupe logic for non-speech cues.

- Settings storage additions
  - Persist spatial mode, cue style if added, and center confirmation preference.

## Cue Rules

For the first release, prefer simple and predictable cues:

- Strong left/right offset plays a cue panned hard toward the side the user should move.
- Mild left/right offset plays a quieter or softer cue panned partially toward that side.
- Centered/good guidance plays a short centered confirmation cue.
- Vertical correction uses pitch:
  - move up: higher pitch
  - move down: lower pitch
- Critical spoken states like no face, low light, clipped subject, and missing permissions should not spam spatial tones.

If one frame has both horizontal and vertical problems, the cue should follow the spoken guidance priority instead of playing multiple directions at once.

## Settings

Add controls under the existing `Erişilebilirlik ve Yönlendirme` section:

- `Yön sesi`
  - `Kapalı`
  - `Sadece yön sesi`
  - `Yön sesi ve konuşma`

- `Merkez onayı`
  - enabled by default
  - plays when the coach reaches a good frame after a correction

Optional later:

- `Ses karakteri`
  - soft
  - clear
  - low tone
  - high tone

## Accessibility

Spatial audio must not bypass the existing VoiceOver-friendly path. VoiceOver users can keep `Yönlendirme sesi` in automatic or VoiceOver mode while also enabling the non-speech direction cue.

The app should avoid fast repetitive cues. The user should be able to silence spatial cues without silencing spoken guidance.

## Testing

Unit tests should cover:

- Settings defaults and persistence.
- Cue resolver returns left/right/center for synthetic analyses.
- Cue resolver respects critical states where tone should be suppressed.
- Center confirmation only plays after entering a good state.
- Speech-only behavior remains unchanged when spatial mode is off.

Manual tests should cover:

- Built-in speakers.
- Headphones.
- VoiceOver on and off.
- Turkish system voice availability.
- Frame Coach enabled before recording and in screen-camera overlay mode.

## Recommended Rollout

Build this in two phases:

1. Add the model, resolver, settings, tests, and a silent/mock player path.
2. Add real AVFoundation tone playback and wire it into the Frame Coach loop.

This lets the feature land safely after the current code testing work finishes.
