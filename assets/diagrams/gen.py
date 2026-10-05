#!/usr/bin/env python3
"""Generate arch/flow SVGs (with <text>) for light and dark; build.sh outlines text."""
ACCENT = "#E8590C"  # the one accent hex; swap in the built SVGs with sed
THEMES = {
    "light": dict(text="#1f2328", muted="#59636e", line="#8c959f", border="#d1d9e0",
                  fill="#f6f8fa", fill2="#ffffff", chip="#eaeef2"),
    "dark":  dict(text="#e6edf3", muted="#9198a1", line="#6e7681", border="#3d444d",
                  fill="#151b23", fill2="#0d1117", chip="#212830"),
}
SANS = "Noto Sans"
MONO = "JetBrainsMono Nerd Font"

def esc(s): return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

class S:
    def __init__(s, t): s.t, s.o = t, []
    def rect(s, x, y, w, h, fill, stroke, r=8, dash=None, sw=1.5, op=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        o = f' fill-opacity="{op}"' if op is not None else ""
        s.o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"{o} stroke="{stroke}" stroke-width="{sw}"{d}/>')
    def text(s, x, y, txt, size=13, w=400, color=None, anchor="start", mono=False):
        f = MONO if mono else SANS
        s.o.append(f'<text x="{x}" y="{y}" font-family="{f}" font-size="{size}" font-weight="{w}" fill="{color or s.t["text"]}" text-anchor="{anchor}">{esc(txt)}</text>')
    def line(s, pts, color=None, arrow=True, dash=None, sw=1.5):
        c = color or s.t["line"]
        p = " ".join(f"{x},{y}" for x, y in pts)
        d = f' stroke-dasharray="{dash}"' if dash else ""
        s.o.append(f'<polyline points="{p}" fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"{d}/>')
        if arrow:
            (x1, y1), (x2, y2) = pts[-2], pts[-1]
            import math
            a = math.atan2(y2 - y1, x2 - x1); L = 8
            p1 = (x2 - L*math.cos(a - 0.45), y2 - L*math.sin(a - 0.45))
            p2 = (x2 - L*math.cos(a + 0.45), y2 - L*math.sin(a + 0.45))
            s.o.append(f'<polygon points="{x2},{y2} {p1[0]:.1f},{p1[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}" fill="{c}"/>')
    def badge(s, cx, cy, txt, color, textcolor="#ffffff"):
        w = 9 + 7.2 * len(txt)
        s.rect(cx - w/2, cy - 10, w, 20, color, color, r=10, sw=1)
        s.text(cx, cy + 4, txt, 11.5, 600, textcolor, "middle", mono=True)
    def chip(s, x, y, txt):
        w = 16 + 7.0 * len(txt)
        s.rect(x, y, w, 22, s.t["chip"], s.t["border"], r=11, sw=1)
        s.text(x + w/2, y + 15, txt, 11.5, 500, s.t["text"], "middle", mono=True)
        return w
    def svg(s, w, h, title):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                f'<title>{esc(title)}</title>' + "".join(s.o) + "</svg>\n")

def arch(t):
    s = S(t); A = ACCENT
    # Apple recovery servers
    s.rect(560, 8, 216, 50, t["fill"], t["border"], r=25)
    s.text(668, 30, "Apple recovery servers", 13.5, 600, anchor="middle")
    s.text(668, 47, "macOS recovery images", 11.5, color=t["muted"], anchor="middle")
    # Linux host
    s.rect(24, 76, 766, 392, t["fill2"], t["line"], r=14, sw=1.5)
    s.text(42, 101, "Linux host", 15, 700)
    s.chip(334, 86, "/dev/kvm")
    s.chip(420, 86, "X11 display")
    # container
    s.rect(90, 126, 446, 326, t["fill"], t["border"], r=12, dash="6 4")
    s.text(108, 150, "Docker container", 14, 700)
    s.text(232, 150, "Arch Linux", 12, color=t["muted"])
    # entrypoint & bootdisk
    s.rect(108, 172, 152, 62, t["fill2"], t["border"])
    s.text(184, 196, "entrypoint.sh", 13, 600, anchor="middle", mono=True)
    s.text(184, 214, "prepares /data,", 11.5, color=t["muted"], anchor="middle")
    s.text(184, 228, "picks a bootdisk", 11.5, color=t["muted"], anchor="middle")
    s.rect(108, 254, 152, 62, t["fill2"], t["border"])
    s.text(184, 278, "OpenCore bootdisk", 13, 600, anchor="middle")
    s.text(184, 296, "from OSX-KVM,", 11.5, color=t["muted"], anchor="middle")
    s.text(184, 310, "or built at start", 11.5, color=t["muted"], anchor="middle")
    # QEMU
    s.rect(290, 172, 228, 262, t["fill2"], t["border"])
    s.text(306, 196, "QEMU + OVMF", 14, 700)
    s.text(306, 213, "q35 VM, KVM-accelerated", 11.5, color=t["muted"])
    # guest
    s.rect(308, 236, 192, 156, A, A, r=10, op=0.14, sw=2)
    s.text(404, 300, "macOS guest", 16, 700, anchor="middle")
    s.text(404, 320, "installed from the", 11.5, color=t["muted"], anchor="middle")
    s.text(404, 335, "recovery image", 11.5, color=t["muted"], anchor="middle")
    # arrows inside container
    s.line([(260, 203), (290, 203)])
    s.line([(260, 285), (290, 285)])
    # KVM / X11 links
    s.line([(372, 108), (372, 172)], dash="3 3", arrow=False)
    s.line([(468, 108), (468, 172)], dash="3 3", arrow=False)
    # /data volume
    s.rect(560, 172, 214, 244, t["fill"], t["border"], r=12)
    s.text(578, 198, "/data", 15, 700, mono=True)
    s.text(630, 198, "volume", 12, color=t["muted"])
    s.text(578, 215, "a host directory, e.g. ./mac", 11.5, color=t["muted"])
    files = [("disk.qcow2", "macOS disk"), ("installer.img", "recovery image"),
             ("ovmf-vars.fd", "UEFI variables"), ("serials.env", "serial numbers")]
    for i, (f, d) in enumerate(files):
        y = 232 + i * 44
        s.rect(574, y, 186, 36, t["fill2"], t["border"], r=6, sw=1)
        s.text(586, y + 16, f, 12, 600, mono=True)
        s.text(586, y + 30, d, 10.5, color=t["muted"])
    # Apple -> installer.img
    s.line([(668, 58), (668, 172)], color=A, sw=2)
    s.text(676, 120, "first start", 11.5, 600, color=t["muted"])
    # /data -> QEMU
    s.line([(560, 300), (518, 300)])
    s.text(539, 292, "drives", 10.5, color=t["muted"], anchor="middle")
    # SSH port path
    y = 440
    s.line([(4, y), (340, y), (340, 392)], color=A, sw=2)
    s.badge(24, y, "50922", A)
    s.badge(90, y, "10022", A)
    s.badge(340, 414, ":22", A)
    s.text(152, y - 7, "SSH", 11.5, 600, color=t["muted"])
    return s.svg(800, 476, "alcatraz architecture")

def flow(t):
    s = S(t); A = ACCENT
    steps = [("1", "Download", "recovery image", "first start"),
             ("2", "Create disk", "empty 256 GB qcow2", "first start"),
             ("3", "Build bootdisk", "serials, config.plist,", "if set, every start"),
             ("4", "QEMU boots", "OpenCore picker", "every start"),
             ("5", "Install macOS", "from Base System", "you, once")]
    w, gap, x0 = 144, 20, 6
    for i, (n, a, b, c) in enumerate(steps):
        x = x0 + i * (w + gap)
        last = i == len(steps) - 1
        if last:
            s.rect(x, 6, w, 96, A, A, r=10, op=0.14, sw=2)
        else:
            s.rect(x, 6, w, 96, t["fill"], t["border"], r=10)
        s.o.append(f'<circle cx="{x+20}" cy="28" r="10" fill="{A}"/>')
        s.text(x + 20, 32, n, 11.5, 700, "#ffffff", "middle")
        s.text(x + 36, 33, a, 13.5, 700)
        s.text(x + 14, 56, b, 11.5, color=t["muted"])
        if i == 2:
            s.text(x + 14, 71, "APPLEID_PATCH, size", 11.5, color=t["muted"])
        s.text(x + 14, 92, c, 11, 600, color=A if c.startswith("first") or c.startswith("you") else t["muted"])
        if not last:
            s.line([(x + w + 3, 54), (x + w + gap - 3, 54)])
    return s.svg(6 + 5 * w + 4 * gap + 6, 108, "alcatraz first start")

for name, t in THEMES.items():
    open(f"src-arch-{name}.svg", "w").write(arch(t))
    open(f"src-flow-{name}.svg", "w").write(flow(t))
