# Generates App/AppIcon.icon (Icon Composer format) for the Instrument Gauge direction.
# Layers are SVGs on a 1024 canvas; the system applies the squircle mask, glass and appearances.
import json, math, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
ICON = ROOT / "App" / "AppIcon.icon"
ASSETS = ICON / "Assets"
CX, CY, R = 512, 610, 360
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'

def polar(r, deg):
    a = math.radians(deg)
    return CX + r * math.cos(a), CY - r * math.sin(a)

def arc(r, a0, a1):
    (x0, y0), (x1, y1) = polar(r, a0), polar(r, a1)
    return f"M{x0:.1f} {y0:.1f}A{r} {r} 0 {1 if abs(a0 - a1) > 180 else 0} 1 {x1:.1f} {y1:.1f}"

def dial():
    # out-of-range arcs thin and grey, in-range arc wide and white: range reads by width, not colour
    out = [f'<path d="{arc(R, 210, 150)}" fill="none" stroke="#9a9ca3" stroke-width="44"/>',
           f'<path d="{arc(R, 30, -30)}" fill="none" stroke="#9a9ca3" stroke-width="44"/>',
           f'<path d="{arc(R, 148, 32)}" fill="none" stroke="#ffffff" stroke-width="84"/>']
    for d in range(210, -31, -20):
        (x0, y0), (x1, y1) = polar(R - 78, d), polar(R - 116, d)
        out.append(f'<path d="M{x0:.1f} {y0:.1f}L{x1:.1f} {y1:.1f}" stroke="#ffffff" stroke-opacity=".5" stroke-width="12" stroke-linecap="round"/>')
    return HEAD + "".join(out) + "</svg>"

def needle():
    nx, ny = polar(R - 50, 70)
    return HEAD + f'''<defs><linearGradient id="n" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#5ee7a8"/><stop offset="1" stop-color="#1fb57a"/></linearGradient></defs>
<path d="M{CX} {CY}L{nx:.1f} {ny:.1f}" stroke="url(#n)" stroke-width="48" stroke-linecap="round"/>
<circle cx="{CX}" cy="{CY}" r="66" fill="url(#n)"/></svg>'''

def layer(name, glass, opacity=1):
    return {"blend-mode": "normal", "fill": "none", "glass": glass,
            "image-name": f"{name}.svg", "name": name, "opacity": opacity}

def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    for name, svg in [("dial", dial()), ("needle", needle())]:
        (ASSETS / f"{name}.svg").write_text(svg)
    group = lambda layers: {"blend-mode": "normal", "hidden": False, "layers": layers, "lighting": "individual",
                            "opacity": 1, "shadow": {"kind": "neutral", "opacity": 0.5}, "specular": True,
                            "translucency": {"enabled": True, "value": 0.4}}
    spec = {
        "fill-specializations": [
            {"value": {"linear-gradient": ["extended-srgb:0.25882,0.27059,0.30196,1.00000",
                                           "extended-srgb:0.08627,0.09020,0.10588,1.00000"]}},
            {"appearance": "dark",
             "value": {"linear-gradient": ["extended-srgb:0.13725,0.14118,0.16078,1.00000",
                                           "extended-srgb:0.03922,0.04314,0.05098,1.00000"]}},
        ],
        "groups": [group([layer("needle", True)]),
                   group([layer("dial", False)])],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (ICON / "icon.json").write_text(json.dumps(spec, indent=2) + "\n")
    print(ICON)

main()
