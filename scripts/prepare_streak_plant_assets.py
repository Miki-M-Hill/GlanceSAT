#!/usr/bin/env python3
"""Remove near-white backgrounds and export streak plant PNGs for Xcode asset catalogs."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip3 install pillow", file=sys.stderr)
    raise

CANVAS = 1024
WHITE_THRESHOLD = 245
FEATHER = 12  # soften edge against white removal
CONTENT_PADDING_RATIO = 0.06


def remove_white_background(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            brightness = max(r, g, b)
            whiteness = min(r, g, b)
            if brightness >= WHITE_THRESHOLD and (brightness - whiteness) < 18:
                pixels[x, y] = (r, g, b, 0)
                continue
            if brightness >= WHITE_THRESHOLD - FEATHER:
                t = (brightness - (WHITE_THRESHOLD - FEATHER)) / max(FEATHER, 1)
                new_a = int(a * (1.0 - min(1.0, max(0.0, t))))
                pixels[x, y] = (r, g, b, new_a)

    return rgba


def trim_and_center(image: Image.Image, canvas: int = CANVAS) -> Image.Image:
    alpha = image.split()[-1]
    bbox = alpha.getbbox()
    if not bbox:
        return Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))

    cropped = image.crop(bbox)
    pad = int(max(cropped.size) * CONTENT_PADDING_RATIO)
    padded_w = cropped.width + pad * 2
    padded_h = cropped.height + pad * 2
    padded = Image.new("RGBA", (padded_w, padded_h), (0, 0, 0, 0))
    padded.paste(cropped, (pad, pad), cropped)

    scale = min(canvas / padded_w, canvas / padded_h)
    target_w = max(1, int(padded_w * scale))
    target_h = max(1, int(padded_h * scale))
    resized = padded.resize((target_w, target_h), Image.Resampling.LANCZOS)

    canvas_img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    offset = ((canvas - target_w) // 2, (canvas - target_h) // 2)
    canvas_img.paste(resized, offset, resized)
    return canvas_img


def process(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    image = Image.open(source)
    processed = trim_and_center(remove_white_background(image))
    processed.save(destination, format="PNG", optimize=True)
    print(f"Wrote {destination} ({processed.size[0]}x{processed.size[1]})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("destination")
    args = parser.parse_args()
    process(Path(args.source), Path(args.destination))


if __name__ == "__main__":
    main()
