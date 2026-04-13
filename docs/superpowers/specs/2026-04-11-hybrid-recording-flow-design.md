# Hybrid Recording Flow Design

**Context**

The recorder now reliably starts, stops, and exports a single `.mp4`, but the daily-use flow still feels fragile. Users can lose confidence around three moments: while recording, while export is finishing, and immediately after save completes.

**Product Direction**

The app should be hybrid:

- The main window remains the setup surface for presets, sources, permissions, and preferences.
- The menu bar becomes the daily-use control surface.
- Recording completion becomes a first-class moment with explicit next actions.

**Goals**

- Make it obvious whether recording is active, stopping, saving, or finished.
- Make the last recording easy to open, reveal, rename, or move.
- Keep the default flow fast while allowing one-off overrides.
- Preserve the current reliable recording/export path.

**Experience**

1. The app launches with its main window and a persistent menu bar item.
2. The menu bar item always exposes at least:
   - Start/Stop recording
   - Show main window
   - Open last recording
   - Reveal last recording in Finder
   - Open settings
   - Quit
3. The menu bar icon pulses while recording and uses a calmer idle icon otherwise.
4. Closing the main window does not terminate the app; the menu bar item keeps the app available.
5. When recording finishes successfully, the app shows a compact completion sheet in the main window.
6. The completion sheet offers:
   - Open
   - Show in Finder
   - Rename
   - Save As
   - Close
7. Recordings still receive automatic timestamped names by default.
8. Users can set a default output folder in Settings.
9. Users can still override the final destination for a single recording through Save As.

**Behavior Rules**

- The global shortcut should only toggle recording state. It should not hide windows or trigger extra navigation.
- Export progress should be visible through status text and not silently fail.
- Failed exports should not leave misleading partial `.mp4` files behind.
- The completion sheet should only appear for successful exports.
- Rename updates the existing saved file in place.
- Save As moves the saved file to the newly chosen destination and updates the app’s “last recording” pointer.

**Technical Approach**

- Extend `RecorderViewModel` with completion-sheet state and output-directory preference handling.
- Make `RecordingFileNamer` configurable from a stored output directory instead of assuming `~/Movies/Video Recorder`.
- Evolve `MenuBarController` from recording-only presence to an always-available status item with dynamic menu items.
- Keep file operations in the view model and inject panel/open/reveal behaviors for testability.

**Non-Goals For This Slice**

- Recording history browser
- Named presets
- Per-recording metadata database
- Background upload or share integrations
