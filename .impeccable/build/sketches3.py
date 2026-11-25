import pathlib, importlib.util, math, contextlib, io
here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("s1", here / "sketches.py"); s1 = importlib.util.module_from_spec(spec)
with contextlib.redirect_stdout(io.StringIO()): spec.loader.exec_module(s1)
SQ, arrow, page, OUT = s1.SQ, s1.arrow, s1.page, s1.OUT

def polar(cx, cy, r, deg):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy - r * math.sin(a)

def arc(cx, cy, r, a0, a1):
    x0, y0 = polar(cx, cy, r, a0); x1, y1 = polar(cx, cy, r, a1)
    large = 1 if abs(a0 - a1) > 180 else 0
    return f"M{x0:.1f} {y0:.1f}A{r} {r} 0 {large} 1 {x1:.1f} {y1:.1f}"

def gauge():
    cx, cy, r = 512, 560, 300
    # 220 deg sweep from 200 (lower left) to -20 (lower right); in-range band is a wider, brighter stroke
    zones = [(200, 150, "#8e8e93", 34), (150, 30, "#ffffff", 58), (30, -20, "#8e8e93", 34)]
    arcs = "".join(f'<path d="{arc(cx, cy, r, a0, a1)}" fill="none" stroke="{c}" stroke-width="{w}" stroke-linecap="butt"/>' for a0, a1, c, w in zones)
    ticks = ""
    for d in range(200, -21, -20):
        x0, y0 = polar(cx, cy, r - 60, d); x1, y1 = polar(cx, cy, r - 92, d)
        ticks += f'<path d="M{x0:.1f} {y0:.1f}L{x1:.1f} {y1:.1f}" stroke="#ffffff" stroke-opacity=".45" stroke-width="8" stroke-linecap="round"/>'
    nx, ny = polar(cx, cy, r - 40, 72)
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3d44"/><stop offset="1" stop-color="#16171b"/></linearGradient>
<linearGradient id="n" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5ee7a8"/><stop offset="1" stop-color="#1fb57a"/></linearGradient></defs>
<path d="{SQ}" fill="url(#g)"/>
<path d="{SQ}" fill="none" stroke="#fff" stroke-opacity=".14" stroke-width="4"/>
{arcs}{ticks}
<path d="M{cx} {cy}L{nx:.1f} {ny:.1f}" stroke="url(#n)" stroke-width="30" stroke-linecap="round"/>
<circle cx="{cx}" cy="{cy}" r="44" fill="#1fb57a"/><circle cx="{cx}" cy="{cy}" r="16" fill="#16171b"/>
<text x="512" y="800" text-anchor="middle" font-family="-apple-system, 'SF Pro Rounded', system-ui" font-weight="700" font-size="120" fill="#ffffff">112</text>
</svg>'''

def trend():
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="f" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffb340"/><stop offset="1" stop-color="#f2701d"/></linearGradient>
<linearGradient id="hi" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".35"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>
<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#7a2c00" flood-opacity=".35"/></filter></defs>
<path d="{SQ}" fill="url(#f)"/><path d="{SQ}" fill="url(#hi)"/>
<g filter="url(#sh)">{arrow(512, 512, 470, -45, "#ffffff", 96)}</g>
</svg>'''

def monogram():
    # a rounded G: 300 deg ring open at upper right; its crossbar continues out as a rising arrow
    cx, cy, r = 490, 540, 250
    x0, y0 = polar(cx, cy, r, 35)
    x1, y1 = polar(cx, cy, r, -10)
    path = f"M{x0:.1f} {y0:.1f}A{r} {r} 0 1 0 {x1:.1f} {y1:.1f}"
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5b5ff0"/><stop offset="1" stop-color="#2f2aa8"/></linearGradient></defs>
<path d="{SQ}" fill="url(#f)"/>
<path d="{path}" fill="none" stroke="#fff" stroke-width="92" stroke-linecap="round"/>
{arrow((cx + x1) / 2 + 30, y1, 290, 0, "#7ef0c2", 72)}
</svg>'''

def glyph(kind):
    g = {"gauge": '<svg width="30" height="24" viewBox="0 0 30 24"><path d="M4 20A12 12 0 1 1 26 20" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><path d="M15 17L19 8" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><circle cx="15" cy="17" r="2.6" fill="currentColor"/></svg>',
         "trend": '<svg width="24" height="24" viewBox="0 0 24 24"><path d="M5 19L19 5M9 5h10v10" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
         "mono": '<svg width="26" height="26" viewBox="0 0 26 26"><path d="M19 7A9 9 0 1 0 21 15H13" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round"/><path d="M18 9l5-5m-4 0h4v4" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'}
    return g[kind]

for name, svg, g in [("r2-gauge", gauge(), "gauge"), ("r2-trend", trend(), "trend"), ("r2-monogram", monogram(), "mono")]:
    (OUT / f"{name}.html").write_text(page(name, svg, glyph(g)))
print("ok")
