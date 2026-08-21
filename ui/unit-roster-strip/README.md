# Unit selection panel — standalone

The single-unit selection panel as a self-contained Godot 4.4 component. No
sidebar, no purchase modal, no multi-select branching — just the panel.

## Run it

Open this folder in Godot 4.4 and press **F5**. The demo gives you sliders for
health and liquid, a unit-type picker, status cycling, and buttons to put people
in and out of seats, so you can watch the panel react.

## Drop it into your project

Copy the `selection_panel/` folder across. That's everything: art, fonts, theme,
data classes, script and scene.

```gdscript
var panel := preload("res://selection_panel/unit_selection_panel.tscn").instantiate()
bottom_dock.add_child(panel)
panel.show_unit(my_unit)
panel.command_issued.connect(func(action: StringName, unit: UnitInstance):
    issue_order(action, unit))
```

The panel does not poll. After mutating a unit in place — damage, a casualty
loaded, water used — call `panel.refresh()`.

### If you already have the full Emergency Ops project

Two things will collide, both easy:

- `selection_panel/data/unit_def.gd` and `unit_instance.gd` declare `UnitDef`
  and `UnitInstance`. Delete both files; the panel only reads properties your
  versions already have.
- `selection_panel/theme/selection_panel.tres` duplicates variations your main
  theme already defines. Delete it and clear the scene's `theme` override.

## Editor preview

The script is `@tool`, so dropping the scene into a layout shows a populated
panel in the editor rather than an empty box. Turn off `preview_in_editor` on
the node if you'd rather see the empty state while designing.

## What it shows

**Health** — bar plus percentage, green above 60%, amber above 35%, red below.

**Occupancy** — every seat drawn, filled or empty, coloured by role: driver
grey, firefighter orange, paramedic green, officer blue, casualty amber,
civilian a pale outline. Count top-right, role tally underneath, hover a seat to
name the role. Colour is the primary signal; the glyphs are 16px on the pips and
act as a second read.

**Liquid** — only rendered when `UnitDef.carries_liquid` is true. Ambulances and
patrol cars show no chip at all rather than an empty one.

**Current order** — status, task text, and a progress bar that hides itself when
`order_progress` is negative.

**Commands** — eight actions, gated by unit category. A fire engine gets
extinguish and rescue; a patrol car gets secure. Unavailable orders lose colour
*and* alpha, because at the standard disabled grey a chunky glyph like the
medical cross still reads as live while a thin one like the cone reads as dead.

## Sizing

1100x188. Four zones: identity 416, occupancy 200, order 170, commands 194. The
seat strip caps at two rows (`seat_columns` x 2) and spills the rest into a `+N`,
so a large-capacity unit can't stretch the panel. If you need it narrower, drop
the order zone first.

## Fonts

Rajdhani and Barlow, both SIL Open Font License, bundled with their licences in
`selection_panel/fonts/`.
