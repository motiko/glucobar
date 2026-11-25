# Design

## Identity: Instrument Gauge

GlucoBar's mark is a dial you glance at, the way you glance at the clock beside it. It is
deliberately not the diabetes-app default (a wavy CGM line on blue, blood drops) and carries
nothing that could pass for an Abbott, Libre or medical-device mark.

- **App icon** (`App/AppIcon.icon`, Icon Composer format): graphite squircle, a 240-degree dial,
  and one green needle resting inside the target range. Two layer groups: `needle` (glass) above
  `dial` (flat). The system supplies the mask, specular glass, and the dark, tinted and clear
  appearances; dark mode uses a deeper graphite fill.
- **Menu bar glyph** (`MenuBarLabel.gauge`): the same dial as an 18x16 monochrome template,
  shown only while there is no Reading (signed out, first fetch). Once a Reading exists the
  number takes its place: the number is the product.

## Rules

- Range reads by shape, not colour: the target-range arc is about twice as thick as the
  out-of-range arcs, in the icon and the glyph alike.
- No numbers in the icon. A fixed value would be a fake Reading, and it turns to mush below
  64 px.
- One accent: needle green (#5ee7a8 to #1fb57a). Red and orange stay reserved for Alerts
  and out-of-range text in the menu bar.

| Token | Value |
|---|---|
| Graphite, light fill | #42454d to #16171b |
| Graphite, dark fill | #232429 to #0a0b0d |
| Target-range arc | #ffffff, 84 on a 1024 canvas |
| Out-of-range arcs | #9a9ca3, 44 |
| Ticks | white at 50%, 12 |
| Needle and hub | #5ee7a8 to #1fb57a |

## Provenance

`.impeccable/build/icon.py` generates the layer SVGs and `icon.json`; edit the script, not the
output, then rerun it. Xcode's asset compiler renders every shipping raster (`AppIcon.icns`,
`Assets.car`) from that file at build time. No hand-painted or generated bitmaps ship.
