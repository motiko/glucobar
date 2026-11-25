# Generates the decision-round HTML sketches for the GlucoBar icon directions.
import pathlib
OUT = pathlib.Path(__file__).resolve().parents[1] / "mocks" / "decision"
SQ = "M100 285C100 165 165 100 285 100H739C859 100 924 165 924 285V739C924 859 859 924 739 924H285C165 924 100 859 100 739Z"
ARROW_UP_RIGHT = "M0 0"  # unused placeholder

def arrow(x, y, s, angle, color, w=None):
    # a trend arrow centred at (x,y), length s, rotated by angle (0 = pointing right)
    w = w or s * 0.16
    h = s / 2
    return (f'<g transform="translate({x} {y}) rotate({angle})" fill="none" stroke="{color}" '
            f'stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round">'
            f'<path d="M{-h} 0H{h}"/><path d="M{h - s*0.34} {-s*0.34}L{h} 0L{h - s*0.34} {s*0.34}"/></g>')

def menubar_corner():
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs>
 <linearGradient id="desk" x1="0" y1="0" x2="0.4" y2="1"><stop offset="0" stop-color="#3d63e6"/><stop offset="0.55" stop-color="#2440b4"/><stop offset="1" stop-color="#16246e"/></linearGradient>
 <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.62"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.30"/></linearGradient>
 <clipPath id="c"><path d="{SQ}"/></clipPath>
 <filter id="sh" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#0a1240" flood-opacity="0.45"/></filter>
</defs>
<g clip-path="url(#c)">
 <rect x="100" y="100" width="824" height="824" fill="url(#desk)"/>
 <circle cx="760" cy="860" r="380" fill="#5b7dff" opacity="0.28"/>
 <g filter="url(#sh)"><rect x="100" y="236" width="824" height="360" fill="url(#glass)"/></g>
 <rect x="100" y="236" width="824" height="3" fill="#fff" opacity="0.8"/>
</g>
<text x="168" y="512" font-family="-apple-system, 'SF Pro Rounded', system-ui" font-weight="800" font-size="248" letter-spacing="-8" fill="#ffffff">112</text>
{arrow(760, 432, 170, -45, "#ffffff", 34)}
<text x="830" y="770" text-anchor="end" font-family="-apple-system, 'Helvetica Neue', Helvetica, sans-serif" font-weight="600" font-size="112" fill="#ffffff" opacity="0.55">9:41</text>
<path d="{SQ}" fill="none" stroke="#ffffff" stroke-opacity="0.25" stroke-width="3"/>
</svg>'''

def reading_tile():
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2fc79a"/><stop offset="1" stop-color="#14896a"/></linearGradient></defs>
<path d="{SQ}" fill="url(#f)"/>
<text x="512" y="590" text-anchor="middle" font-family="-apple-system, system-ui" font-weight="800" font-size="300" letter-spacing="-10" fill="#fff">112</text>
{arrow(512, 740, 220, 0, "#ffffff", 40)}
</svg>'''

def split_flap():
    flap = lambda x, ch: f'''<g transform="translate({x} 300)"><rect width="250" height="424" rx="26" fill="#1a1a1c"/>
<rect y="210" width="250" height="4" fill="#000"/><text x="125" y="350" text-anchor="middle" font-family="'Helvetica Neue Condensed','Arial Narrow',system-ui" font-stretch="condensed" font-weight="700" font-size="330" fill="#f4f1ea">{ch}</text></g>'''
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="st" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d7d9dc"/><stop offset="1" stop-color="#9a9ea4"/></linearGradient></defs>
<path d="{SQ}" fill="url(#st)"/>
{flap(122,"1")}{flap(387,"1")}{flap(652,"2")}
<circle cx="870" cy="210" r="30" fill="#f2a516"/>
<g transform="translate(512 820)">{arrow(0,0,130,-45,"#1a1a1c",26)}</g>
</svg>'''

def bitmap():
    # 5x7 pixel digits
    D = {"1": ["00100","01100","00100","00100","00100","00100","01110"],
         "2": ["01110","10001","00001","00010","00100","01000","11111"]}
    px = 30; out = []
    def digit(ch, ox, oy):
        for r, row in enumerate(D[ch]):
            for c, v in enumerate(row):
                if v == "1": out.append(f'<rect x="{ox+c*px}" y="{oy+r*px}" width="{px}" height="{px}" fill="#111"/>')
    for i, ch in enumerate("112"): digit(ch, 190 + i*200, 300)
    arr = ["0011111","0000011","0000101","0001001","0010000","0100000","1000000"]
    for r, row in enumerate(arr):
        for c, v in enumerate(row):
            if v == "1": out.append(f'<rect x="{610+c*px}" y="{560+r*px}" width="{px}" height="{px}" fill="#ff4f1f"/>')
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<path d="{SQ}" fill="#f3f1ea"/>{''.join(out)}</svg>'''

def canon():
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2aa7d8"/><stop offset="1" stop-color="#1a5fb0"/></linearGradient></defs>
<path d="{SQ}" fill="url(#g)"/>
<rect x="100" y="430" width="824" height="200" fill="#ffffff" opacity="0.18"/>
<path d="M170 560C260 520 310 640 400 600S520 420 610 470S760 560 860 500" fill="none" stroke="#fff" stroke-width="34" stroke-linecap="round"/>
<circle cx="860" cy="500" r="34" fill="#fff"/>
</svg>'''

def page(name, svg, glyph):
    sizes = "".join(f'<div class="s"><div style="width:{s}px;height:{s}px">{svg}</div></div>' for s in (256, 128, 64, 32, 16))
    return f'''<!doctype html><html><head><meta charset="utf-8"><title>{name}</title><style>
html,body{{margin:0;width:1440px;height:900px;background:#e9e7e2;font-family:-apple-system,'Helvetica Neue',Helvetica,sans-serif;overflow:hidden}}
.big{{position:absolute;left:70px;top:60px;width:780px;height:780px}}
.big svg,.s svg{{width:100%;height:100%;display:block}}
.col{{position:absolute;left:900px;top:70px;width:470px}}
.row{{display:flex;align-items:flex-end;gap:26px;flex-wrap:wrap}}
.bar{{margin-top:56px;height:44px;border-radius:12px;background:rgba(255,255,255,.7);display:flex;align-items:center;justify-content:flex-end;gap:22px;padding:0 22px;font:600 26px -apple-system,'Helvetica Neue',Helvetica,sans-serif;color:#111}}
.dark{{background:#1d1d20;color:#f2f2f2}}
.dock{{margin-top:44px;padding:28px;border-radius:30px;background:#1b1c22;display:flex;gap:28px;align-items:center}}
.dock div{{width:128px;height:128px}}
</style></head><body>
<div class="big">{svg}</div>
<div class="col"><div class="row">{sizes}</div>
<div class="bar">{glyph}<span>Tue 9:41</span></div>
<div class="bar dark">{glyph}<span>Tue 9:41</span></div>
<div class="dock"><div>{svg}</div><span style="color:#ddd;font:600 30px -apple-system,'Helvetica Neue',Helvetica,sans-serif">GlucoBar</span></div>
</div></body></html>'''

def glyph(kind):
    if kind == "corner":
        return '<svg width="38" height="28" viewBox="0 0 38 28"><rect x="1" y="3" width="36" height="22" rx="5" fill="none" stroke="currentColor" stroke-width="2.4"/><path d="M11 18L24 9M17 9h7v7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    if kind == "tile":
        return '<svg width="30" height="30" viewBox="0 0 30 30"><path d="M5 15h18M17 9l6 6-6 6" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    if kind == "flap":
        return '<svg width="34" height="28" viewBox="0 0 34 28"><rect x="1" y="2" width="14" height="24" rx="3" fill="currentColor"/><rect x="19" y="2" width="14" height="24" rx="3" fill="currentColor"/><rect y="13" width="34" height="2" fill="#888"/></svg>'
    if kind == "bitmap":
        return '<svg width="28" height="28" viewBox="0 0 7 7" shape-rendering="crispEdges"><path d="M2 0h5v1H2zM6 1h1v2H6zM5 2h1v1H5zM4 3h1v1H4zM3 4h1v1H3zM2 5h1v1H2zM1 6h1v1H1zM0 7h1v-1H0z" fill="currentColor"/></svg>'
    return '<svg width="36" height="24" viewBox="0 0 36 24"><path d="M2 16C7 12 10 20 15 17S22 5 27 8 32 14 34 10" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/></svg>'

for name, svg, g in [("assigned", menubar_corner(), "corner"), ("pick", reading_tile(), "tile"),
                     ("challenger-flap", split_flap(), "flap"), ("challenger-bitmap", bitmap(), "bitmap"),
                     ("canon", canon(), "canon")]:
    (OUT / f"{name}.html").write_text(page(name, svg, glyph(g)))
print("ok")
