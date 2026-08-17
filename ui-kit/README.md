# Emergency Ops — UI kit

210 individually downloadable elements rebuilt as clean vectors from the
style-sheet mockup, plus a working Godot 4 project that uses them.

| Category | Assets |
|---|---|
| Bars | 10 |
| Buttons | 60 |
| Controls | 24 |
| HUD | 8 |
| Icons | 44 |
| Main menu | 15 |
| Misc | 21 |
| Notifications | 10 |
| Panels | 10 |
| Top bar | 8 |

```
svg/                  source vectors — edit these
png-1x/ png-2x/ png-4x/   raster exports
godot-icons/          icons pre-filled white for Godot's importer
tokens/               tokens.json + tokens.css
NINE-SLICE.md         stretch margins for every blank frame
manifest.json         every asset with size, category and note
ui-kit-preview.html   open in a browser to download elements one at a time
```

The Godot project ships alongside this folder as `godot-emergency-ops/`.

## Blank vs example

Blank frames carry no text — those are what you ship, because the engine draws
the label and the same asset then serves any string length or language.
Anything under an `examples/` folder is a spacing spec showing intended type
sizes and icon placement, not runtime art.

## Two gotchas worth knowing

Godot's SVG importer is ThorVG. It **ignores `<text>`**, so the labelled
examples import blank — expected, and why the blank/example split exists. It
also **can't resolve `currentColor`**, which is how `svg/05-icons/` is drawn, so
white copies live in `godot-icons/`. Tint those with `modulate`.

## Typography

Rajdhani for display, headings and button labels; Barlow for body copy. Both are
SIL Open Font License and are bundled in the Godot project under
`ui/fonts/` with their licences. Install them locally before re-exporting PNGs
from the live-text examples, or the metrics will shift.

## On the source mockup

The mockup carried an existing commercial game's title and studio copyright
line. Those aren't reproduced here — `01-menu/title-plate.svg` is an empty slot
sized to the menu column for your own logo, and the version plate reads
"Your studio name". Everything else is generic interface furniture.
