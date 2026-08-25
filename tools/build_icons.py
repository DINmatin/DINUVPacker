from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw


YELLOW = (255, 210, 28)
CYAN = (0, 199, 232)
CHARCOAL = (27, 30, 33)


def classify(rgb: tuple[int, int, int]) -> tuple[tuple[int, int, int], int]:
    r, g, b = rgb
    maximum = max(rgb)
    minimum = min(rgb)
    saturation = 0.0 if maximum == 0 else (maximum - minimum) / maximum

    # The generated source contains a baked light checkerboard. Low-saturation
    # bright pixels belong to that background. Preserve a soft antialiased edge
    # for darker neutral pixels around the charcoal silhouette.
    if saturation < 0.16 and minimum > 205:
        return CHARCOAL, 0
    if saturation < 0.16 and minimum > 120:
        alpha = max(0, min(255, round((205 - minimum) / 85 * 255)))
        return CHARCOAL, alpha
    if b > r * 1.25 and b > g * 1.05:
        return CYAN, 255
    if r > 150 and g > 90 and b < 150:
        return YELLOW, 255
    return CHARCOAL, 255


def flatten_source(source: Path) -> Image.Image:
    image = Image.open(source).convert("RGB")
    output = Image.new("RGBA", image.size)
    output.putdata([(*color, alpha) for color, alpha in map(classify, image.getdata())])
    alpha = output.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise RuntimeError("Icon segmentation produced an empty image")
    cropped = output.crop(bbox)
    margin = max(8, round(max(cropped.size) * 0.07))
    square = max(cropped.size) + margin * 2
    canvas = Image.new("RGBA", (square, square))
    canvas.alpha_composite(cropped, ((square - cropped.width) // 2, (square - cropped.height) // 2))
    return canvas


def save_max_pair(master: Image.Image, output_dir: Path, size: tuple[int, int], suffix: str) -> None:
    icon = master.copy()
    icon.thumbnail(size, Image.Resampling.LANCZOS)
    rgba = Image.new("RGBA", size)
    rgba.alpha_composite(icon, ((size[0] - icon.width) // 2, (size[1] - icon.height) // 2))
    color = Image.new("RGB", size, (0, 0, 0))
    color.paste(rgba.convert("RGB"), mask=rgba.getchannel("A"))
    color.save(output_dir / f"DINUVPacker_{suffix}i.bmp")
    # Max 2016 describes this as 8-bit alpha data, but its shipped legacy
    # _XXa.bmp files store that grayscale channel in a 24-bit RGB bitmap.
    # Saving a single-channel paletted BMP makes the icon resolve but render
    # completely transparent in the classic CUI toolbar.
    alpha = rgba.getchannel("A")
    Image.merge("RGB", (alpha, alpha, alpha)).save(output_dir / f"DINUVPacker_{suffix}a.bmp")


def main() -> int:
    source = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)
    master = flatten_source(source)
    master_512 = master.resize((512, 512), Image.Resampling.LANCZOS)
    master_path = output_dir / "DINUVPacker.png"
    master_512.save(master_path)
    master_512.save(output_dir / "DINUVPacker.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    save_max_pair(master_512, output_dir, (16, 15), "16")
    save_max_pair(master_512, output_dir, (24, 24), "24")

    preview = Image.new("RGBA", (600, 300), (238, 238, 238, 255))
    draw = ImageDraw.Draw(preview)
    draw.text((20, 18), "Master / 24 px / 16 px", fill=(20, 20, 20, 255))
    preview.alpha_composite(master_512.resize((220, 220), Image.Resampling.LANCZOS), (20, 55))
    for x, size in ((300, (24, 24)), (450, (16, 15))):
        small = master_512.copy()
        small.thumbnail(size, Image.Resampling.LANCZOS)
        scale = 8
        preview.alpha_composite(small.resize((small.width * scale, small.height * scale), Image.Resampling.NEAREST), (x, 85))
    preview.save(output_dir / "DINUVPacker-preview.png")
    print(master_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
