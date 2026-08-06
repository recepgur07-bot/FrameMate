# FrameMate ASO iteration

## Scope

- Locales: `en-US`, `tr`
- App version: `1.0`
- Candidate build context: `202608041156`
- Screenshots: unchanged in this iteration
- Measurement window: starts after metadata publication; compare 7/14/30 days

## Baseline and change set

| Field | English | Turkish |
|---|---|---|
| Name | `FrameMate: Screen Recorder` (unchanged) | `FrameMate: Ekran Kaydedici` (unchanged) |
| Subtitle | `Screen, Camera & System Audio` | `Ekran, Kamera ve Sistem Sesi` |
| Keywords | `webcam,window,screencast,tutorial,demo,podcast,voiceover,cursor,framing,microphone,system audio` | `webcam,pencere,screencast,sunum,demo,eğitim,voiceover,kadraj,imleç,anlatım,podcast,sistem sesi` |
| Description | Expanded from 1,815 to 2,904 characters | Expanded from 1,795 to 2,919 characters |
| Promotional text | Expanded from 133 to 155 characters | Expanded from 116 to 139 characters |
| Release notes | Expanded from 279 to 425 characters | Expanded from 267 to 413 characters |

## Why these changes

- The first description now follows a feature-to-use-case structure: recording modes, explanation tools, Frame Coach, workflow settings, accessibility, privacy, and Pro access.
- Settings that were real but invisible in the old description are now named: countdown, duration cap, end warning, audio channel, event sounds, elapsed announcements, window behavior, Dock/menu bar mode, launch at login, output folder, Quick Help, and keyboard shortcuts.
- Accessibility language uses concrete claims—VoiceOver, keyboard use, live announcements, spoken framing guidance, and the conditional Accessibility permission—instead of an untestable “fully accessible” promise.
- Keyword clusters prioritize intent without duplicating the localized app name: screen-recording workflows, camera/window capture, tutorials and demos, audio, VoiceOver, cursor guidance, and framing.
- Screenshots were deliberately left unchanged so the next iteration can align screenshot headlines with these metadata clusters separately.

## Character and byte checks

- Apple limits used for this candidate: name/subtitle `30` characters, promotional text `170` characters, description `4000` characters, keywords `100` bytes.
- English: subtitle `29`, keywords `95` bytes, description `2904`, promotional text `155`.
- Turkish: subtitle `28`, keywords `97` bytes, description `2919`, promotional text `139`.
- All fields are within the limits; keyword strings use comma-separated clusters without keyword stuffing.

## Outcome metrics

- Impressions: not yet measured
- Product page views: not yet measured
- Conversion to download: not yet measured
- Downloads/proceeds: not yet measured
- Confidence: provisional until the metadata is published and a 7/14/30-day baseline exists

## Decision

- Published on `2026-08-04` with Fastlane `store_metadata skip_screenshots:true`; screenshots were not uploaded or replaced, and App Review was not submitted.
- App Store Connect read-back confirmed both localized descriptions, keywords, promotional text, support/privacy URLs, subtitles, and 3,932-character review notes. The existing version remains in its prior `REJECTED` edit state; no submission action was taken.
- Next hypothesis: richer feature coverage and clearer accessibility/privacy positioning should improve qualified product-page visits, while the new subtitle and keyword clusters improve discovery for screen, camera, audio, and accessible recording intent.
