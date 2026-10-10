"""Validate actual GPU frames, floor order, alpha, and selected-floor opacity."""
import json
import sys
from pathlib import Path
from PIL import Image
from surface_fixture import surface_color

report = Path(sys.argv[1])
frames = json.loads(report.read_text())
assert len(frames) >= 8
for frame in frames:
    with Image.open(report.parent / frame['name']) as source:
        image = source.convert('RGB')
        width, height = image.size
        if frame['z'] == 8:
            assert frame['level'] == 0
            assert len(image.getcolors(width * height)) == 1
        else:
            assert frame['level'] > 0
            scale, size = frame['scale'], frame['level'] * 16
            map_width = int(width / scale)
            left = frame['x'] - (map_width - 1) // 2
            origin_x = -int((map_width * scale - width) / 2)
            for py in range(0, height, 7):
                for px in range(width):
                    wx = left + (px + .5 - origin_x) / scale
                    fraction = wx % size / size
                    if min(fraction, abs(fraction - .5), 1 - fraction) * size * scale < 2: continue
                    if frame['z'] == 7 or fraction < .5:
                        expected = surface_color(frame['z'])
                    else:
                        expected = tuple(round(c * frame['opacity'] + b * (1 - frame['opacity']))
                                         for c, b in zip(surface_color(7), (0, 0, 0)))
                    actual = image.getpixel((px, py))
                    assert max(abs(a - b) for a, b in zip(actual, expected)) <= 3, (frame, px, py, actual, expected)
    print(f"PASS: {frame['name']} - real GPU layer order / background alpha / opaque selected floor")
