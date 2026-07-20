# ASC App Review Reply Draft (EN)

To be pasted as a reply to the rejection message in App Store Connect after the new build is uploaded. Requires explicit user approval before sending.

---

Hello,

Thank you for the detailed feedback. We have addressed both issues from the previous reviews in the new build:

1. Guideline 2.4.5(i) — Recording storage. Recordings are no longer saved to the app container. By default, every recording is saved to the user-visible `~/Movies/Video Recorder` folder (using the `com.apple.security.assets.movies.read-write` entitlement). Users can change the destination folder in Settings via the standard folder picker (NSOpenPanel), and each completed recording also offers a standard Save dialog ("Save As"), rename, and "Show in Finder" actions. Custom folders are persisted with security-scoped bookmarks.

2. Guideline 5.1.1(ii) — Microphone purpose string. The microphone purpose string now clearly explains the use and includes a concrete example, in both English and Turkish: the microphone is used to add narration audio to screen recordings and to create audio-only recordings, for example when recording a lesson, demo, meeting note, or podcast draft.

Additional notes for this build:
- In-app purchases are enabled and visible to reviewers (the internal-testing flag that previously hid them is off).
- The paywall now includes Restore Purchases, the privacy policy link, and the Terms of Use (Apple standard EULA) link.

Please let us know if anything else needs attention. Thank you!

---

# Review Notes alanı için güncel metin

docs/app-review-notes.md dosyasının son hali ASC "App Review Information > Notes" alanına yapıştırılacak.
