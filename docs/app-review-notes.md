# App Review Notes

FrameMate is a native macOS screen, camera, and audio recorder. It is designed for local recording workflows, with extra accessibility support for blind and low-vision creators.

No account is required. The app does not upload recordings, does not include advertising SDKs, and does not include analytics or tracking SDKs. Recordings are saved locally on the user's Mac.

Permissions used by the app:

- Camera: used for camera recording, camera overlay, and Frame Coach guidance.
- Microphone: used for microphone audio recording.
- Screen Recording: used for full screen and window recording, and for system audio capture where available.
- Speech: used for spoken Frame Coach guidance.

The app does not request the Accessibility (AX) permission. VoiceOver support is provided through the standard macOS accessibility APIs that require no extra permission.

During recording, FrameMate shows an active recording state in the main window and a menu bar status item. The menu bar item uses a red recording symbol while recording and exposes recording status and duration in its menu.

Recording storage (Guideline 2.4.5(i)): recordings are saved to the user-visible `~/Movies/Video Recorder` folder by default (via the `com.apple.security.assets.movies.read-write` entitlement), never to a hidden app container. Users can change the default folder from Settings with a standard folder picker, and every completed recording offers a standard Save dialog ("Save As"), rename, and "Show in Finder" actions. Custom folders are persisted with security-scoped bookmarks. Note: the default folder is named "Video Recorder" (the app's bundle name), while the marketing name of the app is FrameMate.

In-app purchases: FrameMate Pro is offered as a yearly auto-renewable subscription (with an introductory free trial where eligible) and a lifetime one-time purchase. Both can be bought from the paywall that appears when starting a recording without an active entitlement, and from Settings. The paywall includes Restore Purchases, the privacy policy link, and the Terms of Use (Apple standard EULA) link.

The support and privacy policy URLs are:

- Support: https://recepgur07-bot.github.io/oneday-support/framemate-support
- Privacy Policy: https://recepgur07-bot.github.io/oneday-support/framemate-privacy

Suggested reviewer flow:

1. Launch FrameMate.
2. Complete onboarding.
3. Grant the permissions needed for the recording mode being tested.
4. Test one short camera or screen recording.
5. Open Settings to review purchase controls, restore purchases, accessibility guidance, and privacy/support links.

