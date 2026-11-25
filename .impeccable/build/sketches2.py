import pathlib, importlib.util
here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("s1", here / "sketches.py"); s1 = importlib.util.module_from_spec(spec)
import contextlib, io
with contextlib.redirect_stdout(io.StringIO()): spec.loader.exec_module(s1)
SQ, arrow, page, OUT = s1.SQ, s1.arrow, s1.page, s1.OUT

def illuminated():
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f3d57a"/><stop offset=".45" stop-color="#c99a2e"/><stop offset=".7" stop-color="#e9c35a"/><stop offset="1" stop-color="#9c7020"/></linearGradient></defs>
<path d="{SQ}" fill="#f1e6cc"/>
<rect x="190" y="190" width="520" height="520" rx="18" fill="url(#gold)"/>
<rect x="214" y="214" width="472" height="472" rx="10" fill="none" stroke="#7a5414" stroke-width="6" opacity=".5"/>
<text x="450" y="600" text-anchor="middle" font-family="Georgia, 'Times New Roman', serif" font-weight="700" font-size="470" fill="#c0352b">G</text>
<path d="M560 520C620 560 640 640 610 700S560 820 650 830S780 740 790 640S760 470 830 380" fill="none" stroke="#1f4fa8" stroke-width="30" stroke-linecap="round"/>
<g fill="#1f4fa8"><path d="M640 770c40-30 80-20 96 6-40 22-76 18-96-6z"/><path d="M770 560c-6-44 20-76 52-80 8 40-14 70-52 80z"/></g>
<path d="M830 380l-70 6m70-6l-8 70" fill="none" stroke="#1f4fa8" stroke-width="30" stroke-linecap="round"/>
<circle cx="250" cy="790" r="22" fill="#c0352b"/><circle cx="310" cy="830" r="14" fill="#c99a2e"/>
</svg>'''

SEG = {"a": "M14 4h52l-8 8H22z", "b": "M68 6v52l-8-6V14z", "c": "M68 66v52l-8-8V72z", "d": "M14 120h52l-8-8H22z",
       "e": "M12 66v52l8-8V72z", "f": "M12 6v52l8-6V14z", "g": "M16 62h48l-6 5H22l-6-5zM16 62l6-5h36l6 5z"}
DIG = {"1": "bc", "2": "abged"}
def sevenseg():
    out = []
    for i, ch in enumerate("112"):
        g = []
        for s, d in SEG.items():
            lit = s in DIG[ch]
            g.append(f'<path d="{d}" fill="{"#ff3b30" if lit else "#231010"}" {"filter=\"url(#glow)\"" if lit else ""}/>')
        out.append(f'<g transform="translate({170 + i*210} 300) scale(2.6)">{"".join(g)}</g>')
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.2" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2a2e"/><stop offset="1" stop-color="#121114"/></linearGradient></defs>
<path d="{SQ}" fill="url(#body)"/>
<rect x="150" y="250" width="724" height="430" rx="40" fill="#0b0708"/>
{''.join(out)}
<g filter="url(#glow)">{arrow(760, 790, 150, -45, "#ff3b30", 26)}</g>
<circle cx="230" cy="790" r="16" fill="#231010"/><circle cx="290" cy="790" r="16" fill="#ff3b30" filter="url(#glow)"/>
</svg>'''

def onebit():
    W = 32
    grid = [[0]*W for _ in range(W)]
    for y in range(W):
        for x in range(W):
            grid[y][x] = 1 if (x + y) % 2 == 0 else 0  # 50% dither desktop
    for y in range(0, 3):  # menu bar
        for x in range(W): grid[y][x] = 0
    for x in range(W): grid[3][x] = 1
    def rect(x0, y0, x1, y1, v):
        for y in range(y0, y1+1):
            for x in range(x0, x1+1): grid[y][x] = v
    rect(4, 7, 27, 26, 0)
    for x in range(4, 28): grid[7][x] = grid[26][x] = 1
    for y in range(7, 27): grid[y][4] = grid[y][27] = 1
    for y in (9, 11): 
        for x in range(6, 26): grid[y][x] = 1
    rect(13, 8, 18, 12, 0); rect(14, 9, 17, 11, 0)
    for x in range(4, 28): grid[13][x] = 1
    F = {"1": ["010", "110", "010", "010", "111"], "2": ["111", "001", "111", "100", "111"]}
    for i, ch in enumerate("112"):
        for r, row in enumerate(F[ch]):
            for c, v in enumerate(row):
                if v == "1": rect(7 + i*4 + c, 16 + r, 7 + i*4 + c, 16 + r, 1)
    for (x, y) in [(20,20),(21,19),(22,18),(23,17),(23,18),(22,17),(21,17),(23,19)]:
        grid[y][x] = 1
    # menu bar: tiny reading at top right
    for (x, y) in [(26,1),(27,1),(28,1),(30,1),(29,1)]: grid[y][x] = 1
    px = 824 / W
    cells = "".join(f'<rect x="{100+x*px:.2f}" y="{100+y*px:.2f}" width="{px+0.5:.2f}" height="{px+0.5:.2f}"/>'
                    for y in range(W) for x in range(W) if grid[y][x])
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges">
<defs><clipPath id="c"><path d="{SQ}"/></clipPath></defs>
<path d="{SQ}" fill="#ffffff"/><g clip-path="url(#c)" fill="#000">{cells}</g>
<path d="{SQ}" fill="none" stroke="#000" stroke-width="10"/></svg>'''

def akari():
    ribs = "".join(f'<path d="M{330} {y}Q512 {y + (y-512)*0.06 + 14} {694} {y}" fill="none" stroke="#b08a55" stroke-width="5" opacity=".7"/>' for y in range(300, 740, 48))
    return f'''<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
<defs><radialGradient id="room" cx=".5" cy=".5" r=".7"><stop offset="0" stop-color="#5a4330"/><stop offset="1" stop-color="#231b16"/></radialGradient>
<radialGradient id="paper" cx=".45" cy=".4" r=".6"><stop offset="0" stop-color="#fff8e6"/><stop offset=".7" stop-color="#f4dcae"/><stop offset="1" stop-color="#d9b47a"/></radialGradient>
<filter id="halo" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="40"/></filter></defs>
<path d="{SQ}" fill="url(#room)"/>
<ellipse cx="512" cy="520" rx="260" ry="290" fill="#ffd98a" opacity=".45" filter="url(#halo)"/>
<ellipse cx="512" cy="520" rx="200" ry="240" fill="url(#paper)"/>
<clipPath id="lc"><ellipse cx="512" cy="520" rx="200" ry="240"/></clipPath><g clip-path="url(#lc)">{ribs}</g>
<rect x="500" y="200" width="24" height="80" fill="#2a1f18"/>
<text x="512" y="575" text-anchor="middle" font-family="'Hiragino Sans', -apple-system, 'Helvetica Neue', sans-serif" font-weight="300" font-size="150" fill="#2a211b">112</text>
<rect x="640" y="660" width="86" height="86" rx="8" fill="#d6402a"/>
{arrow(683, 703, 52, -45, "#fff4e2", 10)}
</svg>'''

def glyph(kind):
    g = {"illum": '<svg width="28" height="28" viewBox="0 0 28 28"><text x="10" y="22" text-anchor="middle" font-family="Georgia" font-weight="700" font-size="22" fill="currentColor">G</text><path d="M16 20c4-2 3-8 7-12m0 0h-4m4 0v4" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>',
         "seg": '<svg width="40" height="24" viewBox="0 0 40 24"><path d="M4 3v8M4 13v8M12 3h8M20 4v7M12 12h8M12 13v8M12 21h8M30 18l7-7m-5 0h5v5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/></svg>',
         "bit": '<svg width="28" height="28" viewBox="0 0 8 8" shape-rendering="crispEdges"><path d="M0 0h8v1H0zM0 7h8v1H0zM0 0h1v8H0zM7 0h1v8H7zM0 2h8v1H0zM2 4h1v2H2zM4 4h2v1H4zM5 5h1v1H5z" fill="currentColor"/></svg>',
         "akari": '<svg width="24" height="30" viewBox="0 0 24 30"><ellipse cx="12" cy="16" rx="9" ry="11" fill="none" stroke="currentColor" stroke-width="2.4"/><path d="M5 12h14M4 16h16M5 20h14M12 1v4" stroke="currentColor" stroke-width="1.6"/></svg>'}
    return g[kind]

for name, svg, g in [("r1-assigned", illuminated(), "illum"), ("r1-sevenseg", sevenseg(), "seg"),
                     ("r1-onebit", onebit(), "bit"), ("r1-akari", akari(), "akari")]:
    (OUT / f"{name}.html").write_text(page(name, svg, glyph(g)))
print("ok")
