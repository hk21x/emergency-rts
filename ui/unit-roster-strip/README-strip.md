# Unit roster strip

The bottom bar's fleet view as a standalone, dockable component. One card per
unit, scrolled sideways, clickable.

Ships two ways: as the roster mode inside `UnitSelectionPanel` (now the default),
and as `selection_panel/unit_roster_strip.tscn` on its own.

## Run it

Open `selection-panel-godot/` in Godot 4.4 and press **F5**. Press **Deselect**
to drop into the strip.

## Use it standalone

```gdscript
var strip := preload("res://selection_panel/unit_roster_strip.tscn").instantiate()
dock.add_child(strip)          # needs about 1100 x 140
strip.set_units(all_units)
strip.unit_picked.connect(func(u): select(u))
strip.unit_focused.connect(func(u): camera.centre_on(u))   # double-click
strip.select(current_unit)     # scrolls it into view
strip.refresh()                # after mutating units in place
```

## Sorting is what makes a strip work

A strip can't show a large fleet at once, so what sits on the left matters more
than in any other layout. Four modes, `URGENCY` by default:

| Mode | Order |
|---|---|
| URGENCY | damaged first, then on scene, en route, returning, available |
| STATUS | strict status bands, callsign within each |
| SERVICE | fire, police, medical, support |
| CALLSIGN | plain alphabetical |

URGENCY deliberately ranks damage *above* status: a wrecked engine sitting
"available" wants looking at before a healthy one that happens to be on scene.
Verified order on the sample fleet:

    F02 (off run) · A14, P21 (on scene) · F01, F03 (en route)
    · S02 (returning) · A15, F04, H01, P22, P23, S01 (available)

That's the mitigation for the strip's one real weakness. The units you need are
never the ones you have to scroll to find.

## Scrolling

- **Mouse wheel scrolls horizontally.** A horizontal `ScrollContainer` ignores
  the wheel by default, which feels broken the first time anyone tries it.
- **Edge chevrons** appear only when there's something off-view and disable
  themselves at each end. One press moves `page_cards` (default 3), tweened.
- **The scrollbar is hidden** (`SHOW_NEVER`) — it was drawing across the bottom
  of the cards, over the condition bars. The chevrons make the affordance.
- **Keyboard and gamepad** walk the row for free, because cards are focusable
  siblings in an `HBoxContainer`. Focus scrolls the viewport to follow.
- **Selection scrolls into view** when set from outside, so picking a unit on
  the map highlights the right card without the player hunting.
- **Changing sort resets scroll to the start** — otherwise you're left looking
  at an arbitrary window of a new ordering.

## The card

Status stripe and label, portrait, callsign, type, condition bar and seats
taken. The status word is on the card rather than colour-only, so a new player
doesn't have to learn five colours before the strip is readable.

Three visual states: normal, alert (damaged or off run — red border) and
selected (accent border). Alert beats nothing else; selection beats alert, so a
selected damaged unit still reads as selected.

## Exports

`sort_mode`, `card_width` (116), `follow_selection`, `page_cards`,
`preview_in_editor`. The script is `@tool`, so the strip shows a sample fleet in
the editor while you lay the HUD out.
