#!/usr/bin/env python3
"""Rewrites oklch() colors in SVG attributes to sRGB hex, in place.

The web's avatars use oklch(), which the asset catalog's SVG renderer does not read.
  fill="oklch(L C H)"        -> fill="#rrggbb"
  stroke="oklch(L C H / A)"  -> stroke="#rrggbb" stroke-opacity="A"

Usage: svg_oklch.py file.svg [...]
"""
import math
import re
import sys

ATTR = re.compile(r'([\w-]+)="oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*(?:/\s*([\d.]+)\s*)?\)"')


def oklch_to_srgb_hex(l: float, c: float, h: float) -> str:
    a = c * math.cos(math.radians(h))
    b = c * math.sin(math.radians(h))
    l_ = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (l - 0.0894841775 * a - 1.2914855480 * b) ** 3
    linear = (
        4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
        -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
        -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_,
    )

    def encode(v: float) -> int:
        v = min(1.0, max(0.0, v))
        v = 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
        return round(v * 255)

    return "#" + "".join(f"{encode(v):02x}" for v in linear)


def convert(svg: str) -> str:
    def replace(match: re.Match) -> str:
        attr, l, c, h, alpha = match.groups()
        out = f'{attr}="{oklch_to_srgb_hex(float(l), float(c), float(h))}"'
        if alpha is not None:
            out += f' {attr}-opacity="{alpha}"'
        return out

    converted = ATTR.sub(replace, svg)
    if "oklch(" in converted:
        raise SystemExit("svg_oklch.py: an oklch() color this script does not handle is left")
    return converted


if __name__ == "__main__":
    for path in sys.argv[1:]:
        with open(path) as f:
            svg = f.read()
        with open(path, "w") as f:
            f.write(convert(svg))
