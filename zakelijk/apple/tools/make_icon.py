#!/usr/bin/env python3
"""Genereer het kleinere Pasr Zakelijk-icoon uit het goedgekeurde appicoon."""
from pathlib import Path

from PIL import Image


def main():
    assets = Path(__file__).resolve().parent.parent / "PasrZakelijk/Assets.xcassets"
    with Image.open(assets / "AppIcon.appiconset/AppIcon-1024.png") as icon:
        icon.resize((256, 256), Image.Resampling.LANCZOS).save(
            assets / "AppIconDisplay.imageset/icon.png"
        )


if __name__ == "__main__":
    main()
