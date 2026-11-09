#!/usr/bin/env python3
"""Build the blank bedside dial plates.

These bitmaps are material only: ivory or charcoal face, brushed brass ring,
a soft glass highlight, and a small center cap. They contain no ticks, no
numerals, no hands, and no time text. The app draws the scale on top.

Ring geometry is shared with BedsidePlateMetrics in BedsideTimeSetter.swift.
The circle is centered and fills the square. The outer few percent of the
radius fade to transparent so the plate blends into the editor background.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LIGHT = ROOT / "iOS/App/BedsideDialPlateLight.png"
DARK = ROOT / "iOS/App/BedsideDialPlateDark.png"

# Keep in sync with BedsidePlateMetrics.ringInner.
RING_INNER = 0.818
SIZE = 1600


def plates() -> None:
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    center = (SIZE - 1) / 2.0
    dx = (xx - center) / (SIZE / 2.0)
    dy = (yy - center) / (SIZE / 2.0)
    radius = np.sqrt(dx * dx + dy * dy)
    angle = np.arctan2(dy, dx)
    # Light arrives from the upper left. +1 faces the lamp.
    light = np.cos(angle - math.radians(-135.0))
    brush = 0.5 + 0.5 * np.sin((xx * 0.82 + yy * 0.21) * 2.4)

    render(LIGHT, radius, angle, light, brush, dark=False)
    render(DARK, radius, angle, light, brush, dark=True)


def render(
    path: Path,
    radius: np.ndarray,
    angle: np.ndarray,
    light: np.ndarray,
    brush: np.ndarray,
    dark: bool,
) -> None:
    if dark:
        face = np.array([0.102, 0.098, 0.090], dtype=np.float32)
        bezel = np.array([0.078, 0.075, 0.067], dtype=np.float32)
        brass_hi = np.array([0.83, 0.70, 0.46], dtype=np.float32)
        brass_mid = np.array([0.58, 0.46, 0.28], dtype=np.float32)
        brass_lo = np.array([0.32, 0.24, 0.14], dtype=np.float32)
    else:
        face = np.array([0.945, 0.929, 0.898], dtype=np.float32)
        bezel = np.array([0.953, 0.941, 0.918], dtype=np.float32)
        brass_hi = np.array([0.86, 0.76, 0.55], dtype=np.float32)
        brass_mid = np.array([0.70, 0.58, 0.36], dtype=np.float32)
        brass_lo = np.array([0.50, 0.40, 0.24], dtype=np.float32)

    dx = dx_shift(radius, angle)
    dy = dy_shift(radius, angle)
    rgb = np.broadcast_to(bezel, radius.shape + (3,)).copy()
    alpha = np.zeros(radius.shape, dtype=np.float32)

    face_mask = radius <= RING_INNER
    ring_mask = (radius > RING_INNER) & (radius <= 0.945)
    bezel_mask = (radius > 0.945) & (radius <= 1.02)

    # Warm paper or charcoal glass. The lamp only lifts the face a little,
    # so the ivory does not clip to white.
    shade = 0.985 + 0.03 * np.clip(light, 0, 1)
    face_rgb = face * shade[..., None]
    # Specular glass: a soft crescent in the upper left, not a wash over the whole face.
    glass = np.exp(-((dx + 0.32) ** 2) / 0.18 - ((dy + 0.38) ** 2) / 0.22)
    glass *= 0.20 if dark else 0.07
    face_rgb = np.clip(face_rgb + glass[..., None], 0, 1)
    # The ring casts a thin shadow onto the face.
    inner_shadow = np.clip((radius - (RING_INNER - 0.045)) / 0.045, 0, 1) ** 2
    face_rgb = face_rgb * (1 - (0.22 if dark else 0.06) * inner_shadow)[..., None]
    rgb = np.where(face_mask[..., None], face_rgb, rgb)

    # Brushed brass. The grain is fine; the lamp does the modeling.
    metal = np.clip(0.42 + 0.58 * light + (brush - 0.5) * 0.045, 0, 1)
    brass = brass_lo + (brass_mid - brass_lo) * np.clip(metal * 1.4, 0, 1)[..., None]
    brass = brass + (brass_hi - brass) * np.clip((metal - 0.55) / 0.45, 0, 1)[..., None]
    rgb = np.where(ring_mask[..., None], brass, rgb)

    edge = np.exp(-((radius - 0.932) ** 2) / (2 * 0.006 ** 2))
    edge *= np.clip(light, 0, 1) ** 2 * (0.22 if dark else 0.16)
    rgb = np.clip(np.where(ring_mask[..., None], rgb + edge[..., None], rgb), 0, 1)
    rgb = np.where(bezel_mask[..., None], bezel, rgb)

    # Center cap: a small dome. No mark, no numeral.
    cap_radius = 0.034
    cap = radius < cap_radius
    cap_shade = np.clip(0.25 + 0.85 * ((cap_radius - radius) / cap_radius) + 0.35 * np.clip(-dy, 0, 1), 0, 1)
    cap_color = brass_lo + (brass_hi - brass_lo) * cap_shade[..., None]
    rgb = np.where(cap[..., None], cap_color, rgb)

    alpha = np.where(radius <= 0.97, 1.0, 0.0)
    fade = np.clip((1.005 - radius) / 0.035, 0, 1)
    alpha = np.where(radius > 0.97, fade, alpha)
    alpha = np.where(radius > 1.01, 0.0, alpha)

    out = np.dstack([rgb, alpha])
    image = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)
    print(f"wrote {path} ({path.stat().st_size} bytes)")


def dx_shift(radius: np.ndarray, angle: np.ndarray) -> np.ndarray:
    return radius * np.cos(angle)


def dy_shift(radius: np.ndarray, angle: np.ndarray) -> np.ndarray:
    return radius * np.sin(angle)


if __name__ == "__main__":
    plates()
