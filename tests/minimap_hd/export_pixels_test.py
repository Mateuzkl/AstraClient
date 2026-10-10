"""Independent pixel comparison for top/common elevation in native PNG exports."""
import json
import sys
from pathlib import Path
from PIL import Image

fixture = json.loads(Path(sys.argv[1]).read_text())
with Image.open(fixture['background']) as image:
    background = image.convert('RGBA')
with Image.open(fixture['top']) as image:
    top = image.convert('RGBA')
with Image.open(fixture['combined']) as image:
    actual = image.convert('RGBA')
assert top.getbbox(), 'Top fixture must contain visible pixels'
elevation = int(fixture['elevation'])
assert elevation > 0
shifted = Image.new('RGBA', top.size)
shifted.paste(top, (-elevation, -elevation))
expected = Image.alpha_composite(background, shifted)
assert expected.tobytes() == actual.tobytes(), 'Top item ignored common-item elevation'
unshifted = Image.alpha_composite(background, top)
assert unshifted.tobytes() != expected.tobytes(), 'Fixture must distinguish shifted from unshifted terrain'
print('PASS: real native PNG pixels include common-item elevation before drawing top items')
