#!/usr/bin/env python3
"""Build Mac App Store screenshots with reliable Unicode text rendering."""

from __future__ import annotations

import argparse
import json
import shutil
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "screenshots"
DEFAULT_COPY = ROOT / "scripts" / "mac_store_screenshot_copy.json"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/System/Library/Fonts/Supplemental/Helvetica.ttc"),
        Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default(size=size)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    out = Image.new("RGBA", image.size)
    out.paste(image.convert("RGBA"), (0, 0), mask)
    return out


def resize_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_w, target_h = size
    scale = max(target_w / image.width, target_h / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


def resize_contain(image: Image.Image, size: tuple[int, int], fill: str = "white") -> Image.Image:
    target_w, target_h = size
    scale = min(target_w / image.width, target_h / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    out = Image.new("RGB", size, fill)
    out.paste(resized, ((target_w - resized.width) // 2, (target_h - resized.height) // 2))
    return out


def draw_wrapped(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, fill: str, fnt: ImageFont.FreeTypeFont, width_px: int, line_gap: int = 12) -> int:
    words = text.split()
    lines: list[str] = []
    current = ""
    for word in words:
        proposed = f"{current} {word}".strip()
        if draw.textbbox((0, 0), proposed, font=fnt)[2] <= width_px:
            current = proposed
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)

    x, y = xy
    for line in lines:
        draw.text((x, y), line, font=fnt, fill=fill)
        bbox = draw.textbbox((x, y), line, font=fnt)
        y = bbox[3] + line_gap
    return y


def build_one(raw_path: Path, output_path: Path, title: str, subtitle: str, sequence: str, canvas: tuple[int, int]) -> None:
    cw, ch = canvas
    bg = Image.new("RGB", canvas, "#F6F8FB")
    draw = ImageDraw.Draw(bg)
    draw.rectangle((0, round(ch * 0.70), cw, ch), fill="#E7EDF6")
    draw.ellipse((round(cw * 0.76), -120, round(cw * 1.09), round(ch * 0.28)), fill="#DDE7F5")
    draw.ellipse((-210, round(ch * 0.70), round(cw * 0.25), round(ch * 1.10)), fill="#E9F1EA")

    raw = Image.open(raw_path).convert("RGB")
    shot_size = (2180, 1226)
    raw_ratio = raw.width / raw.height
    target_ratio = shot_size[0] / shot_size[1]
    if raw_ratio > target_ratio * 1.12:
        shot_image = resize_contain(raw, shot_size)
    else:
        shot_image = resize_cover(raw, shot_size)
    shot = rounded(shot_image, 34)

    shadow = Image.new("RGBA", (shot_size[0] + 130, shot_size[1] + 130), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle((65, 65, 65 + shot_size[0], 65 + shot_size[1]), radius=36, fill=(22, 34, 52, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))

    composed = bg.convert("RGBA")
    composed.alpha_composite(shadow, (285, 455))
    composed.alpha_composite(shot, (350, 470))

    draw = ImageDraw.Draw(composed)
    title_font = font(92, bold=True)
    subtitle_font = font(42)
    badge_font = font(30, bold=True)

    badge = Image.new("RGBA", (286, 76), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(badge)
    bdraw.rounded_rectangle((0, 0, 285, 75), radius=24, fill="#1F7A68")
    badge_text = f"FRAMEMATE {sequence}"
    bbox = bdraw.textbbox((0, 0), badge_text, font=badge_font)
    bdraw.text(((286 - (bbox[2] - bbox[0])) // 2, (76 - (bbox[3] - bbox[1])) // 2 - 2), badge_text, font=badge_font, fill="white")
    composed.alpha_composite(badge, (350, 132))

    title_bottom = draw_wrapped(draw, (350, 222), title, "#122033", title_font, 1760, 10)
    subtitle_y = max(370, title_bottom + 18)
    draw_wrapped(draw, (350, subtitle_y), subtitle, "#42526A", subtitle_font, 1680, 10)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    composed.convert("RGB").save(output_path, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", default=DEFAULT_OUTPUT, type=Path)
    parser.add_argument("--locales", default="tr,en-US")
    parser.add_argument("--copy", default=DEFAULT_COPY, type=Path)
    parser.add_argument("--screens", default="")
    args = parser.parse_args()

    data = json.loads(args.copy.read_text(encoding="utf-8"))
    canvas = (data["canvas"]["width"], data["canvas"]["height"])
    screens = data["screens"]
    wanted = [item.strip() for item in args.screens.split(",") if item.strip()]
    if wanted:
        screens = [screen for screen in screens if screen["key"] in wanted]

    locales = [item.strip() for item in args.locales.split(",") if item.strip()]
    for locale in locales:
        locale_dir = args.output / locale
        if locale_dir.exists():
            shutil.rmtree(locale_dir)
        locale_dir.mkdir(parents=True, exist_ok=True)

        for screen in screens:
            key = screen["key"]
            matches = sorted(args.input.glob(f"*{key}*.png"))
            if not matches:
                raise SystemExit(f"Eksik ham ekran goruntusu: {key}")
            localized = screen["locales"][locale]
            sequence = key[:2]
            build_one(
                matches[0],
                locale_dir / f"Mac-{key}.png",
                localized["title"],
                localized["subtitle"],
                sequence,
                canvas,
            )

    print(f"Olusturulan ekran goruntusu: {len(locales) * len(screens)}")


if __name__ == "__main__":
    main()
