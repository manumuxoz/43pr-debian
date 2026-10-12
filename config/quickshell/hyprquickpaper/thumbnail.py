#!/usr/bin/env python3
"""Genera una miniatura para el carrusel de hyprquickpaper sin ImageMagick.

Uso: thumbnail.py <origen> <destino>

Equivale a: convert <origen> -thumbnail x500 -strip -quality 85 <destino>
Se usa como respaldo cuando `magick`/`convert` no están instalados; requiere
Pillow (python3-pil). Mantiene la extensión del destino, igual que el original,
porque shell.qml pide la miniatura con el mismo nombre de fichero que el wallpaper.
"""
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 3:
        print("usage: thumbnail.py <src> <dst>", file=sys.stderr)
        return 2

    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    try:
        from PIL import Image
    except ImportError:
        print("thumbnail.py: falta Pillow (instala python3-pil o imagemagick)", file=sys.stderr)
        return 1

    try:
        with Image.open(src) as im:
            # -thumbnail x500: sólo reduce, nunca agranda (mismo criterio que
            # Pillow.thumbnail).
            im.thumbnail((100000, 500), Image.LANCZOS)
            dst.parent.mkdir(parents=True, exist_ok=True)
            ext = dst.suffix.lower()
            if ext == ".png":
                im.save(dst, "PNG")
            elif ext == ".webp":
                im.convert("RGB").save(dst, "WEBP", quality=85)
            else:
                im.convert("RGB").save(dst, "JPEG", quality=85)
    except Exception as e:
        print(f"thumbnail.py: {src}: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
