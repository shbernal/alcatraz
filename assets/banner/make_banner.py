import os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

OUT = os.path.dirname(os.path.abspath(__file__))

def text_path(fontfile, s, size, x, y, tracking=0.0, kern=None):
    f = TTFont(fontfile)
    gs = f.getGlyphSet(); cmap = f.getBestCmap(); upm = f["head"].unitsPerEm
    sc = size / upm
    pen = SVGPathPen(gs, ntos=lambda v: ("%.1f" % v).rstrip("0").rstrip("."))
    cx = x
    prev = None
    for ch in s:
        g = cmap[ord(ch)]
        if kern and prev and (prev+ch) in kern: cx += kern[prev+ch]*size
        tp = TransformPen(pen, (sc, 0, 0, -sc, cx, y))
        gs[g].draw(tp)
        cx += gs[g].width * sc + tracking * size
        prev = ch
    return pen.getCommands(), cx - tracking*size - x

W, H = 1280, 320
DX = 76
WORD = "/usr/share/fonts/gsfonts/URWGothic-Demi.otf"
TAG = "/usr/share/fonts/Adwaita/AdwaitaMono-Regular.ttf"

THEMES = {
  "light": dict(bg="#ffffff", ink="#1b2838", muted="#5b6878", rock="#1b2838",
                tower="#1b2838", water="#9fb3c8", track="#d5dee8", accent="#e8590c",
                rib="#b8470a", win="#ffffff", beam=0.22),
  "dark":  dict(bg="#0d1117", ink="#e6edf3", muted="#8b98a8", rock="#2a3a50",
                tower="#e6edf3", water="#3a4d66", track="#223044", accent="#f76707",
                rib="#c4510a", win="#0d1117", beam=0.28),
}

def scene(c):
    a = c["accent"]
    parts = []
    # lighthouse beam (wedge from lantern, fading right)
    parts.append(f'''<defs><linearGradient id="bm" x1="0" x2="1" y1="0" y2="0">
<stop offset="0" stop-color="{a}" stop-opacity="{c["beam"]+0.25}"/><stop offset="1" stop-color="{a}" stop-opacity="0"/></linearGradient></defs>''')
    parts.append(f'<path d="M150 92 L470 58 L470 112 Z" fill="url(#bm)"/>')
    # rock: stepped mesa
    parts.append(f'<path d="M64 252 L96 224 L112 224 L128 206 L404 206 L420 220 L452 220 L492 252 Z" fill="{c["rock"]}"/>')
    # lighthouse: tapered tower + gallery + lantern + cap
    t = c["tower"]
    parts.append(f'<path d="M140 206 L144 112 L156 112 L160 206 Z" fill="{t}"/>')
    parts.append(f'<rect x="136" y="106" width="28" height="6" fill="{t}"/>')
    parts.append(f'<rect x="142" y="88" width="16" height="18" fill="{a}"/>')
    parts.append(f'<path d="M138 88 L150 76 L162 88 Z" fill="{t}"/>')
    # cellhouse = shipping container, corrugated ribs read as bars
    x0, y0, w, h = 200, 150, 176, 56
    parts.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="{a}"/>')
    ribs = "".join(f'M{x0+12+i*12} {y0+7}V{y0+h-7}' for i in range(13))
    parts.append(f'<path d="{ribs}" stroke="{c["rib"]}" stroke-width="4" stroke-linecap="round"/>')
    parts.append(f'<path d="M{x0} {y0}h{w}v5h-{w}zM{x0} {y0+h-5}h{w}v5h-{w}z" fill="{c["rib"]}"/>')
    # water tower-ish small block on the right for skyline rhythm
    parts.append(f'<path d="M384 206 L387 156 L395 156 L398 206 Z" fill="{c["rock"]}"/>')
    # water lines
    for i,(xa,xb,y) in enumerate([(40,520,262),(96,300,274),(340,470,274),(150,260,286),(380,430,286)]):
        parts.append(f'<path d="M{xa} {y}H{xb}" stroke="{c["water"]}" stroke-width="3" stroke-linecap="round"/>')
    return "\n".join(parts)

def build(name):
    c = THEMES[name]
    wp, ww = text_path(WORD, "alcatraz", 132, 576+DX, 186, tracking=-0.01)
    tp, tw = text_path(TAG, "macOS in a container", 30, 580+DX, 242, tracking=0.02)
    # boot-progress bar under tagline
    bar_y = 270
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="alcatraz: macOS in a container">
<title>alcatraz: macOS in a container</title>
<g transform="translate({DX} 0)">\n{scene(c)}\n</g>
<path d="{wp}" fill="{c["ink"]}"/>
<path d="{tp}" fill="{c["muted"]}"/>
<rect x="{580+DX}" y="{bar_y}" width="{tw:.0f}" height="6" rx="3" fill="{c["track"]}"/>
<rect x="{580+DX}" y="{bar_y}" width="{tw*0.62:.0f}" height="6" rx="3" fill="{c["accent"]}"/>
</svg>
'''
    p = f"{OUT}/banner-{name}.svg"
    open(p,"w").write(svg)
    print(name, os.path.getsize(p), ww, tw)

for n in THEMES: build(n)
