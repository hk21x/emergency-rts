# Emergency-RTS

An Emergency 4–style dispatch game. You run a small emergency service across one city
district: buy units, send them to calls, and get people treated, fires out and suspects
in custody before the shift ends.

Godot 4.x, pure GDScript, Forward+ renderer, **no build step** — clone it and press play.
Built on 4.6.3, verified on 4.7.

```
godot --path .                                            # play it
godot --headless --fixed-fps 60 --path . --script res://Game/smoke_test.gd   # test it
```

## Where it is

All twenty planned phases have landed except the last half of one: the career economy
shipped, **campaign scenarios have not**. What exists is a complete freeplay loop —
open a shift, take the calls it rolls, get scored on it — plus the district, the fleet,
the economy and the world that reacts to all three.

**650 automated checks**, all passing. The suite reports its own total; take the number
from a run rather than from here.

The one thing the tree knows is wrong: **vehicles corner too wide and sometimes overshoot
a junction.** It is diagnosed down to the line — the steering aims at a point past the
bend, so the car applies almost no lock and arcs across it — and a working fix exists that
breaks three unrelated checks. All of it, with numbers, is in `NEXT.md`.

## The district

One hand-built district, 260m square, generated from two deliberately irregular band
tables in `CityGrid.gd`. Everything derives from those two tables: roads, blocks,
junctions, addresses, parks, pavements, zebra crossings, where traffic drives, where the
crowd walks and where calls can open.

- **A police station and a hospital**, diagonally opposite each other, which is what makes
  the two services' journeys different lengths.
- **Ambient traffic** that keeps its lane, gives way at junctions, queues, pulls over for
  a vehicle on blues, and turns back at a police cordon.
- **A crowd on the pavements** that crosses at the zebras and never walks in the road. It
  is also where casualties come from — a medical call takes the shopper who was standing
  there, and the district quietly refills over time so a long career does not empty it.
- **A day cycle and rain.** Rain takes grip off every vehicle on the map, so the same
  corner is taken slower in the wet.

## Units and verbs

Six things to buy, three services. Capability is hard: a unit either has an ability or
does not, so a patrol car cannot put out a building fire however long you point it at one.

| | vehicles | on foot |
| --- | --- | --- |
| **Police** | Patrol car | Officer |
| **Medical** | Ambulance | Paramedic |
| **Fire** | Fire engine | Firefighter |

Every verb is an `Ability`, and adding one gives it a command tile, a hotkey and a
right-click meaning with no interface work. The current set:

`Move` · `Stop` · `Treat` · `Apprehend` · `Extinguish` · `Collect` (stretcher) ·
`Escort` (a suspect into the car) · `Secure` (a cordon) · `Board` · `Unload` ·
`Return` · `Lights` · `Siren`

Right-click does whatever scores highest on the thing under the cursor, so most play needs
no tiles at all. Units within range of an incident get on with the job themselves.

**Return** is contextual: an ambulance carrying a casualty goes to the hospital, a patrol
car with a suspect goes to custody, anything else goes home. A unit driving home is not on
a shout — it keeps to the limit and runs dark, which is the one order that does.

## The shift

Press **F2** and the district starts producing calls. Until then it idles: no scripted
incidents, nothing to react to.

Calls open on the street, not inside buildings. Fires spread to reachable ground only, and
a building fire needs a hose and a water tank behind it — an appliance that runs dry has
to be moved to a hydrant rather than waited out. Casualties are stabilised where they lie
and then stretchered aboard; they are not saved until they reach the hospital. Suspects
are detained and driven to the station.

The shift ends in a debrief and a score. Vehicles take damage from what you drive them
into, and repairs come out of the same purse the fleet is bought from.

## Controls

Also on **F1** in game, and on the CONTROLS chip beside it.

| | |
| --- | --- |
| **Select** | left-click · drag to box-select · `Shift` to add |
| **Order** | right-click · `Shift` to queue · `Esc` to cancel |
| **Command tiles** | `Z X C V B N M G H J K` |
| **Groups** | `Ctrl`+`1`…`9` to assign, the number alone to recall |
| **Camera** | `WASD` pan (`Shift` faster) · `Q`/`E` rotate · wheel zoom · middle-drag pan · `F` follow |
| **Minimap** | left-click to look, right-click to send |
| **Shift** | `F2` start · `P` pause · `R` respawn |
| **Diagnostics** | `F3` report a stuck unit · `F4` show what a unit is steering at |

## Layout

```
Game/
  Playground.tscn      the district — generated, see the .tscn rule below
  build_*.gd           the generators: map, vehicles, characters, civilians, audio…
  CityGrid.gd          the two band tables everything derives from
  Units/               Unit, Vehicle, Person + every Ability and Order
  Incidents/           Fire, Casualty, Suspect, Cordon, Hospital, CallBoard
  UI/                  HUD panels, minimap, menus, controls card
  Director.gd          freeplay — inert until a shift is opened
  Mission.gd           scoring
  StuckLog.gd          the black box (F3)
  NavDebug.gd          the navigation overlay (F4)
  smoke_test.gd        the suite
  diagnose_driving.gd  driving diagnostics
  probe_*.gd           focused probes for a specific fault
```

`Playground.tscn` and the vehicle/character scenes are **generated** by their `build_*.gd`
scripts. Edit the generator, not the scene — and note the generators need a window, since
the headless dummy driver silently writes an empty city. Full rule in `CLAUDE.md`.

## The other documents

- **`PROGRESS.md`** — what each phase cost and what it taught, in order. The most useful
  document in the repo if you want to know *why* something is the way it is.
- **`NEXT.md`** — what is left, what is known-broken, and the standing gaps. Every entry
  carries the measurements behind it, including the approaches that were built, measured
  and reverted.
- **`Game/README.md`** — the technical reference: how each system works and the traps in
  it. Read it before changing anything in `Game/`.
- **`CLAUDE.md`** — the working rules: how to run things, what the `.tscn` boundary means,
  and the verification discipline.

## How this repo works

Two habits explain most of what you will find:

**Measure the fault before fixing it.** Reproduce it headlessly and get a number. More
than once the first diagnosis here was wrong and only a measurement caught it, and there
are several entries in `NEXT.md` describing fixes that were built, measured, found to do
nothing, and removed.

**Every new check must be seen to fail.** Break the fix, watch the check go red, put it
back. This project has had checks that passed with their own fix deleted, which is worse
than no check at all.
