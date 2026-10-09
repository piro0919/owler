#!/usr/bin/env python3
"""assets/icon-source.png から、アプリのアイコンとメニューバーのアイコンを書き出す。

原画は ChatGPT で作った（依頼文は docs/art-prompt.md）、四隅まで塗り切った正方形。角丸と余白はここで付ける。

    python3 Tools/make-icon.py

書き出すもの:
    assets/AppIcon.png         角丸と余白を付けた 1024px。README と LP でも使う
    Resources/AppIcon.icns     アプリに入れる
    Resources/StatusIcon.png   メニューバー用の影絵。18pt の 1x
    Resources/StatusIcon@2x.png          同じく 2x
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "icon-source.png"
RESOURCES = ROOT / "Resources"

CANVAS = 1024
# Apple の格子では、1024 の画布に 824 の本体を置き、角の半径は本体の約 22.5%
BODY = 824
RADIUS = 185

# メニューバーの影絵は高さ 18pt に収める
STATUS_POINTS = 18


def rounded_icon(source: Image.Image) -> Image.Image:
    body = source.convert("RGBA").resize((BODY, BODY), Image.LANCZOS)

    # 縁を滑らかにするため、4倍で描いてから縮める
    scale = 4
    mask = Image.new("L", (BODY * scale, BODY * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, BODY * scale - 1, BODY * scale - 1), radius=RADIUS * scale, fill=255
    )
    body.putalpha(mask.resize((BODY, BODY), Image.LANCZOS))

    offset = (CANVAS - BODY) // 2
    # 他の Mac アプリと並んだとき浮いて見えないよう、下に薄い影を落とす
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_body = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 90))
    shadow_body.putalpha(ImageChops.multiply(body.getchannel("A"), shadow_body.getchannel("A")))
    shadow.paste(shadow_body, (offset, offset + 10), shadow_body)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.alpha_composite(shadow)
    icon.alpha_composite(body, (offset, offset))
    return icon


def write_icns(icon: Image.Image, out: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            icon.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
            icon.resize((size * 2, size * 2), Image.LANCZOS).save(
                iconset / f"icon_{size}x{size}@2x.png"
            )
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)


def status_silhouette(source: Image.Image) -> Image.Image:
    """白いフクロウだけを抜き出して、黒の影絵にする。

    地は藍色のグラデーションで、フクロウは白。赤・緑・青の最小値は、地（赤が低い）と
    琥珀色の目（青が低い）では低く、白い体だけで高い。それを不透明度に使うと、目に穴の開いた影絵になる
    """
    r, g, b = source.convert("RGB").split()
    lowest = ImageChops.darker(ImageChops.darker(r, g), b)
    # 地と目はおよそ 0〜100、体の白は 200 以上。その間をなだらかにつなぐ
    alpha = lowest.point(lambda v: 0 if v < 130 else 255 if v > 200 else int((v - 130) * 255 / 70))
    box = alpha.getbbox()
    alpha = alpha.crop(box)

    side = max(alpha.size)
    square = Image.new("L", (side, side), 0)
    square.paste(alpha, ((side - alpha.width) // 2, (side - alpha.height) // 2))

    glyph = Image.new("RGBA", square.size, (0, 0, 0, 255))
    glyph.putalpha(square)
    return glyph


def main() -> None:
    source = Image.open(SOURCE)
    RESOURCES.mkdir(exist_ok=True)

    icon = rounded_icon(source)
    icon.save(ROOT / "assets" / "AppIcon.png")
    write_icns(icon, RESOURCES / "AppIcon.icns")

    glyph = status_silhouette(source)
    for suffix, factor in (("", 1), ("@2x", 2)):
        px = STATUS_POINTS * factor
        glyph.resize((px, px), Image.LANCZOS).save(RESOURCES / f"StatusIcon{suffix}.png")

    print("書き出しました:", ", ".join(p.name for p in sorted(RESOURCES.iterdir())))


if __name__ == "__main__":
    if shutil.which("iconutil") is None:
        raise SystemExit("iconutil が見つかりません。macOS で実行してください")
    main()
