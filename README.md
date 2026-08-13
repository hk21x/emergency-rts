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

Every planned phase has landed except the last half of one: the career economy shipped,
**campaign scenarios have not**. What exists is a complete freeplay loop — open a shift,
take the calls the director rolls, get scored on it — plus the district, the fleet, the
economy, and a world that reacts to all three.

Ten kinds of call, three services, and fifteen verbs. Two of those calls need more than
one service and need them **in order**: somebody pinned under a load has to be cut free
before they can be moved, and a crowd turning has to be contained before it can be
arrested.

**766 automated checks**, all passing. The suite reports its own total; take the number
from a run rather than from here.

The one thing the tree knows is untidy: **vehicles sometimes shuffle back and forth for a
few seconds before getting where they are going.** They do arrive — 23 of 24 and 24 of 24
across seeded cross-district journeys — so this is a slowness-and-ugliness fault rather
than a functional one. Five attempts at it have been built, measured and reverted; the
black box now carries enough detail to aim a sixth properly, and the metric to judge it by
is escape count rather than arrivals. All of it, with numbers and the wrong turns, is in
`NEXT.md`.

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

`Move` · `Stop` · `Treat` · `Apprehend` · `Extinguish` · `Cool` (a hazard, before it
goes) · `Free` (someone pinned) · `Collect` (stretcher) · `Escort` (walk a cuffed suspect
to the car) · `Secure` (a cordon) · `Board` · `Unload` · `Return` · `Lights` · `Siren`

Right-click does whatever scores highest on the thing under the cursor, so most play needs
no tiles at all. Units within range of an incident get on with the job themselves.

**Return** is contextual: an ambulance carrying a casualty goes to the hospital, a patrol
car with a suspect goes to custody, anything else goes home. A unit driving home is not on
a shout — it keeps to the limit and runs dark, which is the one order that does.

## The shift

Press **F2** and the district starts producing calls. Until then it idles: no scripted
incidents, nothing to react to.

Calls open on the street, not inside buildings. Fires come in three kinds — a bin, a car,
a building — and each burns, spreads and yields differently. A building fire needs a hose
and a water tank behind it: an appliance that runs dry has to be moved to a hydrant rather
than waited out. A car fire damages whatever is parked in it, including yours.

**Different fires want different things put on them.** A car burns fuel, so it takes
foam — and foam comes out of a second tank that only the station refills, so a shift of
car fires sends the appliance home whatever the hydrant on the corner says. An electrical
fire takes dry powder, which is what a patrol car carries and the appliance does not: the
one call the fire service cannot answer and the police can. The board says what each fire
wants, so none of it is guesswork.

**Your own people can be lost.** A crew member caught in a blast, or one wrestling a
suspect on their own, goes down and needs an ambulance like anyone else. Get them to
hospital and they come back; don't, and the unit is off your books for good.

**A crowd can turn.** A disturbance left unattended draws bystanders in until it is
several people rather than one. An officer standing in it stops that, and so does a
cordon — the first thing in the game that has ever needed one.

**Someone can be pinned under the load.** A trapped casualty can be treated where they
lie, but nobody moves them until a fire crew cuts them free — the first call that needs
two services in sequence rather than at once, so turning up in the wrong order costs you.

One call can hurt you back. A **gas leak** puts a pressure cylinder beside a burning bin;
it heats while the fire burns and the board counts it down — *warming*, *venting*, *about
to go*. Let it reach the limit and it takes the street: damage to everything near it,
bystanders hurt, fresh fires thrown. Hose the cylinder, or put the fire out and let it
cool itself. Both work; picking one is the call. Casualties are stabilised where they lie
and then stretchered aboard; they are not saved until they reach the hospital. Suspects
are detained, walked to a patrol car by the officer who arrested them, and driven to the
station. A car takes two.

The shift ends in a debrief and a score. Vehicles take damage from what you drive them
into, and repairs come out of the same purse the fleet is bought from.

## Controls

Also on **F1** in game, and on the CONTROLS chip beside it. `F5` opens a call spawner for
picking a specific call kind rather than waiting for the director to roll one.

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
