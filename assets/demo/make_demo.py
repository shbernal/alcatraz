#!/usr/bin/env python3
"""Generate the alcatraz README hero demo: demo-light.svg and demo-dark.svg.

A terminal types the quick-start `docker run`, prints the container's startup
output, then a QEMU window opens on a drawn OpenCore picker. CSS animation only;
every element's resting style is the finished scene, so static renderers show
the final frame. All text is outlined (glyphs from DejaVu Sans Mono / DejaVu
Sans as <path> in <defs>, placed with <use>), so no font is needed to view it.

Usage: make_demo.py [OUTDIR]
"""
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONTS = {
    "m": "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
    "b": "/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf",
    "s": "/usr/share/fonts/TTF/DejaVuSans.ttf",
}
SIZE = 12.0  # glyphs are defined at 12 px; other sizes scale a group

# ---------------------------------------------------------------- timeline
CYCLE = 25.0          # seconds per loop
FADE_OUT = (24.4, 24.9)

W, H = 960, 552
TERM = dict(x=16, y=14, w=760, h=472)
QEMU = dict(x=448, y=196, w=496, h=340)
COLS = 100
LH = 16.5             # terminal line height

THEMES = {
    "light": dict(
        term_bg="#f6f8fa", term_bar="#eaeef2", border="#d0d7de", text="#1f2328",
        dim="#656d76", prompt="#1a7f37", ok="#1a7f37", title="#57606a",
        cursor="#1f2328", shadow=0.18, q_bar="#eaeef2", q_menu="#f6f8fa",
        q_text="#24292f", q_border="#d0d7de"),
    "dark": dict(
        term_bg="#161b22", term_bar="#21262d", border="#30363d", text="#c9d1d9",
        dim="#8b949e", prompt="#3fb950", ok="#3fb950", title="#8b949e",
        cursor="#c9d1d9", shadow=0.55, q_bar="#2d333b", q_menu="#22272e",
        q_text="#adbac7", q_border="#444c56"),
}

# ---------------------------------------------------------------- content
# The quick start from README.md, as bash echoes it when typed (PS2 is "> ").
COMMAND = [
    ("$ ", "docker run -it \\"),
    ("> ", "    --device /dev/kvm \\"),
    ("> ", "    -p 50922:10022 \\"),
    ("> ", "    -v ./mac:/data \\"),
    ("> ", "    -v /tmp/.X11-unix:/tmp/.X11-unix \\"),
    ("> ", '    -e "DISPLAY=${DISPLAY:-:0.0}" \\'),
    ("> ", "    ghcr.io/shbernal/alcatraz:latest"),
]
TYPE_START, CPS, ENTER_PAUSE = 0.7, 52.0, 0.14

DMG_MB = 1042.7       # illustrative size of Tahoe's BaseSystem.dmg
TMP = "/tmp/tmp.Qz81KfXbWm"
BAR = (COLS - 2) // 3  # macrecovery.py: barwidth = (columns - TERMINAL_MARGIN) // 3


def progress(p, total=DMG_MB):
    return (f"{total * p:.1f}/{total:.1f} MB |{'=' * int(BAR * p):<{BAR}}|"
            f" {p * 100:.1f}% downloaded")


def wrap(s):
    return [s[i:i + COLS] for i in range(0, len(s), COLS)]


# ---------------------------------------------------------------- glyphs
class Glyphs:
    def __init__(self):
        self.fonts = {k: TTFont(p) for k, p in FONTS.items()}
        self.used = {}

    def adv(self, font, ch):
        f = self.fonts[font]
        name = f.getBestCmap().get(ord(ch))
        return f["hmtx"][name][0] * SIZE / f["head"].unitsPerEm

    def ref(self, font, ch):
        gid = f"{font}{ord(ch):x}"
        if gid not in self.used:
            f = self.fonts[font]
            name = f.getBestCmap()[ord(ch)]
            gs = f.getGlyphSet()
            s = SIZE / f["head"].unitsPerEm

            def ntos(v):
                t = f"{v:.2f}".rstrip("0").rstrip(".")
                return "0" if t in ("-0", "") else t
            pen = SVGPathPen(gs, ntos=ntos)
            gs[name].draw(TransformPen(pen, (s, 0, 0, -s, 0, 0)))
            self.used[gid] = pen.getCommands()
        return gid

    def defs(self):
        return "".join(f'<path id="{k}" d="{d}"/>' for k, d in self.used.items() if d)

    def text(self, s, x, y, font="m", size=SIZE, cls=None, anchor="start"):
        k = size / SIZE
        width = sum(self.adv(font, c) for c in s)
        if anchor == "middle":
            x -= width * k / 2
        out, cx = [], 0.0
        for c in s:
            if c != " ":
                gid = self.ref(font, c)
                if self.used[gid]:
                    out.append(f'<use href="#{gid}" x="{cx:.2f}"/>')
            cx += self.adv(font, c)
        tr = f"translate({x:.2f} {y:.2f})" + (f" scale({k:g})" if k != 1 else "")
        c = f' class="{cls}"' if cls else ""
        return f'<g{c} transform="{tr}">{"".join(out)}</g>'


# ---------------------------------------------------------------- animation
class Anim:
    """Collects keyframes; every animation runs CYCLE seconds, infinite."""

    def __init__(self):
        self.rules, self.n = [], 0

    def pct(self, t):
        return f"{max(0.0, min(100.0, t / CYCLE * 100)):.3f}".rstrip("0").rstrip(".")

    def add(self, frames):
        self.n += 1
        name = f"k{self.n}"
        body = "".join(f"{sel}{{{decl}}}" for sel, decl in frames)
        self.rules.append(f"@keyframes {name}{{{body}}}"
                          f".{name}{{animation:{name} {CYCLE:g}s linear infinite}}")
        return name

    def appear(self, t):
        """Hidden until t, then shown for the rest of the cycle."""
        return self.add([(f"0%,{self.pct(t)}%", "opacity:0"),
                         (f"{self.pct(t + 0.01)}%,100%", "opacity:1")])

    def window(self, t0, t1):
        """Shown only in [t0, t1); resting style is hidden (class h)."""
        return self.add([(f"0%,{self.pct(t0)}%", "opacity:0"),
                         (f"{self.pct(t0 + 0.01)}%,{self.pct(t1)}%", "opacity:1"),
                         (f"{self.pct(t1 + 0.01)}%,100%", "opacity:0")])


def build(theme_name):
    T = THEMES[theme_name]
    G, A = Glyphs(), Anim()
    adv = G.adv("m", "a")
    body = []

    tx = TERM["x"] + 14
    ty = TERM["y"] + 28 + 22  # first baseline
    row = 0

    def y(r):
        return ty + r * LH

    # Terminal chrome
    body.append(
        f'<rect x="{TERM["x"] + 4}" y="{TERM["y"] + 8}" width="{TERM["w"] - 8}" '
        f'height="{TERM["h"] - 4}" rx="10" fill="#000" opacity="{T["shadow"]}" filter="url(#blur)"/>'
        f'<rect x="{TERM["x"]}" y="{TERM["y"]}" width="{TERM["w"]}" height="{TERM["h"]}" '
        f'rx="9" fill="{T["term_bg"]}" stroke="{T["border"]}"/>'
        f'<path d="M{TERM["x"] + 0.5} {TERM["y"] + 28}V{TERM["y"] + 9}a8.5 8.5 0 0 1 8.5-8.5'
        f'H{TERM["x"] + TERM["w"] - 9}a8.5 8.5 0 0 1 8.5 8.5V{TERM["y"] + 28}z" fill="{T["term_bar"]}"/>'
        f'<path d="M{TERM["x"]} {TERM["y"] + 28.5}h{TERM["w"]}" stroke="{T["border"]}"/>')
    for i in range(3):
        cx = TERM["x"] + TERM["w"] - 18 - i * 18
        body.append(f'<circle cx="{cx}" cy="{TERM["y"] + 14}" r="5" fill="{T["border"]}"/>')
    body.append(G.text("~/vms — bash", TERM["x"] + TERM["w"] / 2, TERM["y"] + 18.5,
                       font="s", cls="ti", anchor="middle"))

    dyn = []  # everything that resets each loop

    # Typed command
    t = TYPE_START
    for i, (ps, cmd) in enumerate(COMMAND):
        yy = y(row)
        n = len(cmd)
        t0 = t if i else 0.0
        prompt = G.text(ps, tx, yy, font="b" if ps == "$ " else "m", cls="pr")
        dyn.append(f'<g class="{A.appear(t0)}">{prompt}</g>' if i else prompt)
        dyn.append(G.text(cmd, tx + 2 * adv, yy, cls="cm"))
        t1 = t + n / CPS
        x0, wd = tx + 2 * adv, n * adv
        steps = f"animation-timing-function:steps({n},end)"
        # Curtain in the terminal colour, shrinking right to left as keys land.
        cur = A.add([
            (f"0%,{A.pct(t)}%", f"opacity:1;transform:scaleX(1);{steps}"),
            (f"{A.pct(t1)}%", "opacity:1;transform:scaleX(0)"),
            (f"{A.pct(t1 + 0.01)}%,100%", "opacity:0;transform:scaleX(0)")])
        dyn.append(f'<rect class="h cu {cur}" x="{x0 - 0.5:.2f}" y="{yy - 12:.2f}" '
                   f'width="{wd + 1:.2f}" height="{LH:.2f}" fill="{T["term_bg"]}"/>')
        # Cursor riding the typing.
        frames = [(f"0%,{A.pct(t0)}%", "opacity:0;transform:translateX(0)")] if i else []
        if not i:  # blink on the empty prompt first
            frames = [("0%,1.2%", "opacity:1;transform:translateX(0)"),
                      ("1.21%,2.2%", "opacity:0;transform:translateX(0)")]
        frames += [
            (f"{A.pct(t0 + 0.01) if i else '2.21'}%,{A.pct(t)}%",
             f"opacity:1;transform:translateX(0);{steps}"),
            (f"{A.pct(t1)}%,{A.pct(t1 + ENTER_PAUSE)}%", f"opacity:1;transform:translateX({wd:.2f}px)"),
            (f"{A.pct(t1 + ENTER_PAUSE + 0.01)}%,100%", f"opacity:0;transform:translateX({wd:.2f}px)")]
        c = A.add(frames)
        dyn.append(f'<rect class="h {c}" x="{x0:.2f}" y="{yy - 10.5:.2f}" width="{adv:.2f}" '
                   f'height="14" fill="{T["cursor"]}"/>')
        t = t1 + ENTER_PAUSE
        row += 1

    # Container output. Each entry: (time, text or list of frames, class)
    t += 0.35
    out = []

    def line(at, s, cls="tx"):
        out.append((at, [s], cls, None))

    def frames(at, step, texts, cls="tx"):
        out.append((at, texts, cls, step))

    line(t, "No installer at /data/installer.img, downloading macOS tahoe"); t += 0.3
    line(t, "Downloading 093-37385..."); t += 0.35
    line(t, f"Saving http://oscdn.apple.com/…/BaseSystem.dmg to {TMP}/BaseSystem.dmg...")
    t += 0.25
    ps = [0.0, 0.07, 0.19, 0.33, 0.48, 0.62, 0.77, 0.9, 1.0]
    frames(t, 0.28, [progress(p) for p in ps]); t += 0.28 * len(ps)
    line(t, "Download complete!", "ok"); t += 0.2
    line(t, f"Saving http://oscdn.apple.com/…/BaseSystem.chunklist to {TMP}/BaseSystem.chunklist...")
    t += 0.15
    line(t, progress(1.0, 0.0)); t += 0.1
    line(t, "Download complete!", "ok"); t += 0.2
    line(t, "Verifying image with chunklist..."); t += 0.15
    chunks = [1, 14, 29, 47, 63, 80, 96, 105]
    frames(t, 0.12, [f"Chunk {c} ({10485760 if c < 105 else 2165530} bytes)" for c in chunks])
    t += 0.12 * len(chunks)
    line(t, "Image verification complete!", "ok"); t += 0.2
    conv = [0.0, 12.5, 31.25, 50.0, 68.75, 87.5, 100.0]
    frames(t, 0.15, [f"    ({v:.2f}/100%)" for v in conv]); t += 0.15 * len(conv)
    t += 0.1
    fmt = ("Formatting '/data/disk.qcow2', fmt=qcow2 cluster_size=65536 extended_l2=off "
           "compression_type=zlib size=274877906944 lazy_refcounts=off refcount_bits=16")
    for part in wrap(fmt):
        line(t, part)
    t += 0.3
    exe = ("+ exec qemu-system-x86_64 -m 4G -cpu Skylake-Client,-hle,-rtm,kvm=on,vendor=GenuineIntel,"
           "+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check "
           "-machine q35,accel=kvm:tcg -smp 4,cores=4 ...")
    line(t, exe[:COLS - 1] + "…", "dm"); t += 0.25
    line(t, "QEMU 10.1.0 monitor - type 'help' for more information"); t += 0.1
    line(t, "(qemu) ")
    qemu_prompt_t = t

    for at, texts, cls, step in out:
        yy = y(row)
        if step is None:
            k = A.appear(at)
            dyn.append(f'<g class="{k}">{G.text(texts[0], tx, yy, cls=cls)}</g>')
        else:
            for j, s in enumerate(texts):
                last = j == len(texts) - 1
                a0 = at + j * step
                k = A.appear(a0) if last else A.window(a0, a0 + step)
                dyn.append(f'<g class="{"" if last else "h "}{k}">{G.text(s, tx, yy, cls=cls)}</g>')
        row += 1

    # Blinking cursor after "(qemu) ": resting visible.
    row -= 1
    blink = [(f"0%,{A.pct(qemu_prompt_t)}%", "opacity:0")]
    b, on = qemu_prompt_t + 0.01, True
    while b < CYCLE:
        nb = min(b + 0.53, CYCLE)
        blink.append((f"{A.pct(b)}%,{A.pct(nb - 0.01)}%", f"opacity:{1 if on else 0}"))
        b, on = nb, not on
    k = A.add(blink)
    dyn.append(f'<rect class="{k}" x="{tx + 7 * adv:.2f}" y="{y(row) - 10.5:.2f}" '
               f'width="{adv:.2f}" height="14" fill="{T["cursor"]}"/>')

    # QEMU window
    q_t = qemu_prompt_t + 0.35
    qx, qy, qw, qh = QEMU["x"], QEMU["y"], QEMU["w"], QEMU["h"]
    sx, sy = qx + 1, qy + 28 + 22
    sw, sh = qw - 2, qh - 28 - 22 - 1
    win = A.add([
        (f"0%,{A.pct(q_t)}%", "opacity:0;transform:translateY(14px) scale(.97)"),
        (f"{A.pct(q_t + 0.01)}%", "opacity:0;transform:translateY(14px) scale(.97);"
         "animation-timing-function:cubic-bezier(.2,.8,.3,1)"),
        (f"{A.pct(q_t + 0.45)}%,100%", "opacity:1;transform:none")])
    blk = A.add([
        (f"0%,{A.pct(q_t + 0.9)}%", "opacity:1"),
        (f"{A.pct(q_t + 1.4)}%,100%", "opacity:0")])
    sel = A.add([
        (f"0%,{A.pct(q_t + 1.5)}%", "opacity:0"),
        (f"{A.pct(q_t + 1.9)}%,100%", "opacity:1")])
    pcx, pcy = sx + sw / 2, sy + sh * 0.44
    qwin = [
        f'<g class="qw {win}">',
        f'<rect x="{qx + 4}" y="{qy + 8}" width="{qw - 8}" height="{qh - 4}" rx="9" '
        f'fill="#000" opacity="{T["shadow"] + 0.05:.2f}" filter="url(#blur)"/>',
        f'<rect x="{qx}" y="{qy}" width="{qw}" height="{qh}" rx="8" fill="{T["q_menu"]}" '
        f'stroke="{T["q_border"]}"/>',
        f'<path d="M{qx + 0.5} {qy + 28}V{qy + 8}a7.5 7.5 0 0 1 7.5-7.5H{qx + qw - 8}'
        f'a7.5 7.5 0 0 1 7.5 7.5V{qy + 28}z" fill="{T["q_bar"]}"/>',
        G.text("QEMU", qx + qw / 2, qy + 18.5, font="s", cls="qt", anchor="middle"),
        f'<path d="M{qx + qw - 21} {qy + 10}l8 8m0-8l-8 8" stroke="{T["q_text"]}" '
        f'stroke-width="1.4" stroke-linecap="round"/>',
        f'<path d="M{qx} {qy + 28.5}h{qw}" stroke="{T["q_border"]}"/>',
        G.text("Machine", qx + 12, qy + 43, font="s", size=11.5, cls="qt"),
        G.text("View", qx + 76, qy + 43, font="s", size=11.5, cls="qt"),
        # Guest screen: OpenCore's graphical picker, drawn generically.
        f'<rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" fill="url(#oc)"/>',
        # Selection plate
        f'<rect class="{sel}" x="{pcx - 50}" y="{pcy - 48}" width="100" height="96" rx="16" '
        f'fill="#fff" fill-opacity=".1" stroke="#fff" stroke-opacity=".28"/>',
        # Drive icon
        f'<rect x="{pcx - 34}" y="{pcy - 22}" width="68" height="44" rx="7" fill="url(#drv)"/>',
        f'<rect x="{pcx - 34}" y="{pcy + 8}" width="68" height="14" rx="0" fill="#000" '
        f'fill-opacity=".18"/>',
        f'<rect x="{pcx - 34}" y="{pcy - 22}" width="68" height="44" rx="7" fill="none" '
        f'stroke="#fff" stroke-opacity=".35"/>',
        f'<circle cx="{pcx + 24}" cy="{pcy + 15}" r="2.4" fill="#7ee787"/>',
        f'<rect x="{pcx - 26}" y="{pcy + 13.5}" width="30" height="3" rx="1.5" fill="#fff" '
        f'fill-opacity=".35"/>',
        # Down-arrow badge: an installer volume
        f'<circle cx="{pcx}" cy="{pcy - 5}" r="10" fill="#fff" fill-opacity=".9"/>',
        f'<path d="M{pcx} {pcy - 11}v10m-4.5-4.5l4.5 4.5 4.5-4.5" fill="none" stroke="#3a4a63" '
        f'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
        G.text("macOS Base System", pcx, pcy + 66, font="s", size=11, cls="ol", anchor="middle"),
    ]
    # Restart and shut down buttons
    by = sy + sh - 34
    for bx, kind in ((pcx - 20, "r"), (pcx + 20, "p")):
        qwin.append(f'<circle cx="{bx}" cy="{by}" r="12" fill="#fff" fill-opacity=".1" '
                    f'stroke="#fff" stroke-opacity=".25"/>')
        if kind == "r":
            qwin.append(f'<path d="M{bx + 5} {by - 1.5}a5.2 5.2 0 1 1-1.6-3.6" fill="none" '
                        f'stroke="#e6edf3" stroke-width="1.6" stroke-linecap="round"/>'
                        f'<path d="M{bx + 4.6} {by - 7.4}v4.2h-4.2" fill="none" stroke="#e6edf3" '
                        f'stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>')
        else:
            qwin.append(f'<path d="M{bx - 3.6} {by - 3.9}a5.4 5.4 0 1 0 7.2 0" fill="none" '
                        f'stroke="#e6edf3" stroke-width="1.6" stroke-linecap="round"/>'
                        f'<path d="M{bx} {by - 6.5}v5.5" stroke="#e6edf3" stroke-width="1.6" '
                        f'stroke-linecap="round"/>')
    qwin += [
        f'<rect class="h {blk}" x="{sx}" y="{sy}" width="{sw}" height="{sh}" fill="#000"/>',
        "</g>"]
    dyn.extend(qwin)

    fade = A.add([(f"0%,{A.pct(FADE_OUT[0])}%", "opacity:1"),
                  (f"{A.pct(FADE_OUT[1])}%,100%", "opacity:0")])

    css = (
        f".ti{{fill:{T['title']}}}.pr{{fill:{T['prompt']}}}.cm{{fill:{T['text']}}}"
        f".tx{{fill:{T['text']}}}.ok{{fill:{T['ok']}}}.dm{{fill:{T['dim']}}}"
        f".qt{{fill:{T['q_text']}}}.ol{{fill:#f0f3f6}}"
        ".h{opacity:0}.cu{transform-box:fill-box;transform-origin:100% 50%}"
        ".qw{transform-box:fill-box;transform-origin:50% 60%}"
        + "".join(A.rules)
        + "@media (prefers-reduced-motion:reduce){*{animation:none!important}}"
    )
    defs = (
        '<filter id="blur" x="-10%" y="-10%" width="120%" height="130%">'
        '<feGaussianBlur stdDeviation="9"/></filter>'
        '<radialGradient id="oc" cx="50%" cy="38%" r="75%">'
        '<stop offset="0" stop-color="#3b4252"/><stop offset=".6" stop-color="#232833"/>'
        '<stop offset="1" stop-color="#14171d"/></radialGradient>'
        '<linearGradient id="drv" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#d9dee6"/><stop offset="1" stop-color="#8d96a3"/>'
        '</linearGradient>'
        + G.defs())
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}" role="img" aria-label="Running alcatraz: docker run downloads '
        f'the macOS recovery image, creates the disk and opens QEMU on the OpenCore picker">'
        f"<style>{css}</style><defs>{defs}</defs>"
        + "".join(body)
        + f'<g class="{fade}">' + "".join(dyn) + "</g></svg>")


def main():
    outdir = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent)
    for name in THEMES:
        svg = build(name)
        p = outdir / f"demo-{name}.svg"
        p.write_text(svg)
        print(f"{p} {len(svg.encode()) / 1024:.1f} KB")


if __name__ == "__main__":
    main()
