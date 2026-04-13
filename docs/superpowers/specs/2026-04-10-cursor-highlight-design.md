# Cursor Highlight Design

## Goal

Add a Screen Studio-style cursor highlight for screen and window recordings so the pointer is easier to follow in exported videos.

## Scope

This first slice covers:

- Screen and window recording modes only
- A new `Imleci vurgula` toggle
- Default state: off
- A soft spotlight that follows the pointer in the exported video
- Short pulse rings on mouse clicks

This slice does not cover:

- Live preview of the cursor effect
- Keyboard shortcut overlays
- Auto zoom / focus
- Intelligent content-aware pointer avoidance

## User Experience

When the user is in a screen or window preset, they can enable `Imleci vurgula`.

If enabled:

- The recorded/exported video keeps the normal captured cursor
- A soft spotlight sits behind the pointer
- Left/right/other mouse down events create a short pulse ring

If disabled:

- Export behaves exactly as it does today

## Architecture

### 1. Cursor timeline capture

Add a dedicated cursor tracker that runs only while a screen/window recording is active.

It collects:

- Timestamped cursor samples
- Timestamped click events

Samples are stored in normalized coordinates relative to the selected capture target:

- display frame for screen recording
- window frame for window recording

This keeps the timeline reusable for both horizontal and vertical exports.

### 2. Geometry support in screen options

`ScreenDisplayOption` and `ScreenWindowOption` should carry the capture frame geometry needed to normalize cursor coordinates.

These geometry fields are internal implementation details and do not need to be surfaced in the UI labels.

### 3. Export decoration

Extend the screen export composition builder so it can optionally add cursor decoration layers on top of the rendered video.

The decoration layer should include:

- one spotlight layer animated along the cursor path
- one pulse layer per click event

The existing camera overlay border/shadow decoration should continue to work and share the same animation tool.

## Visual Rules

- Spotlight color: soft warm yellow/white with low opacity
- Spotlight size: modest, large enough to guide attention without hiding UI
- Click pulse: short expanding ring, visible but restrained
- No cursor decoration should be rendered outside the captured target bounds

## Error Handling

- If cursor tracking cannot start, recording should continue without the effect
- If no cursor samples are captured, export should fall back to the current undecorated behavior
- If the selected display/window geometry is missing, cursor tracking remains off for that recording

## Testing

Add tests for:

- default toggle state is off
- display/window geometry is preserved in screen source options
- cursor samples convert into correct render-space points
- click events produce extra decoration layers
- disabled cursor highlight keeps current export behavior
