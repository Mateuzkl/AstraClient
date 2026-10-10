"""Indexed transparent PNG floors; independent from any private server map."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw

def surface_color(floor):
    return (20 + floor * 20, 45 + floor * 10, 180 - floor * 10)

if __name__ == '__main__':
    import subprocess
    # Reuse the contrasting classic OTMM fixture, not a generated fake renderer.
    subprocess.run([sys.executable, '-B', str(Path(__file__).with_name('glitch_fixture.py')), *sys.argv[1:]], check=True)
    root = Path(sys.argv[2]) / 'surface-pack'
    root.mkdir()
    info = json.loads(Path(sys.argv[1]).read_text())
    (root / 'minimap.otmm').write_bytes((root.parent / 'glitch-pack/minimap.otmm').read_bytes())
    entries = []
    for floor in range(8):
        for level in (1, 2, 4, 8, 16):
            size = 16 * level
            for y in range(4096, 4224, size):
                for x in range(4096, 4224, size):
                    name = f'satellite-{level}-{x}-{y}-{floor}.png'
                    image = Image.new('RGBA', (512, 512), (*surface_color(floor), 255) if floor == 7 else (0, 0, 0, 0))
                    if floor < 7:
                        ImageDraw.Draw(image).rectangle((0, 0, 255, 511), fill=(*surface_color(floor), 255))
                    image.save(root / name)
                    entries.append(f'{level} {x} {y} {floor} {name}')
    (root / 'index.txt').write_text(f"ASTRAHD 1 16 32 {info['dat_signature']} {info['spr_signature']} {len(entries)}\n" + '\n'.join(entries) + '\n')
