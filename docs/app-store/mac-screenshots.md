# Mac App Store screenshot workflow

FrameMate uses a repeatable screenshot workflow so Turkish and English store assets stay consistent.

## Output

- Size: 2880 x 1800 pixels
- Aspect ratio: 16:10
- Format: PNG
- Locales: `tr`, `en-US`
- Destination: `fastlane/screenshots/<locale>/`

## Raw screenshots

Place raw macOS app captures in:

```text
fastlane/screenshots_raw/mac/
```

Use these file keys:

```text
01_Record_Everything.png
02_Presentations_Lessons.png
03_Flexible_Modes.png
04_Frame_Coach.png
05_Customize_Settings.png
06_Preview_Save.png
```

The raw screenshots can be any practical Mac window capture. The styling script crops them into a consistent App Store canvas.

## Generate store screenshots

```sh
ruby fastlane/scripts/style_mac_store_screenshots.rb \
  --input fastlane/screenshots_raw/mac \
  --output fastlane/screenshots \
  --locales tr,en-US
```

For a quick single-screen check:

```sh
ruby fastlane/scripts/style_mac_store_screenshots.rb \
  --input fastlane/screenshots_raw/mac \
  --output fastlane/screenshots \
  --locales tr,en-US \
  --screens 01_Record_Everything
```

## Public screenshot copy

The text is stored in:

```text
fastlane/scripts/mac_store_screenshot_copy.json
```

The public App Store screenshots should not show the purchase screen. If in-app purchases are used, prepare the paywall screenshot separately for App Store Connect review metadata.
