"""Read-only inspection of a Tenkaiser/Tibia satellite pack."""
import argparse
import io
import lzma
import struct
from collections import Counter
from pathlib import Path
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--world", type=Path)
args = parser.parse_args()
patterns = ["satellite-1-1008-1008-15-*", "satellite-1-*-*-47-*",
            "satellite-64-*-*-15-*", "satellite-1-*-*-7-*"]
sheet = Image.new("RGB", (1024, 1080), "#303030")
draw = ImageDraw.Draw(sheet)
for index, pattern in enumerate(patterns):
    f = next(args.source.glob(pattern))
    blob = f.read_bytes()
    decoded = lzma.decompress(blob[32:])
    image = Image.open(io.BytesIO(decoded)).convert("RGBA")
    print(f.name, image.size, image.getbbox(), image.getextrema())
    x, y = (index % 2) * 512, (index // 2) * 540
    sheet.paste(image, (x, y + 28), image)
    draw.text((x + 4, y + 5), f.name, fill="white")
sheet.save(args.output)
counts = Counter()
bounds = {}
for f in args.source.glob("satellite-1-*.bmp.lzma"):
    _, _, x, y, z, _ = f.name.split("-", 5)
    x, y, z = int(x), int(y), int(z)
    counts[z] += 1
    old = bounds.setdefault(z, [x, y, x + 16, y + 16])
    old[:] = [min(old[0], x), min(old[1], y), max(old[2], x + 16), max(old[3], y + 16)]
print("PACK floor counts/bounds:", sorted((z, counts[z], b) for z, b in bounds.items()))
if args.world:
    # Only collect node properties, not item/tile trees, from the escaped OTBM.
    raw = args.world.read_bytes()
    stack, props, tile_bounds, tile_counts, area = [], bytearray(), {}, Counter(), None
    escaped = False
    def node_props():
        global area
        if not props:
            return
        if props[0] == 4:
            area = struct.unpack_from("<HHB", props, 1)
        elif props[0] in (5, 14) and area:
            x, y, z = area[0] + props[1], area[1] + props[2], area[2]
            tile_counts[z] += 1
            old = tile_bounds.setdefault(z, [x, y, x, y])
            old[:] = [min(old[0], x), min(old[1], y), max(old[2], x), max(old[3], y)]
        elif props[0] == 13:
            ident = struct.unpack_from("<I", props, 1)[0]
            length = struct.unpack_from("<H", props, 5)[0]
            print("TOWN:", ident, props[7:7 + length], struct.unpack_from("<HHB", props, 7 + length))
    for byte in raw[4:]:
        if escaped:
            props.append(byte)
            escaped = False
        elif byte == 253:
            escaped = True
        elif byte in (254, 255):
            node_props()
            props.clear()
        else:
            props.append(byte)
    print("WORLD floor counts/bounds:", sorted((z, tile_counts[z], b) for z, b in tile_bounds.items()))
