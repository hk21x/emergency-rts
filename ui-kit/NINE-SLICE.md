# Nine-slice reference

Blank frames are built so corners stay crisp when stretched. In Godot 4 use a
`StyleBoxTexture` and set `texture_margin_*`; in CSS use `border-image-slice`.

| Asset | L | T | R | B |
|---|---|---|---|---|
| 01-menu/menu-item-*.svg | 8 | 8 | 8 | 8 |
| 01-menu/menu-container.svg | 12 | 12 | 12 | 12 |
| 01-menu/version-plate.svg | 8 | 8 | 8 | 8 |
| 02-topbar/topbar-frame.svg | 10 | 10 | 10 | 10 |
| 03-panels/panel.svg | 10 | 10 | 10 | 10 |
| 03-panels/panel-inset.svg | 8 | 8 | 8 | 8 |
| 03-panels/section-frame.svg | 10 | 48 | 10 | 10 |
| 03-panels/window.svg | 10 | 46 | 10 | 10 |
| 03-panels/dialog.svg | 12 | 12 | 12 | 12 |
| 04-buttons/large/*.svg | 8 | 8 | 8 | 8 |
| 04-buttons/small/*.svg | 6 | 6 | 6 | 6 |
| 04-buttons/icon-tile-*.svg | 12 | 12 | 12 | 12 |
| 04-buttons/command-button-*.svg | 8 | 8 | 8 | 8 |
| 06-notifications/notification-*-blank.svg | 40 | 8 | 40 | 8 |
| 06-notifications/tooltip.svg | 12 | 12 | 12 | 22 |
| 07-bars/bar-track.svg, bar-fill-*.svg | 3 | 3 | 3 | 3 |
| 08-controls/dropdown-closed.svg | 8 | 8 | 8 | 8 |
| 08-controls/tab-*.svg | 10 | 10 | 10 | 4 |
| 09-hud/unit-selection-panel.svg | 10 | 34 | 10 | 10 |

Notification frames need a 40px left margin so the coloured icon tab never
stretches. Multiply every margin by the export scale: a 12px margin on the 1x
source is 24px on `png-2x`.

Circular pieces — radio buttons, slider grabbers, status dots — must not be
nine-sliced. Export those at the size you need.
