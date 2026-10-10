"""Compare real GPU-rendered transition frames against independent chunk geometry."""
import json
import math
import sys
from pathlib import Path
from PIL import Image
from glitch_fixture import color

report = Path(sys.argv[1])
frames = json.loads(report.read_text())
assert {'warm.png', 'zoom-start.png', 'partial.png', 'refined.png', 'fractional.png', 'full-map-pending.png', 'returned.png', 'floor8.png', 'classic.png'} == {f['name'] for f in frames}
for frame in frames:
    with Image.open(report.parent / frame['name']) as source:
        image = source.convert('RGB')
        width, height = image.size
        level = frame['level']
        if not level:
            # Classic-only remains functional and deliberately unlike the HD fixture.
            assert len(image.getcolors(width * height) or []) == 1
            assert image.getpixel((width // 2, height // 2))[0] > 100
            print(f"PASS: {frame['name']} - classic-only fallback preserved")
            continue
        scale = frame['scale']
        map_width, map_height = int(width / scale), math.ceil(height / scale)
        left = frame['x'] - (map_width - 1) // 2
        top = frame['y'] - (map_height - 1) // 2
        origin_x = -int((map_width * scale - width) / 2)
        origin_y = -int((map_height * scale - height) / 2)
        size = level * 16
        for py in range(height):
            for px in range(width):
                wx = left + (px + .5 - origin_x) / scale
                wy = top + (py + .5 - origin_y) / scale
                # Skip only pixels within one texel of a mathematically shared edge;
                # still reject any OTMM/background seam there by color range.
                actual = image.getpixel((px, py))
                assert actual[0] < 80 and actual[2] > 140, (frame['name'], px, py, actual, 'OTMM/seam leaked')
                if min(wx % size, size - wx % size, wy % size, size - wy % size) * scale < 1:
                    continue
                expected = color(level, int(wx // size) * size, int(wy // size) * size, frame['z'])
                assert max(abs(a - b) for a, b in zip(actual, expected)) <= 2, (frame['name'], px, py, actual, expected)
    print(f"PASS: {frame['name']} - coherent LOD {level}, shared edges and no transient OTMM rectangles")
