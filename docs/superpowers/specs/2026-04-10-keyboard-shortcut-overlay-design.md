# Keyboard Shortcut Overlay Design

## Goal

Add a Screen Studio-style keyboard shortcut overlay for screen and window recordings so exported videos can briefly show meaningful shortcut combinations.

## Scope

This first slice covers:

- Screen and window recording modes only
- A new `Klavye kisayollarini goster` toggle
- Default state: off
- Short-lived on-video cards for meaningful shortcuts

This slice does not cover:

- Plain text typing
- Shortcut overlay live preview
- Per-app shortcut dictionaries
- Keyboard overlay for camera-only recordings

## User Experience

When the user enables the shortcut overlay in a screen or window preset:

- qualifying shortcut presses appear as a compact card near the bottom center
- each card remains visible for a short duration, then fades out
- repeated shortcuts continue to appear one by one

If disabled:

- export behaves exactly as it does today

## Qualification Rules

The first version should only show shortcut-like input:

- combinations containing `Command`, `Control`, or `Option`
- combinations may also include `Shift`

It should not show:

- plain text typing
- standalone letters and digits
- modifier-only key presses

## Architecture

### 1. Shortcut timeline capture

Add a dedicated keyboard shortcut tracker for screen and window recordings.

It records:

- timestamped shortcut events
- already-formatted display labels such as `⌘ K`, `⌘ ⇧ 4`, `⌃ ⌥ Space`

### 2. Export decoration

Extend the existing screen export decoration pipeline so it can render shortcut cards alongside:

- camera overlay decoration
- cursor highlight decoration

The shortcut card should use a simple shared style:

- dark translucent background
- light text
- rounded corners

## Visual Rules

- bottom-center placement
- compact card with comfortable padding
- fade in quickly, fade out smoothly
- only one card per captured shortcut event

## Error Handling

- If keyboard monitoring cannot start, recording continues normally
- If no shortcut events are captured, export stays unchanged

## Testing

Add tests for:

- default toggle state is off
- shortcut formatter keeps only shortcut-like combinations
- screen recording starts and stops the keyboard tracker when enabled
- export decoration creates layers for captured shortcut events
