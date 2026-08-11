# RTS playground

An Emergency 4–style demo built on the Synty POLYGON packs: select units, order them
somewhere, and they drive or walk themselves there through a city district — cars
keeping to the roads, people using the pavements.

Everything written for the game lives under `Game/`. The Synty packs themselves are
unmodified, though the POLYGON City pack was relocated on import — see `PROGRESS.md`.

## Where this is up to

**All 15 planned phases are done, plus 16 (the world reacts), 17 (audio), 18 (game
framing), 19 (the fire service) and the career economy — half of phase 20.** 522
automated checks, all passing.

A 260m city district — twenty-five blocks of varied size, with parks, parking lots and
four tower families — with 60 pedestrians and 22 civilian cars going about their business.
The map opens **quiet and empty** — a career starts with £2,000 and no units, buys
its fleet from the DISPATCH block, and keeps it between sessions. `F2` opens a
**freeplay shift**: five, ten or fifteen minutes of calls the district produces — busier
towards the end — scored per call cleared and weighted by response time, with every
task paying its points in pounds. A debrief closes it: score, best, and what was
earned. You command what you have bought from a docked command bar and work each
shout end to end: treat the casualty, wheel them to the ambulance, put the fire out
before it spreads, take the troublemaker in.

What makes it a dispatch game rather than an RTS with sirens:

| | |
| --- | --- |
| **Incidents are jobs** | A `Call` groups everything at one scene under a street address, so a fire that spreads into six bodies stays one line on the board |
| **Units are specialised** | Gating is hard — an officer cannot treat, a paramedic cannot fight a fire. Sending the wrong one is a wasted trip |
| **The fleet is bought** | Nothing is free: units and staff are purchased with money earned per completed call, speed-weighted — and a unit sent home parks on the forecourt, because it is property |
| **The city has rules** | Traffic keeps right, yields, and pulls over for blues; a unit recalled to the station runs dark, holds the limit and keeps its lane |
| **The city takes part** | A medical call is a *civilian* collapsing, and a body draws onlookers along the pavements — kept back by an officer's cordon |

One thing is still missing and is not an oversight: street furniture is drawn without
collision, so units walk through benches — the hydrants are the exception, and only
because a mechanic finally needed them. Audio is complete and **mostly synthesised**:
the siren is a recording, and engine, crackle, radio and city bed are still written
sample by sample, ready for recordings to replace them the same way. The **fire service** exists but wears borrowed clothes — the pack
ships no appliance and no firefighter, so both are the police models in the pack's
orange palette until a fire pack arrives. Everything under them is real.

`PROGRESS.md` is the status document — what each phase cost and what it taught.
`NEXT.md` is what is still to do. This file is the technical reference: how each system
works, and the traps found along the way.

## Running it

Any Godot 4.6+ binary works (originally built on 4.6.3, verified on 4.7):

    godot --path .

`Game/Playground.tscn` is the project's main scene, so **F5** runs it.

## Controls

| Input | Action |
| --- | --- |
| **Left click** | select a unit (clicking anywhere else deselects) |
| **Left drag** | box-select everything inside the rectangle |
| **Shift + left click** | add to / remove from the selection |
| **Right click** | order the selection to go there |
| **Right click a car** (people selected) | walk over and get in |
| **Right click a fire** | walk into hose range and put it out |
| **Right click a casualty** | kneel beside them and treat |
| **Right click a stable casualty** (paramedic selected) | fetch the stretcher from the ambulance and wheel them aboard |
| **Right click a suspect** (officer, then patrol car) | apprehend them; then send the car to escort them in |
| **Shift + right click** | queue that order behind the current one |
| `Ctrl` + `1`–`9` | assign a control group |
| `1`–`9` | recall a control group |
| `Z` `X` `C` `V` `B` `N` `M` `G` `H` `J` `K` | the command tiles, left to right |
| Command tile | `Move`, `Treat`, `Extinguish`, `Secure`, `Board`, `Collect` arm the cursor for a target click; `Stop`, `Unload` and `Return` fire at once; `Lights` (`J`) and `Siren` (`K`) are toggles — the tile turns blue while one is running |
| Roster chip | click to isolate that unit, `Ctrl`-click to drop it, double-click to follow |
| `Esc` | cancel an armed ability |
| `F1` (or the CONTROLS chip above the bar) | open or close the controls card |
| `W` `A` `S` `D` / arrows | pan the camera (hold `Shift` to pan faster) |
| `Q` / `E` | rotate |
| Mouse wheel | zoom |
| Middle-drag | pan |
| Minimap | left-click or drag to look there; right-click to order the selection there (Shift queues). The trapezoid is the camera's ground footprint, its far sweep capped so it stays marker-sized |
| `F` | follow the selection |
| `R` | respawn the selection at its start slot |
| `F2` | start a freeplay shift (scored; see "Freeplay") |
| `ENTER` / `SPACE` (title) | play — the session opens on the title card |
| `P` | pause menu: resume, restart shift, settings (volume, shift length, call rate, time of day), quit to title |

Keys are bound to **physical** keycodes, so the layout holds on AZERTY and QWERTZ.

## The pieces

| File | What it is |
| --- | --- |
| `Units/Unit.gd` | Base: selection, ability list, order queue |
| `Units/Vehicle.gd` | Arcade motion model + autopilot, extends `Unit` |
| `Units/Person.gd` | A unit on foot: walks, animates, rides in vehicles |
| `Units/Civilian.gd` | A member of the public: strolls the pavements, runs from fire |
| `Units/TrafficCar.gd` | Ambient traffic: drives the road grid in lane, yields |
| `CityGrid.gd` | The district's layout, shared by the generator and the ambient AI |
| `Units/Order.gd`, `MoveOrder.gd`, `BoardOrder.gd` | Queued instructions |
| `Units/Ability.gd`, `MoveAbility.gd`, `StopAbility.gd` | Verbs a unit offers |
| `Units/BoardAbility.gd`, `UnloadAbility.gd` | Getting in and out of vehicles |
| `Units/WorkOrder.gd` | Orders with range, duration and failure |
| `Units/ExtinguishAbility.gd`, `TreatAbility.gd` + orders | Dealing with incidents |
| `Vehicles/FireEngine.tscn`, `Firefighter.tscn` | The fire service: an appliance, its crew, and the hose reach between them |
| `Hydrant.gd` | Where an appliance refills. The first street furniture with a mechanic |
| `Soundscape.gd`, `build_audio.gd` | The city bed and the dispatch radio; every sound synthesised |
| `Units/SecureAbility.gd`, `SecureOrder.gd` | Cordoning a scene off. Police only |
| `Units/ReturnAbility.gd`, `ReturnOrder.gd` | Sending a unit back to the station |
| `Units/LightsAbility.gd`, `SirenAbility.gd` | Manual lightbar and siren toggles. Vehicles only |
| `Station.gd` | The forecourt: a finite roster, spawn slots, standing down |
| `UI/DispatchPanel.gd`, `ServiceMark.gd` | Calling units out of the station |
| `Incidents/Cordon.gd` | The ring of cones, and what the crowd keeps out of |
| `Incidents/Incident.gd` | Base: something that gets worse if ignored |
| `Incidents/Fire.gd`, `Fire.tscn` | Grows, spreads, is doused |
| `Incidents/Casualty.gd`, `Casualty.tscn` | Declines, is treated, wheeled out, or lost |
| `Incidents/Suspect.gd`, `Suspect.tscn` | A Disturbance: apprehended, escorted, booked in |
| `Incidents/Hospital.gd`, `Hospital.tscn` | Drop-off zone; delivers on arrival |
| `Incidents/Call.gd` | One job: the incidents at one scene, with an address and a state |
| `Incidents/CallBoard.gd` | Groups incidents into calls, passively |
| `UI/CallList.gd`, `CallMark.gd` | The call board; click a row to jump to it |
| `Units/CollectAbility.gd`, `StretcherOrder.gd` | The paramedic's stretcher run |
| `Units/ApprehendAbility.gd` + order | Taking a suspect into custody. Police only |
| `Units/LoadSuspectAbility.gd` + order | Sending the patrol car for a detained suspect |
| `Mission.gd` | Objectives, win and lose — and the freeplay score |
| `Director.gd` | Freeplay: opens calls on a timer, ends the shift. Inert until F2 |
| `UI/Palette.gd` | Every colour the interface uses, in one table |
| `UI/build_theme.gd` | Bakes `UI/Theme.tres` from that table |
| `UI/Glyph.gd` | Every symbol: pack icons with drawn fallbacks, shared by tiles, avatars and pills |
| `UI/ControlsPanel.gd` | The controls card: keycap icons, sectioned by function |
| `UI/GameMenu.gd` | The framing: title card, pause menu (`P`), settings |
| `UI/ShopPanel.gd` | The unit shop: portraits, prices, blurbs, BUY |
| `UI/Icons/`, `UI/Keys/` | Curated icons and keycaps from the pack under `Assets/padding` |
| `UI/Portrait.gd` | Who is selected and what they are doing |
| `UI/Roster.gd`, `UnitChip.gd` | Every unit under command, as clickable avatars |
| `UI/CommandGrid.gd`, `CommandIcon.gd` | Command tiles, drawn from ability metadata |
| `UI/UnitBadge.gd` | A unit as a circular avatar, used at three sizes |
| `UI/StatusStrip.gd` | Shift clock and what is outstanding |
| `UI/Minimap.gd` | Overhead map, click to jump the camera |
| `build_portraits.gd` | Renders the unit avatars. **Needs a window** |
| `build_minimap.gd` | Renders the minimap's base image. **Needs a window** |
| `Units/Target.gd` | What was clicked: point, collider, unit |
| `RTSController.gd` | Picking, multi-selection, control groups, order issuing |
| `RTSCamera.gd` | Overhead camera: pan, rotate, zoom, follow |
| `UI/SelectionBox.gd` | Draws the drag rectangle |
| `Vehicles/PoliceCar.tscn`, `Ambulance.tscn` | **Generated** from City prefabs |
| `build_vehicles.gd` | Generates the vehicle scenes |
| `Car.tscn` | The original Starter car. Unused, kept as a reference |
| `Person.tscn`, `Paramedic.tscn` | The two crews on foot. Service decides their verbs |
| `Characters/PoliceOfficer.tscn`, `Paramedic.tscn` | **Generated** from the City police characters |
| `HUD.tscn`, `HUD.gd` | The docked command bar and the world overlays |
| `Playground.tscn` | The city district — **generated**, see below |
| `build_map.gd` | Generates `Playground.tscn`, including both navigation bakes |
| `setup_project.gd` | Registers input actions, sets the main scene |
| `setup_retarget.gd` | One-shot: builds the bone maps and patches the scene importers |
| `build_character.gd` | Builds every character scene from its retargeted rig |
| `build_civilians.gd` | Wraps each civilian character in a walking body |
| `check_retarget.gd` | Verifies the animations drive the rig, renders a pose sheet |
| `smoke_test.gd` | Headless behaviour test |
| `screenshot.gd` | Renders PNGs of the scene |
| `inspect_meshes.gd` | Prints every mesh's bounding box |
| `inspect_tiles.gd` | Renders a labelled contact sheet of kit prefabs |
| `inspect_animations.gd` | Lists animation clips and skeleton bone names |
| `inspect_rigs.gd` | Dumps rig node trees and their importer subresource keys |
| `AnimationViewer.tscn` | Standalone clip viewer, run it directly |
| `ChaseCamera.gd` | **Unused.** The follow camera from the manual-driving version, kept in case it is wanted again. It needs a `cam_cycle` input action, which no longer exists. |

## Unit architecture

Three separate ideas, so vehicles and personnel share everything except locomotion:

- **`Unit`** — selectable, holds an ability list and an order queue. Runs the order at
  the front of the queue and knows nothing about how it physically moves.
- **`Order`** — one instruction. `start()` once, then `tick()` each physics frame
  until it reports done. Orders own *what* should happen.
- **`Ability`** — a verb the unit offers. Each is asked to `score()` a `Target`, and
  the best score wins.

That last part is the point. `RTSController` never names a verb: right-click builds a
`Target` from the raycast, asks the selection to resolve it, and queues whatever comes
back. Adding "extinguish" later means writing an ability that scores fires highly —
the controller does not change. `MoveAbility` deliberately scores **0**, so any
purposeful verb outranks it just by scoring above zero.

The command bar is generated the same way, from the union of the selection's
abilities. Instant abilities (`Stop`, `Unload`) fire on click; targeted ones (`Move`,
`Board`) arm the cursor for the next left-click.

Adding a unit type means a scene with a `Unit` subclass and its own
`_build_abilities()`. Nothing else needs to know about it.

## Personnel

`Person` is deliberately much simpler than `Vehicle`: a person turns on the spot, so
there is no steering model, no reversing and no turning circle — just steer at the
next path corner and walk. Clip choice follows actual speed (`Idle`, `Walk`,
`Jog_Fwd`), and playback rate is scaled by speed so the feet do not skate.

**Two navigation meshes** are baked over the same geometry, because a car needs 1.5m
of clearance and a person needs 0.4m:

| Region | Agent radius | `navigation_layers` |
| --- | --- | --- |
| `VehicleNavigation` | 1.5 | 1 |
| `PersonNavigation` | 0.4 | 2 |

### The kerb is a wall, why that is deliberate, and how a car gets over it anyway

Godot's `move_and_slide` has no step-up and a vehicle collider is a **box**, so a vertical
7cm face stops a car outright — one driven at a kerb halts 2.8m short and oscillates. A
person's collider is a **capsule** whose rounded base rides the same step without
noticing, which is why the crowd crosses roads happily while no car can mount a kerb.

That is a cost worth paying, and it was measured by paying the other one. Bevelling the
kerb — a 9° wedge along each pavement's road-facing edge, which a car climbs under power
— fixed the wedging and cost containment through corners: the turn into one junction went
from 17.1s to 30.6s with **328 of 1836 frames spent on the pavement**, grinding. Cars are
held in their lane through a corner by the kerb, not by the steering.

There is no middle setting **in the ground**. A kinematic body climbs any slope under
`floor_max_angle` at any speed, so a bevelled kerb is either climbable or it is not;
steepening the wedge past 45° just makes it a wall again. Making the pavement flush
instead was tried twice and reverted twice, for the same reason and worse — see NEXT.md.

### …and how a car gets over one anyway

The rule above binds a *slope*. It does not bind a *body*, and that is the seam
`Vehicle._climb_kerb` goes through: a manual step-up, run after `move_and_slide`, that
lifts the car `climb_height` when it is blocked by something low with clear ground on the
far side. The ground is untouched, so the kerb is exactly as solid as it ever was for
every car that has not earned a lift.

**What earns one is the gate, and getting it right took two goes.** Gated on *being
stuck* it does the wrong thing twice: a car braking into a corner dips under 0.3 m/s
against the kerb and climbs — the turn into junction 1,3 went 12.9s → **41.2s** with 423
of 2473 frames off the carriageway, the bevel's failure move for move — while the case
the player cares about never fires at all. Gated on *the player having asked*, it does
neither. A destination off the vehicle navigation layer sets `_off_road_target`, and that
one flag does two jobs: `_update_autopilot` stops treating `is_navigation_finished()` as
arrival (an off-mesh order used to complete on its first frame, so a car told to park on
a pavement simply ignored the click), and `_climb_kerb` waives the `climb_escapes` tally
and the drivable-landing test, because the whole point of the order is that the
destination is neither. A car with a road destination still has to earn a climb the hard
way, which is what keeps corners honest.

**Three details make it read as driving rather than as a physics trick**, and all three
came from play rather than from a probe. The lift does **not** wait on the stuck timer
for an off-road order — requiring it meant the car drove to the kerb and sat grinding
against the face until it had been under 0.3 m/s for half a second, then hopped up; the
destination already proves intent, so the timer bought nothing and looked broken. The
lift carries the car **forward** as well as up (`climb_nudge`), because a pure lift drops
it straight back against the face and fires again next frame — 33 lifts on one journey.
And within `off_road_approach` of the target the **reverse latch and escape manoeuvre are
switched off**, because they are built for streets and understand nothing that is not on
one: a car that had just climbed up promptly reversed off at 8 m/s, drove round, and
climbed again. With all three: up at 1.4s, two lifts, order complete in 2.4s, parked on
the pavement. `_take_damage` also excuses non-vehicle contacts on that approach — a kerb
taken on purpose at 9 m/s billed £38, and charging for obeying an order is a bill the
player can only avoid by not using the verb.

Two traps in here have now caught things twice each. `map_get_closest_point` takes **no
layer filter** and both navigation regions share one map, so it answers 0.00m for a point
in the middle of a pavement — any "is this off the road?" test written with it is
vacuous, and `_is_off_road` uses `map_get_path` for that reason. And the *scenarios* are
misleading: a car is never routed over a kerb, queues 7m short of a blockade, threads a
single obstruction without touching the verge, and steers away from a kerb it is aimed
at. `Game/probe_kerb.gd` measures all of it, one condition per process — running two
conditions in one process measured the harness instead, with whichever ran second
failing.

Each `NavigationAgent3D` picks its mesh through matching `navigation_layers`. The
meshes are sourced by **group** (`nav_source`) rather than by child nodes, because the
same geometry has to feed both regions and a node can only have one parent. Measured
against the boundary wall: the person layer reaches 0.35m from it, the vehicle layer
1.35m.

### Getting past a parked car

The collision masking is asymmetric on purpose. People are on layer 4 and mask 1, which
is what the player's vehicles sit on; vehicles mask 1|2|64 and cannot see a person at
all. So nothing moves out of anybody's way, and a walker who met a parked patrol car used
to stand against it for ever — measured at 1,716 stationary frames out of 1,747, never
arriving.

`Person._step_round_obstacles` fixes it from the person's side. Half a second of trying
to walk and getting nowhere earns a **sidestep**: the intent is swung round to run
*along* whatever is in the way, and `move_and_slide` — which already slides on anything
with a tangential component and resolves a head-on contact to nothing at all — does the
rest. One step lasts 1.1s, long enough at walking pace to clear the width of a car.

Two things worth keeping:

- **The obstruction is found with a ray, not with this frame's slide collisions.** A
  person walked flat into the side of a car has `velocity` zeroed and a slide-collision
  list of two entries, both of them the road they are standing on. The car does not
  appear in it. Whatever the engine does with a contact that stops motion outright, it is
  not something to build behaviour on.
- **The crowd is not allowed the same freedom.** `Civilian._may_step_to` refuses any step
  that would finish off the pavement graph. An officer under orders may cut across a road
  to get round something; a passer-by doing the same is walking down the middle of the
  carriageway, which is the one thing this district's pedestrians never do.

Not solved by dropping vehicles from the person mask — walking *through* a parked car is
worse than stopping at one — and not by giving vehicles the people layer either, since a
car that collided with pedestrians would push them into walls, or through the floor.

Boarding is ordinary ability resolution. `BoardAbility` scores **10** against a
vehicle with a free seat, beating `MoveAbility`'s 0, so right-clicking a car with
people selected means "get in" rather than "walk to that spot". `BoardOrder` re-paths
if the car drives off, so people chase a moving vehicle. Someone aboard is hidden, has
their collision disabled and reports `is_selectable() == false`, which the controller
uses to drop them from the selection.

## Incidents

An `Incident` is something on the map that gets worse if it is ignored. That is the
clock the player races.

- **`Fire`** grows at `growth_per_second` on its own, and once past
  `spread_threshold` throws off a new fire every `spread_interval`, up to `max_fires`.
  Dousing it below the threshold makes it start building again before it can spread.
  Spread positions step by a golden angle rather than using a random number generator,
  so a test run is reproducible.
- **`Casualty`** has two separate quantities: `health` runs down on its own, and
  `treatment` is what a worker adds. Treatment stabilises; running out of health does
  not. That gap is the point — arrive late and they are lost, which is a failure the
  player can feel.
**The figures wear the crowd's clothes.** `Casualty` and `Suspect` ship with the
Starter pack's grey-blue mannequin, which reads as a placeholder in a city full of
dressed pedestrians, so both swap it in `_ready` for one of the seven civilian
outfits (`Incident.OUTFITS`). Two details are load-bearing: the swap has to happen in
`_ready` **and hand back the new `AnimationPlayer`**, because `@onready var _animation
:= $Character/AnimationPlayer` has already resolved and would be left pointing at a
freed node; and the replacement inherits the old node's transform, which is where the
180° yaw that stops them moonwalking lives. When a collapse takes a specific shopper
the director passes that shopper's outfit through `_spawn`, before the incident enters
the tree — so the body on the pavement is wearing what they were wearing.

- **`Suspect`** is the police half of what `Casualty` is to the medical service:
  somebody causing trouble, worked with `Apprehend`, loaded by a patrol car,
  delivered at the station. Deliberately **no timer** — an unattended disturbance
  is not lost, it just carries on while the response bonus drains away. And it is
  *alive*: they pace a few metres about the scene along the pedestrian graph,
  mouthing off; while an officer works the arrest they **fight it** (the punch
  clips alternate off a heat value the work refreshes — no order bookkeeping);
  cuffed, they walk back to the kerbside spot the call opened on, which is what
  keeps them inside the escorting car's reach. Every clip is a one-shot
  restart-looped the way `Person` does it — the rig's player has no `*_Loop`
  variants, and trusting one left the first suspect in a silent T-pose. Facing
  goes through `_face()`, and **`Suspect.tscn` must keep its 180° Character yaw**:
  the project steers with `atan2(x, z) + PI`, which aims the node's −Z, and the
  visual's half-turn is what converts that into the model looking forwards. The
  scene shipped without it and the first suspect paced backwards.

Incidents sit on **collision layer 8**: pickable by the selection raycast, but outside
the vehicle (mask 3) and person (mask 1) masks, so nobody drives into a fire or trips
over a casualty. They are also outside the navigation bake, which only reads layer 1,
so an incident never carves a hole in the paths.

### Where an incident may be

Every Director picker funnels through `_clear`, and that is where "**nothing happens inside
a property**" lives. A scene nobody can walk to is a call that cannot be answered — it
burns or bleeds until it fails — so the gate is one test in one place rather than a rule
each picker has to remember.

Fixed offsets are the exception that proves it: the rescue placed its casualties a set
distance from the fire, which is pavement on a frontage facing one way and the building's
interior on one facing the other. `Director._beside` keeps the distance and sweeps the
direction until the ground is real.


`CityGrid.standable` answers "could anyone stand here?" — carriageway, a block's pavement
ring, or a park lawn, but never inside a building. **Not `walkable`**, which is the
pedestrian graph's question and means only "not in the middle of the road": it says yes to
a building's footprint, and a fire placed on a `walkable` tile can be inside a warehouse.

`Fire._spread` learned this the hard way. It placed its child five metres off at a golden
angle with no test at all, so a fire against a frontage spread into the building and
burned unreachably until the call failed. Written against `walkable` the fix was inert —
every spread it should have rejected passed — and what caught it was the check refusing to
go red under sabotage.

### WorkOrder

`MoveOrder` and `BoardOrder` both just complete on arrival. Incidents needed a
different shape, and `WorkOrder` is it: an order with a **range** to close, a
**duration** to spend, and a **failure** it has to survive.

Every tick re-checks that the target is still worth working on, because it can vanish
mid-job — a fire goes out because someone else reached it, a casualty is lost. Note
that `queue_free()` does not take effect until the end of the frame, so `Incident` also
carries an `active` flag that clears immediately; orders trust that rather than
`is_instance_valid` alone.

Being shoved out of range mid-job drops the work animation and goes back to walking,
then resumes on arrival. Subclasses supply only `_work()`.

### The casualty journey

Stabilising is **not** saving. `treat()` stops the decline and marks them stable, but
the incident stays open until they reach hospital — which is what makes the ambulance
run part of the job rather than a formality.

    hurt -> treated on scene -> wheeled aboard on the stretcher -> delivered at the Hospital

Collection is **on foot**: `StretcherOrder`, the paramedic's verb. They walk to the
nearest medical vehicle with a free slot, pull the stretcher out (a generated prop —
the pack ships no gurney), wheel it to the casualty, lift them on (`is_carried`:
visible, unpickable, riding the prop), and wheel them back aboard. It replaced an
ambulance-side Collect that drove at the casualty, which was broken by geography:
the vehicle mesh is the carriageway and nothing else, so a casualty deep on the
pavement — or in a park, where collapses now happen — was forever out of a parked
vehicle's 4.5m reach. Feet go everywhere the pedestrians do. Cancelling mid-carry
puts them down where the stretcher stands, still open, still collectable; driving
the vehicle away mid-run is allowed — the walker follows it.

`Hospital` is an `Area3D` that hands over whoever a vehicle is carrying the moment it
drives in. No extra order to issue: driving there already says what you mean.

The **suspect journey** is the same three beats with police verbs — apprehended on
scene, escorted into a patrol car, booked in at the station. The station's custody
door is polled against the same `return_radius` the returns already use, rather than
hung on an `Area3D`, because the forecourt is generated geometry and the yard *is*
that circle.

### Getting on with it

An idle unit starts work on a suitable incident within `auto_engage_range` of it, so a
crew put down beside a fire fights it without being told twice. `Unit._auto_engage` scans
the incident group, builds a `Target`, and asks the ladder — the same resolve a right-click
runs — so the capability gating comes free: an officer has no Extinguish to score against a
casualty, and no amount of standing nearby will change that.

Two gates, both load-bearing:

- **Only when idle** (`has_orders()`). Without it a unit sent past a fire abandons its
  order to fight it, and an order stops meaning anything.
- **Only abilities that opt in** (`Ability.auto_engages`). The ladder says what a unit
  *would* do, not what it should do unasked. Extinguish, Treat, Collect and Apprehend say
  yes; Secure and Board do not, because closing a street or getting into a vehicle is the
  player's decision.

The opt-in takes the unit and target so it can answer contextually: a fire that needs a
hose engages the fire service only. `ExtinguishAbility` scores against any fire and the
*order* is what discovers the hose is missing — acceptable when the player chose it, not
when an idle officer chose it and stopped being available.

### The scoring ladder

Right-click meaning falls out of the numbers, with no branching in the controller:

| Ability | Score | Offered by | So that… |
| --- | --- | --- | --- |
| `Treat` / `Apprehend` | 30 | people | the person *is* the job: a casualty or a suspect beside a fire gets worked first |
| `Collect` | 25 | paramedics | a stable casualty means "run the stretcher" — see the casualty journey |
| `Escort` | 25 | patrol cars | a detained suspect means "send the car" — crime is kerbside by construction |
| `Extinguish` | 20 | people | a fire beats walking into it — how fast depends on who holds it, see below |
| `Board` | 10 | people | a car with a free seat means "get in" |
| `Move` | 0 | all | the universal fallback |

`Treat` and `Collect` never compete: `Treat` only applies while the casualty is still
declining, `Collect` only once they are stable.

**`Extinguish` is one verb with three rates**, which is what makes the fire service a
service rather than a faster officer (`ExtinguishOrder`):

Each is a multiplier on the fire's own `douse_per_second`:

| Who | Rate | Why |
| --- | --- | --- |
| Firefighter within `HOSE_REACH` (18m) of a fire engine | **180%** | a pressurised line off a tank — parking the engine at the scene *is* the job |
| Firefighter away from any engine | 35% | only what they can carry |
| Police | 45% | the extinguisher a patrol car actually carries |

The hose being **above 100%** is the point, and it was 100% until play feedback in
August 2026 said fires took too long with an engine on scene. It did: a building fire
was 11.0 seconds a node, and buildings *spread*, so a real building call was a minute
of standing still. At 1.8 the same node is 3.8 seconds and a kerbside fire is 0.9. The
other two rates were deliberately left alone — the complaint was about the engine being
there, and the gap it makes went from 2.9× to 5.1×. A check pins `on_hose >
douse_per_second`, so the multiplier cannot quietly go back to being a ceiling.

And a `Fire` with `needs_hose` set — a building — yields to **nothing but the first
row**. An officer can stand in front of one all day: the order runs, the animation
plays, and the intensity does not move.

**And the hose runs on water.** An appliance carries a tank (`Vehicle.water`), drawn
down while its crew works and refilled beside a `Hydrant` or on the station forecourt
— and only while *parked*, so where the engine stops is a decision rather than a
formality. An engine with an empty tank stops counting as a supply at all, which
makes running dry a failure rather than a slowdown: a building grows faster than a
crew off the hose can knock it down, so the answer is to move the engine.

The tank is charged **per unit of intensity knocked down**, not per second
(`WATER_PER_DOUSE`), and how far it goes is `Vehicle.tank_capacity` — a divisor, so
`water` stays the 0..1 fullness the portrait's bar reads. While the hose ran at exactly
the fire's own rate, per-second and per-unit were the same number; the moment that rate
moved, per-second billing meant a faster crew put fires out for *less* water, which is
backwards. Charging the work keeps the economy invariant under any future retune.

### A building fire is sized to the crew that has to fight it

A building fire **spreads while the crew drive to it**, which is what makes it hard:
at a 40-second response the full-size version is six nodes on arrival and pinned at
`max_fires` (8), and one worker can only be at one node. Measured against that scene,
neither of the obvious levers touches it:

| | outcome after 180s |
| --- | --- |
| tank 20× bigger | still burning, and ended above half full |
| hose rate 1.8 → 4.0 | still burning |
| 1, 2 or 3 firefighters | still burning, at *any* of those rates |
| 4 firefighters | cleared in 19.7s |

A cliff, not a curve, sitting exactly on the appliance's four seats. Hands are the only
thing that helps — so the fire is **sized to the hands available**
(`Director.BUILDING_SIZE`, applied by `_size_to_crew()` to both the plain building fire
and the rescue):

| firefighters owned | nodes | spread every | measured outcome |
| --- | --- | --- | --- |
| 1 | 2 | 15s | cleared in 13.9s |
| 2 | 4 | 12s | cleared in 13.7s |
| 3 | 6 | 10s | cleared in 15.6s |
| 4+ | 8 | 8s | cleared in 19.7s |

The fight stays about the same *length* while the scene visibly grows, and past four it
stops growing — the appliance seats four, and a fire that outran a full crew would just
be the unwinnable version again wearing a bigger number.

Gating instead was tried first: `_can_fight_buildings()` briefly demanded a full crew of
four. It worked and it was miserable — a one- or two-firefighter career simply never saw
the most interesting call in the game. The gate is back to an engine plus *one*
firefighter, and the difficulty does the work. It is also the first thing in the project
to answer NEXT.md's standing complaint that difficulty is one setting for everyone.

## Sound

Every sound in the game is **synthesised**, not recorded — `build_audio.gd` writes
16-bit mono WAVs sample by sample, because the project owns no sound library and
buying one was not the point. They are placeholders a real recording can replace
file-for-file.

| Sound | Where it lives | Driven by |
| --- | --- | --- |
| Siren | `AudioStreamPlayer3D` on the vehicle | the `K` toggle |
| Engine | `AudioStreamPlayer3D` on the vehicle | road speed, as pitch and level |
| Crackle | `AudioStreamPlayer3D` on the fire | its intensity |
| Radio chirp | `Soundscape` (non-positional) | `CallBoard.call_opened` |
| City bed | `Soundscape` (non-positional) | nothing; it just plays |

Positional audio lives on the thing making it; the last two have nowhere to be — the
ambience is everywhere and a radio call is in the player's ear, not at the address it
is about.

**Loops have to close.** Every looping sound is an exact whole number of cycles of its
own fundamental (the engine is 22 cycles of 55Hz, hence its odd 0.4s length): a buffer
that ends mid-cycle clicks once per loop, which at an engine's loop length is a rattle.

**Audio fails silently**, which is why it is checked at all. A missing file, an
unimported one and a player nobody called `play()` on are indistinguishable from the
code and equally quiet. The suite asserts every stream is loaded, attached and
running, and that the two which answer the world — engine pitch, crackle volume —
actually move when it changes. `Apprehend` and `Escort` mirror the
pair exactly, split on `is_detained` — and they even share the same hotkeys (C and B),
because no unit carries both services' verbs: C is simply "work the person in front
of you", whichever service is holding the keyboard.

## The black box

**The most useful thing in this file if a handling fault is ever reported again.** Three
were, in August 2026, and all three were found by reading its records — none by a staged
test. Every headless staging of "a unit gets trapped" came out clean, because none of
them were traps: they were a route that began behind the car, a give-up timer blaming the
road for the car's own trouble, and orders landing outside the district. Three fixes built
on staged evidence in the same period were measured and reverted. **Read the log, then
write the probe.**

`StuckLog.gd` writes down what one of the player's vehicles was doing when it stopped
getting anywhere. It exists because the handling faults that survive in this project are
exactly the ones a staged test does not reproduce — a unit trapped at a crossroads was
reported from play three times, and three separate headless stagings of it came out
clean. Rather than keep guessing at the staging, the game records the real thing.

It arms itself when a vehicle under orders stops closing on what it is aiming at for
`report_after` seconds, and **F3** forces a record for anything that looks wrong but is
technically still moving. Records append to `user://stuck-log.txt` —
`~/Library/Application Support/Godot/app_userdata/Polygon_Starter/` on macOS — one block
each:

    --- Patrol 7: no progress for 4s ---
      at (20.0, 5.0)  on a road: true  speed -0.0  on the floor: true
      aiming at (17.5, 14.0), 9.3m away
      order: Returning to station   turning round: false   passing: true
      in a junction box: no, 15m from the nearest crossroads
      within 14m:
        Patrol1              0.0m  speed  -0.0
        Officer1             5.5m  speed   0.0

Progress rather than speed, for the reason `TrafficCar` learned it in phase 12: a car
shuffling back and forth under the escape manoeuvre is never stationary and never
arriving, and a standstill test misses the worst case entirely. Ambient traffic is not
watched — a taxi queueing at a junction is doing its job, and there are twenty-two of
them.

A passive watcher like `Mission` and `CallBoard`: it hooks `node_added` rather than being
registered with, so nothing else has to know it exists.

Each record carries a **ten-second trail** — twenty positions at half-second intervals —
and that is the field that settles things. A snapshot cannot tell a car that stopped where
it stood from one that wandered thirty metres off its route and stopped there, and those
are completely different faults. The trail is what turned "the police car is erratic" into
a measurable 523° loop.

**Anything that loads `Playground.tscn` must redirect `log_path` first.** The recorder is
in the map scene and defaults to the player's own `user://stuck-log.txt`, so a harness
that drives a car quietly appends its fixtures to the file real faults are read from —
and afterwards a staged record is indistinguishable from a played one. The suite learned
this once (`user://smoke-stuck-log.txt`) and has a check pinning it; the probes learned it
again in August 2026, after `probe_corner.gd` and `probe_kerb.gd` put **149 records** of
staged driving into the player's log in a single session. They write to
`user://probe-stuck-log.txt` now. A probe drives far more than the suite does, so this is
the first thing a new one should do.

It earned itself on its first session. Three headless stagings of "a unit gets trapped"
had come out clean; the first real record showed a car aiming at **z = 402 on a 260m
map**, which turned out to be the minimap converting an out-of-rect click into a
destination outside the district. That is not a fault any staging would have found,
because it was never a trap — it was an order to somewhere that does not exist.

## Seeing what a car thinks it is doing — F4

The black box answers "what was it doing when it stopped". It does not answer the other
standing complaint — a car that answers a right-click by swinging a full circle instead of
steering left and then right — because that fault is a **disagreement between three
things**, and a log can only show one at a time:

- the **lane route** `MoveOrder` plotted over the street grid (`CityGrid.lane_route`),
- the **polyline** the navigation agent solved inside it,
- the **single point** the steering is aimed at this frame.

`NavDebug` (**F4**) draws all three at once over every navigating player vehicle, in
cyan, amber and green respectively, with a white stick on the destination and rings on
each route waypoint — filled on the one being aimed at. The aim line and heading turn
**red** while the car is reversing or running its escape, because a car backing out of
trouble is *meant* to be driving away from its aim and must not be read as one that has
lost the plot. A first waypoint behind the car, an agent path that doubles back, or a
reverse latch engaged when nothing needed reversing are each obvious in a second.

Ambient traffic is deliberately excluded — it drives on its own rails and has none of
this machinery, so drawing it would be forty lines of noise around the two that matter.

It ships **off**, like the director, and a check pins that: a diagnostic that starts on
is a diagnostic that ships on. Drawing is one `ImmediateMesh` rebuilt each frame rather
than a pool of nodes, which at a handful of vehicles is cheaper than keeping nodes in
step with orders that change every few seconds — and, more to the point, it cannot leave
a stale line behind, which here would be a false diagnosis. Measured with it switched on
for a whole suite run, it disturbed no timing-sensitive driving check.

Worth running alongside Godot's own `--debug-navigation`, which draws the baked mesh and
answers the one question this does not: *where may a car go at all*.

    godot --path . --debug-navigation

## The crowd refills

Every medical call takes a shopper permanently — the body is the person who was standing
there, which is the point of taking one rather than spawning a stranger. `CrowdRefill`
puts them back, one every thirty seconds, and **only up to the size the map was built
with**, so a district nothing has happened to sees nothing happen.

It reads the size and the outfits off the map at startup: the district decides how many
people it holds. Arrivals go somewhere out of shot and clear of any incident, and an
arrival that cannot be placed discreetly waits for the next turn rather than appearing in
view.

Two traps worth knowing, both found by a failing check rather than by reading the code.
A **packed scene may not remember where its children came from** — `scene_file_path` on
the instanced crowd came back empty, so it asks `res://Game/Civilians` directly when the
crowd cannot say what it is made of. And a **stored countdown ignores a changed
interval**: `_due` is clamped to `every` each frame, or lowering the gap does nothing
until the old one elapses. `StuckLog`'s cooldown had the identical bug.

## Return knows where you are going

One tile, not two. A unit carrying a casualty goes to the **hospital**, one carrying a
suspect to the **custody door**, an empty one **home** — both deliveries already happen
automatically on arrival, so all that was missing was a way to say "take them in" without
knowing which end of the district the right door is at.

It is one tile because the command bar holds exactly **seven** before the
`PanelContainer` grows and silently swallows the CONTROLS chip above it. An eighth took it
from 148px to 176px. That trap has now caught this project five times; adding a command
tile is never free.

## Damage and repairs

The career's only sink. Calls pay in; nothing took anything back until this, so funds
accumulated and the shop ran out of things to want.

Damage is **money and nothing else** — a dented patrol car steers, brakes and answers
exactly as it did new. Taking a unit off the board for a scrape would punish the same
mistake twice, once when it happens and again for the ten minutes afterwards.

`Vehicle._take_damage` charges for whatever this frame's slide ran into, measured as the
speed lost **into the surface**: the component of the pre-slide velocity along the contact
normal. A glancing scrape costs little and meeting something head-on costs a lot — £132 at
9 m/s against £300 at 12. The floor is 3 m/s so kerbs and parking shuffles are free, and a
per-frame cap keeps one deep-overlap artefact from emptying the purse (this project has
form: see `_keep_on_the_map`).

`Station.repair` settles it when a unit is **booked in**, which makes the bill a decision
rather than a tax: a damaged car keeps working, so the player chooses between keeping it
out on the shout and bringing it home to be paid for. The purse can be emptied but never
overdrawn — what it cannot cover stays on the vehicle as outstanding, because a career
that cannot afford its repairs should feel poor rather than stop working.

It is visible in two places: the dispatch heading carries the fleet's outstanding damage
beside the funds, and the debrief reports the shift's repairs directly under what it
earned. A shift can be busy, well scored, and still cost more than it brought in.

## Mission

`Mission.gd` watches the incidents and decides how the shout is going. It is
deliberately passive — it reads the world rather than being told about it, hooking
`SceneTree.node_added` so a fire that spreads is picked up without registering itself.

- **Won** when no active incidents remain (and at least one existed).
- **Lost** the moment a casualty dies, if `fail_on_casualty_lost` is on.

`Incident._finish()` clears its `active` flag *before* emitting `resolved`, so the
incident that just closed is already excluded from the "anything left?" count.

In a freeplay shift both rules are off — `scoring` is true, and the mission judges
**calls** instead. Outside a shift they only matter to the test suite, which spawns
incidents of its own: the shipped map carries none, and `_seen_incident` keeps an
idle district from being declared won. See "Freeplay" below.

## Freeplay

The map ships **quiet**: an empty `Incidents` container, a district that idles, and a
"Press F2 to start a shift" line mid-screen (cleared by `Director.shift_started` — a
state change cannot clear it, because opening a shift leaves the mission RUNNING,
which it already was).

`F2` starts a scored shift. `Director.gd` opens calls on a timer; `Mission` keeps the
score; the shift ends with a debrief instead of win/lose. Until `begin_shift()` the
director does nothing at all — most of the suite is written against a quiet map plus
incidents it spawns itself, and a director that started on its own would break all of
it at once.

**The director stops things rather than starting them.** Fires already spread and
casualties already decline, so escalation was free. What it decides is pacing and
placement: at most `max_open_calls` (3) jobs at once, a `breather` (8s) after any call
closes, calls kept `CLEAR_OF_FORECOURTS` (22m) from the station and hospital and
`CLEAR_OF_OTHER_CALLS` (25m) from every open scene. That last constant must stay above
`Call.GROUPING_RADIUS` (14m) — shrink it below and a "new" call is silently swallowed
into the scene it was meant to be distinct from. A check asserts the relationship.

The mix is a weighted table (`Director.KINDS`):

| Call | Where | Needs |
| --- | --- | --- |
| Medical emergency (35) | Where a civilian is standing | Paramedic, then ambulance |
| Kerbside fire (25) | A pavement tile | Police (the extinguisher) |
| Road traffic collision (15) | A junction | Police to secure, paramedics, ambulance |
| Disturbance (15) | A kerbside pavement tile | Officer to apprehend, patrol car to escort |
| Vehicle fire (10) | Against the kerb of a street | Police (the extinguisher) |
| Building fire (20) | A kerbside pavement tile | A firefighter on an engine's hose — **only drawn once the career owns both** |
| Rescue (12) | A kerbside pavement tile | Engine, crew, paramedic **and** ambulance — the one call no single service finishes |

A medical call **takes a civilian** when the crowd can supply one: the director swaps
a shopper for a casualty where they stand (`_spawn_medical`), so the collapse is
somebody who was just there — the crowd is one lighter for the rest of the session —
and only falls back to a bare pavement tile when nobody qualifies. A vehicle fire is
a `Fire` with a script-free car prefab as a child, parked `KERB_OFFSET` off the
centre line of a street leg; the wreck goes when the fire does.

An RTC is two casualties in one crossroads — grouping and addressing came free from
the call board; what was new is the **name**. `Incident.flavour` carries it, and
`Call.title()` prefers it over the derived kind, so the board reads "Road traffic
collision" rather than the "Medical emergency" two casualties would otherwise be.
The vehicle fire uses the same field; a Disturbance instead gets its own
`Call.Kind.CRIME`, derived from the `Suspect` at the scene — outranked by anything
burning or bleeding beside it, the way triage would rank them.

**The shift escalates.** The rolled interval is scaled from 1.0 down to
`late_interval_scale` (0.55) across the shift, and past `late_surge_at` (65%) the
cap takes one extra simultaneous call. `current_cap()` and `interval_scale()` are
plain arithmetic on the clock, checked directly.

**Building fires are a career gate, not a ban.** The director has always refused to
open a call the roster cannot answer — which, while there was no fire service to buy,
meant no building fires at all. It is now the same rule asked of the *career*:
`_can_fight_buildings()` checks the station owns both an engine and a firefighter
(either alone is no use), and only then does the `building` kind enter the weighted
draw. Generating a fire that is impossible to put out would still be the game lying
about what it can be asked to do.

**Scoring is where calls become authoritative.** The mission's tallies: 50 a fire out,
100 a casualty delivered, 75 an arrest booked in, −150 a casualty lost — a loss costs
points, not the shift. On top, each call cleared pays a response bonus off
`Call.response_age` (the age at which its status first turned `ON_SCENE`): the full
100 inside a 10-second grace, sliding linearly to a floor of 25%. Fast attendance is
worth more than the fire it puts out, which is the game telling you what it is about.

The shift is `shift_length` (300s) of new calls, ending when the board is clear: time
running out with a job open means finishing the job. The status strip shows the score
and time remaining; the debrief under the banner shows the score, calls cleared and
failed, delivered and lost — and arrests, when there were any. `F2` after a debrief
starts the next shift.

**The best shift is banked.** `Mission` keeps `best_score` in `user://records.cfg` —
one section, one key — written on `end_shift()` when beaten and read back at
`_ready`. The debrief line carries `NEW BEST` or `BEST <n>` accordingly.
`records_path` is a var, not a const, so the test suite points it at a disposable
file instead of writing records the player then has to beat. It was the project's
first save-shaped code; the menu's `settings.cfg` and the station's `career.cfg`
followed it, and three is the lot.

## Game framing

`UI/GameMenu.gd` — the title card, the pause menu and settings, as one overlay in
the hand-authored HUD rather than a separate scene. That choice bought three
things: the district idles *live* behind the title (crowds, traffic, the parked
shift), the project's main scene stays `Playground.tscn`, and the generated map is
never touched. The cost is input discipline, and it is load-bearing: while the
title is up the node stops the mouse (a full-rect `MOUSE_FILTER_STOP`) and
swallows the keyboard in `_input` — a leaked F2 would open a shift under the menu,
which a check exists to forbid.

**Pause is the scene tree's own.** The menu node runs `PROCESS_MODE_ALWAYS` (set
in HUD.tscn); everything else inherits PAUSABLE, so `get_tree().paused = true`
freezes vehicles, fires, casualty decline, the shift clock and the call ages in
one line. The title deliberately does *not* pause — the living city is the
backdrop.

**Restart and quit-to-title** go through `Director.abandon_shift()`, which turns
scoring off *before* freeing the open scenes: the calls they leave behind close
silently over the next frames instead of counting as cleared, and only then does
restart open the fresh shift. Units stay where they are — the same contract as
pressing F2 after a debrief.

**Settings** — master volume (the Master bus), shift length (5/10/15 minutes),
**call rate** (QUIET/STEADY/BUSY, a ×2.0/×1.35/×1.0 multiplier on the director's
intervals) and **time of day** (DAY/DUSK/NIGHT) — persist in `user://settings.cfg`,
path overridable for the tests. Each is applied to its node immediately and on every
later assignment of it. BUSY is the pace the game shipped with; STEADY is the default,
because a full shift at the original rate was the first thing anyone called too fast.
The suite pins `pace = 1.0` in its fixtures: tests set their own intervals and must not
inherit a setting.

### The hour is one value, and day is the map as generated

[Daylight.gd](Daylight.gd) owns `time_of_day` and derives everything else from it —
the sun's elevation, colour and energy, the fill light, the ambient, the fog, the
tonemap exposure, the procedural sky's four colours, the 101 street lamps, and a pair
of headlamps on every vehicle. One value, so nothing can end up with the street lights
burning under a noon sun. `is_dark()` is the only question anything else asks; no
system outside the node compares modes.

**DAY is the baseline captured from the scene on `_ready`, not a preset written out
here.** That is deliberate and load-bearing: the shipped map at DAY is the map exactly
as `build_map.gd` wrote it, so the several hundred checks written against it are still
measuring what they think they are. Going back to day restores the captured values
verbatim, and a check asserts the round trip.

Headlamps are fitted by a **watcher** — `Daylight` hooks `SceneTree.node_added` the way
[Mission](Mission.gd) and [CallBoard](Incidents/CallBoard.gd) do — so a patrol car
bought at midnight arrives with its lights on and nothing in the station had to learn
about the hour. Their placement comes off each vehicle's own collision box rather than
a shared constant, so the van-bodied appliance gets them at its width.

### Weather is a property of the road

CLEAR / RAIN, on the same node and the same settings card. The visual half is a 40m rain
box following the camera's ground focus, plus a fog and exposure bump applied *after* the
hour's preset so the two compose — every hour has a wet version without another table.

The mechanical half is one number. `Vehicle.grip_scale` multiplies both grip terms, and
the autopilot already derives corner entry from `sqrt(max_lateral_accel * grip_scale *
radius)` and caps yaw by the same term — so `WET_GRIP` (0.72) lengthens braking distances
and lowers apex speeds for the player's units **and** the ambient fleet without a single
branch asking whether it is raining. Measured on one junction: **8.9 m/s dry, 7.2 wet.**

0.5 was tried and rejected: junctions are 10m across and the planner already sits near
the limit of what a car can hold, so ordinary turns began missing their apex and getting
re-routed, which reads as a broken car rather than as weather. Note the grip figure has
**two** consumers — the corner planner and the yaw cap — so a sabotage aimed at only one
leaves the other still slowing the car.

Three fixed hours rather than a rolling clock, because three states can be tested and a
shift that drifted through them would mean every lighting check had to say *when* it
was looking. Two faults the first build had, both invisible in code and obvious on
screen: the procedural sky stayed noon blue over a blacked-out city, and its ground half
is white at the horizon, which laid a strip of daylight under the skyline. The minimap
stays a daytime photograph — `build_minimap.gd` bakes it once, and it is a map, not a
window.

All the pacing numbers are exports on the Director node, tunable in the inspector.
`shift_seed` is 0 (a different shift every time); set it non-zero for a reproducible
run, which is what the tests do.

## Dispatch and the career

**One station, and it is the career's home.** The forecourt stocks all six types —
patrol car, ambulance, fire engine, officer, paramedic, firefighter. Emergency 4 has a
house per service, but
this map has one yard, and splitting the roster across the hospital would buy nothing
but a longer walk. The hospital stays what it already was: where casualties are
delivered.

**The map ships empty and nothing is free.** A new career opens with
`Station.STARTING_FUNDS` (£2,000) and buys its fleet:

| Type | Price |
| --- | --- |
| Patrol car | £600 |
| Fire engine | £1,400 |
| Firefighter | £300 |
| Ambulance | £900 |
| Officer | £200 |
| Paramedic | £250 |

Money is earned by working calls — every positive scoring event pays the same number
in pounds (`Mission._pay`, wired to the station by group lookup), including the
response bonus at its 0.25–1.0 speed weight, so a fast shift buys roughly one
vehicle. Losses cost score only; there are no fines, because an empty purse is
already the punishment and a fined career spirals. Funds and the owned fleet persist
in `user://career.cfg` — the third and last save-shaped file — with RESET CAREER in
the settings card.

**Buying is the shop** (`UI/ShopPanel.gd`): a storefront overlay opened from the
DISPATCH heading ("DISPATCH · £1,250 · BUY") or by clicking any row that owns
nothing. One card per type — the rendered portrait, the price, a two-line blurb of
what the unit is for (all from `Station.TYPES`), the owned count, and a BUY button.
It deliberately does **not** pause: buying mid-shift while the district burns is a
choice the player is allowed to make. While it is open the mouse stops at it and
the keyboard is swallowed, same discipline as the title card.

**"Available" is derived, not counted**: what is owned minus what is standing on the
map (`Station._alive`, a live scan over `type_of`), so there is no bookkeeping to
drift. Dispatch spawns a unit only while something owned is still in the house — and
sets crew **portraits** from `TYPES`, because with no pre-placed units nobody else is
left to do it. It also re-marks the unit's respawn anchor after placing it
(`Unit.mark_spawn()`): `_ready` runs at the origin, and respawning to the origin
drops a unit inside a block.

**A returning unit parks.** `Station.accept()` stands it on a free forecourt slot —
two rows of four, **both on the street side of the yard** — visible, selectable,
ready to go again. It used to free the unit back into a counter, which the career
made wrong: it read as the game repossessing what the player had paid for.

The street side is measured, not chosen. The slots originally sat building-side,
and the first career's units "never appeared": a pick-ray probe from the opening
view showed everything at z ≥ +0.5 of the apron centre swallowed by the station's
own block — bought, alive, auto-selected, invisible. Every candidate slot depth was
probed pickable before being adopted, and a check now dispatches two units and
demands the opening-view ray reach both.

Types are **derived, not declared**: a unit's `service` and whether it is a `Vehicle`
are enough to name which of the four it is, so any two units of a type are
indistinguishable to the station without either being tagged.

Slots are checked before use — two units dispatched in the same breath would
otherwise be handed the same spot and shove each other across the yard. If every slot
is occupied it uses the first anyway: a brief overlap sorts itself out, and a
dispatch button that silently does nothing does not.

`ReturnAbility` is instant: there is one station, so there is nothing to click. It finds
it through the group rather than holding a reference, because an `Ability` is a
`RefCounted` shared by every unit of its type and cannot own a pointer to one station
before the map has finished building.

> The dispatch rows are a **flat list, not pills** — and purchasing moved off the
> bar entirely, to the shop. Its brief life as per-row chips is worth the record:
> the first chip attempt used themed Buttons whose stylebox padding grew the bar to
> 191px, the *third* time this block sprang the same trap (pills at 190, command
> tiles at 176). A `PanelContainer` grows to fit its contents, the bar grows with
> it, and whatever sits above the bar silently stops being clickable. The 148px
> height check catches it every time.

### A unit going home drives it properly

Returning is not a shout, so a vehicle recalled to the station **runs dark, holds the
limit, and keeps to its own lane**.

`Order.is_emergency()` is the seam — true for everything the player sends a unit *to*,
overridden false by `ReturnOrder`. `Vehicle.is_responding()` reads it for the lightbar
and for `_cruise_ceiling()`, which drops from `max_speed` to `legal_speed` (12 m/s,
matching the ambient traffic). The vehicle has no way of knowing on its own whether it
is going to something or coming back from it; the order does.

Lane discipline needed routing, not a flag. Left to the navigation mesh a car
straight-lines down the **middle** of the road — the mesh covers the full width, so it
has no opinion about which side to use — and cuts the corners off junctions.
`ReturnOrder` instead routes junction to junction with `CityGrid.route()` (breadth-first
over the 4×4 lattice) and lays two waypoints per street, offset right of travel by
`LANE_OFFSET`. That is the same scheme the ambient traffic drives, and they now share
the constants.

Two legs are not junction-to-junction and both needed their own waypoint:

- **Getting to the first junction.** The route starts at the *nearest* one, which is
  often behind the car — parked halfway down a street it has to drive back to the
  corner, and without a waypoint it does that down the middle.
- **Getting off the grid at the end.** The forecourt is not on a street, so the last
  stretch runs along whichever road passes it. Without that waypoint the mesh takes the
  car diagonally off the junction and across the oncoming lane.

Measured over a drive from the far corner of the district: **6% of samples over the
centre line with the lane route, 18% without.** The residual 6% is turn arcs, which
reach past the junction box and are counted deliberately — excluding them made the check
pass whether or not the route was in lane at all, which is the more useful thing to know.

People on foot just walk. Their navigation mesh is the pavements, which is already the
rule that applies to them.

## Roles

`Unit.service` decides what a unit can do, not just what colour it is drawn.

| Service | Verbs |
| --- | --- |
| **Police** — officers, patrol cars | Move, Apprehend, Extinguish, Secure, Board, Stop; Escort on the cars |
| **Medical** — paramedics, the ambulance | Move, Treat, Collect (the stretcher run), Board, Stop; the ambulance carries and delivers |
| **Fire** — firefighters, the engine | Move, Extinguish, Board, Stop — one verb, done properly; the engine carries the crew and the hose |

The gating is **hard**. An officer is not offered Treat at all, so right-clicking a
casualty with one selected produces a **Move** order and nothing else. Sending the wrong
unit is a wasted trip rather than a slower one, which is the point of having a roster to
choose from.

It needed no new machinery. `Unit.resolve()` already picks the best-scoring ability and
returns null when none applies, so an ability that is simply not in `_build_abilities()`
can never win a right-click and never gets a command tile. `Collect` moved from
`stretchers > 0` to `service == MEDICAL` for the same reason — `stretchers` still decides
how many it can carry.

Police keep the extinguisher a patrol car actually carries: enough for a bin or a
vehicle. A building fire yields to nothing but a crew on an appliance's hose — an
officer can stand in front of one all day and the intensity will not move.

### Secure has to be armed

`SecureAbility` is the one verb that declines every right-click on purpose. It applies to
any patch of ground, so left to score it would swallow Move and an officer could never be
sent anywhere without cordoning it off.

That is what `Ability.can_target()` is for: it defaults to whatever `score()` says — right
for every verb that also wants to win a right-click — and Secure overrides it to accept a
target the player has deliberately armed. `RTSController._fire_armed()` asks `can_target`,
not `score`.

`SecureOrder` extends `WorkOrder`, which needs a *node* to walk to, so the `Cordon` is
created immediately and unraised and **is** the target. The officer walks to it, works for
three seconds, and raising it is the finish. Abandon the order and a cordon that was never
finished goes with it.

The cones have **no collision** — the prefab's `StaticBody3D` children are stripped. A
ring of bollards across the road would trap the ambulance the officer put it there to make
room for. Keeping the public out is a decision the crowd makes: `Civilian` checks cordons
before fires, because an officer saying "not here" should move someone along whether or not
anything is burning.

### The paramedic and the firefighter are wearing police blues

The City pack ships police characters and nothing else — no paramedic, no firefighter —
and no fire appliance either. Paramedics wear `Character_Female_Police`, picked because a
second uniformed responder at least reads as an emergency worker and is tellable from the
male officers at a glance. The **fire service goes further and repaints**: the firefighter
is `Character_Male_Police` and the engine is the **van** body, both folded through
`PolygonCity_02_A` so that at RTS distance the appliance and its crew read as fire rather
than as more police. `build_portraits.gd` shoots their avatars through the same palette, or
the shop would sell a red engine off a white photograph.

The engine was the patrol car's own hull until August 2026, which read as a saloon with an
odd paint job. The van is 30cm wider and 26cm taller on a longer wheelbase — and, unasked
for, ships **rear doors** as separate meshes, so the crew now disembark through doors that
swing.

> **An alt palette is a texture atlas, not a colour.** Each mesh's UVs choose which swatch
> of it they land on, so one palette paints two meshes two different colours and there is
> no "orange material" to reach for. This has cost two shipped bugs. `04_A` is genuinely
> orange on the patrol car's hull, which is why it was picked — on the van it averages
> `rgb(.27,.29,.28)`, a flat charcoal, and the first build of the appliance swap shipped a
> **black fire engine**; on the crew mesh it averages `rgb(.39,.39,.30)`, and the
> firefighters had been quietly **green** ever since phase 19. `02_A` is the warmest of the
> twelve on both bodies. It has to be *sampled per mesh*: the material's name proves
> nothing. A check now samples each body's own UVs and asserts red leads both other
> channels, which is what tells warm from olive as well as from grey.

Swapping in a real appliance is one line — the `prefab` in `build_vehicles.VEHICLES` — and
nothing else in the game has to change. Keep the three palette references in step:
`build_vehicles.VEHICLES`, `build_character.CHARACTERS` and `build_portraits.ALT_FIRE`.

What makes them a paramedic is their **service**: medical green on the avatar, the
selection ring, and the map dot, and the fact that they are the only unit that can treat
anybody. No amount of code fixes the jacket.

## Calls

An `Incident` is a body on the ground or a thing on fire. A `Call` is the **shout**: a
kind, a street address, an age and a state, wrapping everything at one scene.

Grouping is the whole point. One fire left alone becomes eight, and eight rows on the
board would be eight jobs when it is plainly still one. An incident joins the nearest
open call within `GROUPING_RADIUS` (14m) and only opens a new one when there is nothing
near — so a spreading fire stays a single line, and a casualty beside it silently
upgrades that line from **Fire** to **Fire, casualty reported**. Kind and position are
both re-read from whatever the call holds, so nothing has to announce the change.

`CallBoard` is passive in exactly the way `Mission` is: it watches
`SceneTree.node_added` rather than being told, so anything appearing later is picked up
without registering itself.

> One ordering trap, and it is easy to miss: `node_added` fires from **inside**
> `add_child`, and `Fire._spread()` sets the new fire's position *after* adding it.
> Reading the position there puts every spread fire at its parent's feet — close enough
> to group correctly by luck, and it would silently stop being so the day something
> spawns further from its parent. Adoption is deferred a frame.

A call also closes itself if its incidents are **freed** rather than resolved. Freeing
emits nothing, so without that a torn-down scene leaves a call on the board forever
holding a list of dangling references.

Addresses come from `CityGrid.place_name()`. The grid has four road bands per axis, so
the district has four avenues and four streets, and every point in it has a nearest
crossroads — which is how anyone would describe a location over a radio.

**Outside a shift the mission still reads incidents directly, not calls.** That is
deliberate: the incident rules work and are well covered, and keeping the board a
*view* rather than the authority means it cannot be the thing that breaks them.
Freeplay is where calls become what the game is judged on — see "Freeplay".

## The interface

An Emergency 4–style **docked bar** owns the bottom 148px: portrait, roster, command
tiles, dispatch. It is opaque and it stops the mouse, so a click that lands on it is a
click on the interface and never also an order out in the world. Everything else —
status strip, incident pills, minimap, controls, banner — floats over the 3D view and
ignores the mouse, except the minimap and the incident rows, which opt back in.

The camera still renders full-screen behind the bar rather than into a letterboxed
`SubViewport`. For a solid bar the result is identical, and it leaves camera picking
untouched.

### It is laid out for 1600x900 and scaled from there

`setup_project.gd` sets `stretch/mode = canvas_items` against a 1600x900 base, so every
offset in `HUD.tscn` is in those units and the interface grows with the window. Without
it the HUD is raw screen pixels: fine at the default size, unusable on a 3440-wide
display, where the bar is a 148px sliver and only the 3D view got bigger.

`aspect = expand` rather than `keep`, so extra width on an ultrawide becomes more city
rather than pillarboxing.

The catch is that the window and the interface are now two different coordinate spaces.
Picking is unaffected — input events and `unproject_position` both work in the scaled
one — but **anything measuring the interface must ask the viewport, not the window**,
and `smoke_test.gd` sets `root.size` to the stretch base so its synthesised clicks land
where it thinks they do. At any other size they came out about a third off.

The scheme is **light**: pale chrome, white cards, dark ink, rounded corners, pills.
It reads better over a bright Synty city than the dark scheme it replaced — a white
card with a saturated service colour on it stays legible against a lit shopfront in a
way a dark translucent panel does not.

`Palette.gd` holds every colour, `build_theme.gd` bakes `Theme.tres` from it, and the
drawing code reads the same constants. Without one table the theme and the `_draw`
calls drift, and a unit ends up one blue in the roster and a different blue on the map.

### Unit avatars are real renders

`build_portraits.gd` photographs every vehicle and character prefab — one camera angle,
one lighting rig, and **one orthogonal frame size shared across each group**, sized from
the largest member. So every vehicle is shot identically *and* keeps its true size
relative to the others: the ambulance is visibly the big one. Framing each subject to
its own bounds instead would make a hatchback and a van the same size on screen.

    godot --path . \
      --script res://Game/build_portraits.gd

**Run it with a window.** It renders through a `SubViewport`, and `--headless` is the
dummy driver: every capture comes back empty and the portraits save as blank PNGs.
Same trap as the map's MultiMesh buffers, and just as quiet — a unit with no portrait
silently falls back to a drawn outline, so nothing breaks, it just looks worse. A test
asserts every commanded unit has one.

Shot from the *shipped prefabs*, not the generated scenes: a prefab is pure meshes,
while a generated vehicle is a `CharacterBody3D` carrying a navigation agent and a
script that expects to be in a live map.

### Symbols come from the icon pack

The command tiles, incident marks and avatar fallbacks use the icon pack: one white
64px PNG per symbol key under `Game/UI/Icons/`, curated out of the 4,890-icon pack
parked (and `.gdignore`d) under `Assets/padding/`, tinted to whatever ink each panel
needs at draw time. `Glyph.gd` still owns the mapping, so one texture serves a 54px
command tile, a 38px avatar and a 22px pill badge — and the old drawn primitives
remain in the same file as the **fallback** for any key without a texture, the same
rule the minimap applies when its base render is missing. A check asserts every key
the game uses resolves to a texture, because the fallback failing *quietly* is the
whole danger of having one.

The controls card draws the keyboard as keycaps (`Game/UI/Keys/`, from the pack's
dark set), sectioned by function — SELECT, ORDER, CAMERA, MINIMAP, SHIFT — and ships
closed: the CONTROLS chip above the bar (or F1) opens it. The command block is sized
so the fattest selection's seven tiles fit **one row** — let them wrap and the
PanelContainer grows, the bar grows with it, and whatever sits just above the bar is
silently covered. That is the dispatch-pill trap again, and it ate the CONTROLS chip
for a morning; a check now pins the bar's height with the ambulance selected.

### Service is identity, not capability

`Unit.service` (POLICE / MEDICAL / FIRE / NONE) is what the interface colours by: the
avatar fill, the minimap dot, the roster's membership. Phase 13 will read the same
field to *gate* abilities, which is what makes "send the right unit" mean anything —
but today it says who a unit is, not what it can do.

It is also what keeps the roster honest. The roster lists **every unit with a service**,
which is exactly the set the player commands; civilians and ambient traffic are `NONE`
and never appear. A looser filter fills the bar with shoppers.

### The minimap is a photograph too

`build_minimap.gd` renders the district from directly overhead into
`UI/MinimapBase.png`. It shows the real city — which block is the hospital, where the
forecourts are — and it cannot drift from the world because it *is* the world. Markers
are still drawn on top every frame.

    godot --path . \
      --script res://Game/build_minimap.gd

Re-run it after `build_map.gd`. Two things have to be exactly right or the map lies
about where things are:

- **The camera is orthogonal.** A perspective shot has parallax — buildings lean
  outward from the centre — so a marker at the edge would sit beside a building it is
  nowhere near.
- **The camera basis is written out longhand, never `look_at`.** Looking straight down
  makes the up vector colinear with the view, so Godot picks an arbitrary roll. That is
  the same trap that put the whole road kit in at right angles to its streets; here it
  would silently rotate the map under the markers.

The render also has to be *flattened* first: the scene is lit for a street-level view,
and from 200m up the depth fog swallows the city while the low sun lays shadows across
it in stripes that read as streets that are not there. Fog off, sun overhead, shadows
off, saturation down.

With no base image the panel falls back to drawing the street plan from the road slabs'
own collision shapes — plainer, but it works before the generator has been run.

### The roster is a control, not a readout

It shows the whole shift rather than mirroring the selection, so the parked ambulance
can be sent from the bar without first finding it in the street, and one glance says how
much of the shift is committed. Fill carries state: pale is standing by, solid is
working, faded is riding in a vehicle, and a dark ring marks the selection.

### The command grid is still generated

Unchanged from the first version: tiles are built from whatever abilities the selection
advertises. What is new is that `Ability` also declares an `icon()` and a `hotkey()`,
and that the union comes from `RTSController.available_abilities()` rather than being
recomputed in the panel — so the tile you can see and the key printed on it are always
the same ability.

Give a unit a new verb and a tile appears, with its key bound, with no change to any UI
file.

### Why the hotkeys are Z X C V B N M

Because almost nothing else is free, and what takes the good keys takes them by
*polling*. `RTSCamera` reads `W A S D` and `Q E` through `Input.get_vector` every
frame, so those keys pan and rotate whether or not an event was consumed — binding a
command to `W` would move the camera as well. `F` is focus, `R` is respawn, `Esc`
disarms, and `1`–`9` are control groups.

Tiles are laid out in `RTSController.COMMAND_KEYS` order, not keycode order, so a
tile's position along the row matches the key under the player's hand. Sorting by
keycode would put them in alphabetical order instead, which teaches nothing.

### Panels are wired from a setter, not from `_ready`

Godot readies **children before their parent**, so by the time `HUD.gd` hands a panel
its controller reference, that panel's own `_ready` has long since run. Reading the
reference there finds null. The roster and the command grid connect from a setter for
exactly this reason; the version that did it in `_ready` looked completely correct and
left both panels empty for the whole session.

## How the vehicle drives itself

`Vehicle.gd` is split in two:

- A **motion model** that reads `throttle_input`, `steer_input` and `handbrake_input`
  and knows nothing about where they came from. Speed is driven directly, heading
  comes from a bicycle-steering model capped by a grip limit, and leftover sideways
  velocity is bled off. So the same car could still be driven by a player controller.
- An **autopilot** that writes those inputs to follow a move order.

The autopilot steers at the next corner of a **navigation path**, not straight at the
destination, so it follows the streets round a block rather than driving into it. It
eases off for sharp turns and again on approach, and reverses to swing its nose round
when the target is close but behind — a car cannot turn on the spot.

### Steering around what is in the way

Vehicles are solid, so the autopilot cannot simply aim at the next path corner and
drive. Each frame it looks for a vehicle in the **corridor** it is about to sweep —
ahead of it, and within `avoid_width` (2.4m) of its own centre line. A corridor, not
a cone: a cone opens with distance, so a car parked at the kerb 12m up the road counts
as an obstruction, and the patrol car then crawls the length of its own station
forecourt. (It did. The corner-to-corner drive test, which has only 18% of its frame
budget to spare, is what caught it.)

With a blocker, `_passing_line` looks for a way round: the overtaking side first —
the left, this district driving on the right — then the other side, for something
sitting in the oncoming lane. A line counts as a gap only if it is close to the
navigation mesh and has nobody standing in it, so a pass cannot swap one obstruction for
a head-on. No gap means hold station at the blocker's own speed — a rolling queue keeps
rolling.

This paragraph used to claim the mesh test also kept the car off the pavement, "for
free". **It never did.** Both navigation regions live on the same navigation map and
`map_get_closest_point` takes no layer filter, so a point in the middle of a pavement
comes back 0.00m away. `map_get_path` does take the filter — and swapping it in was
measured and reverted: aiming a little wide of the carriageway is how the car gets round
anything at all, and the kerb it aims over then holds it on the road like a rail. The one
car in the road went from passed in 23s to never got through in 45. See NEXT.md for the
full finding, including why a 7cm kerb is a wall to a vehicle and not to a person.

A **raised cordon turns traffic back**. The cones are visual — a cordon that physically
blocked the road would trap the ambulance the officer put it there to make room for — so
without this a car drove into a closed scene and waited for something that would never
move. `_turn_back` sends it the way it came, deliberately not `_reroute`, which refuses to
double back: right for a busy street, wrong for a closed one, since the only way out of a
closure is the way in. Noticed at 34m rather than 26 because the turn itself carries the
car forward — at 26m it ended up 2.7m inside a 6m ring.

`avoids_vehicles` is off for `TrafficCar`: ambient traffic queues instead. A taxi
swinging into the oncoming lane to get past a bus would be the district driving like
an emergency.

### Getting past, and being let past

Traffic pulls over for a responder, and the **warning is time rather than distance**:
`pull_over_notice` seconds of closing speed, so fifty metres at full pelt and sixteen for
one crawling. A flat 16m was two thirds of a second at 25 m/s — the car started tucking
when the response was already on top of it and never cleared the lane, so the pass was
spent crawling behind it anyway. Past a certain range the responder must also be *coming
this way*, or half a street tucks for a response that has already gone by.

`Vehicle.held_up_for` counts time spent doing somebody else's speed because there is no gap
to pass through. The give-up timer watches for *no progress* and a crawl is progress, so
before this a journey could run its whole length at a taxi's pace with nothing noticing.
It **cools rather than resets** when the car gets clear: a held car is a stopped car, a
stopped car trips the escape manoeuvre, and for those frames there is no blocker in the
corridor at all.

### And giving up on the street entirely

Holding station works for a queue and not for a wall. `MoveOrder` watches the car close
on whatever it is currently aiming at, and six seconds of no progress writes that street
off: the two junctions either end go into a `shut` set, `CityGrid.route` refuses to cross
them, and the car plans again. Three streets per journey, then it stops trying — enough
to go round a block, short of touring the district rather than admitting it cannot get
there.

Three things this needs that are not obvious:

- **Progress, not speed.** A car shuffling forward and back under the escape manoeuvre is
  never stationary and never arriving. `TrafficCar` learned this in phase 12; this is the
  same rule.
- **A three-point turn is not a stall.** The distance to the target *grows* through one,
  so `Vehicle.is_turning_round()` exempts it. Without that, a car sent somewhere behind it
  wrote off the street it was standing on before it had finished setting off.
- **The re-plan has to be allowed to turn round.** The new route almost always starts back
  the way the car came, and a car nose-first against an obstruction cannot come round on
  steering alone. So one aim after a give-up gets `may_turn_round`, the generous reverse
  latch range. Without it: a perfectly good route round the block and 0.6m travelled in
  sixty seconds.

The route also skips its approach waypoint when the car has **already passed** that
junction along the first leg. The lattice starts from the nearest junction and nearest is
often behind, which sends a car backwards to a corner and then demands a 180° turn at a
waypoint 48m off — beyond the reverse latch's range, so it drives a circle instead. From
one recorded start it turned through **523°** before making any ground toward its
destination.

And it only writes a street off when something is **actually in it**. Getting nowhere and
being blocked are different, and confusing them is expensive: a car recorded in play
reversed out of its own escape manoeuvre with nothing within 14m, decided the street was
shut, wrote off two, and turned a journey 200m east into twenty waypoints ending at the
far west edge of the district. The test is deliberately longer and wider than the passing
check's, and is aimed along the way the car is *trying to go* rather than the way it is
pointing — a car the escape has just reversed faces back down the street.

Below `LANE_ROUTE_MIN` (40m) a journey normally gets no lane route at all — routing an 8m
nudge round the lattice is a detour, not tidier driving. A journey with a street written
off is the exception: there the straight line is precisely the thing that did not work.

### Braking for corners it can see coming

Grip caps the tightest circle a car can hold at `v² / max_lateral_accel`. At 26 m/s
that is **47 m, and a junction is 10 m across** — so a car that arrives at a corner at
speed physically cannot get round it, and swings wide into the oncoming lane.

Slowing for the *current* heading error is not enough, and was the original bug: on a
straight approach the error stays near zero until the car is already in the junction.
`_corner_speed_limit()` instead walks the navigation path ahead, and for each corner
works out the speed it can be taken at — from the car's own geometry, `wheelbase /
tan(steer_lock)` for the circle and grip to hold it — then solves `v² = u² + 2as` for
how fast it may be going now and still be down to that on arrival.

**Measure the turn over a distance, not per vertex.** The navigation mesh rounds a
right angle into a run of small bends: a 90° junction turn comes through as **47° then
31° over two and a half metres**. Taken one bend at a time each reads as gentle and
nothing ever slows. `_direction_after()` samples where the path is heading over the
next `corner_window` metres, which sees the whole corner.

Measured on a 90° junction turn, speed at the apex:

| | Patrol Car | Ambulance |
| --- | --- | --- |
| Reacting to heading error only | 17.8 m/s (needs 23 m) | 9.3 m/s |
| Looking ahead | **9.5 m/s** (needs 6.4 m) | **8.0 m/s** |

Journey time was unchanged, so the car brakes early, makes the corner, and gets back
on the power. `corner_lookahead = 0` turns the whole thing off, which is what the
before column above was measured with.

Two safeguards matter:

- The reverse manoeuvre is a **Schmitt trigger** (`reverse_angle_degrees` in,
  `reverse_exit_angle_degrees` out). With a single threshold the car flip-flops
  between reversing and driving forward every few frames.
- If it is pinned at a standstill for `stuck_timeout`, it backs off and tries a
  different line — a net for what the path cannot express, like being wedged against a
  knocked-over cone.

Every number is an exported property, tunable in the inspector while the game runs.

## The map

A 260m city district on a **52×52 grid of 5m tiles**. Two-tile (10m) roads cut it
into a **5×5 of blocks**, and the road spacing is **irregular** — the band tables
`CityGrid.X_BANDS` / `Z_BANDS` place the avenues and streets, so blocks span 30m to
50m and a test asserts they vary. Most blocks are a one-tile sidewalk ring around a
plot carrying a terrace; the rest are monolith towers (square, round, octagon, old
brick), City Hall, two parks and two parking lots — see BLOCK_PLAN in build_map.gd.

Parks are walkable: their interior is a sidewalk-layer slab under grass and path
tiles, their lawns join CityGrid.pavement_points(), and both the strolling crowd and
the freeplay director use them. Parking lots are walkable too; the cars in the
stalls are batched decoration. **The grass/path kit uses the opposite corner origin
to the road kit** (x[-5,0] measured, against the road kit’s x[0,5]) — hence
`_grass_transform` beside `_kit_transform`. The round tower gets a **cylinder**
collider: a square box around a 23m drum eats clicks aimed past its shoulders.

Every ground tile, façade segment and roof cap occupies `x[0,5] z[-5,0]` **in its own
local space**, so `_kit_transform()` converts a tile centre and a yaw into the
transform that lands a piece there and nothing in the layout has to think about the
corner origin.

**Facing is not one convention but two**, and mixing them up is silent:

| Kit | Authored facing | Helper |
| --- | --- | --- |
| Buildings, sidewalks, props | `+Z` face | `_yaw()` |
| Roads | markings on the `+X` **edge**, street running along `Z` | `_yaw_edge()` |

Every road piece agrees on the second one — lane lines, crossing bars and direction
arrows. Get it wrong and the yellow lines and zebra crossings come out at right angles
to the street they belong to, which is obvious in play and invisible in the tests.

Nine blocks: a police station and a hospital diagonally opposite each other — so a
casualty run is a real drive across the district — plus a City Hall, two office
towers, and terraces of shops and apartments. The two service blocks give up one side
of the block to a drivable **forecourt**, which is where vehicles park.

## Navigation

**The road network *is* the vehicle pathfinding graph.** There is no separate road
graph to keep in sync: the vehicle `NavigationMesh` is baked from road surfaces and
nothing else, so a car cannot cut across the map because there is nothing off-road to
path over. Order one into the middle of a block and it drives to the nearest street.

That falls out of two collision layers on top of the four already in use:

| Layer | Meaning | Carried by |
| --- | --- | --- |
| 16 | Road surface | Road bands and station forecourts (`1 \| 16`) |
| 32 | Walkable, not a road | Sidewalk rings (`1 \| 32`) |

and each mesh's `geometry_collision_mask` picking what it can see:

| Mesh | Mask | Agent radius | `navigation_layers` |
| --- | --- | --- | --- |
| `VehicleNavigation` | 16 | 1.5 | 1 |
| `PersonNavigation` | 16 \| 32 | 0.4 | 2 |

So people use the pavements *and* the roads, and can cross wherever they like -- a
freedom the player's crews use and the civilians deliberately do not; the 7cm
kerb modelled into the sidewalk meshes is well inside `agent_max_climb`, which is what
joins the two surfaces into one mesh.

Buildings are on the world layer only. They never need to carve either mesh, because
neither mesh covers the ground they stand on.

Both bakes happen at build time, from the **static colliders** in the `nav_source`
group, so the shipped scene needs no runtime bake. The colliders are a handful of
slabs — one per road band, four per block — rather than one per tile: the tiles are
flush, so the join is invisible, and the bake has far less geometry to voxelise.

**Give a building the height it actually has.** Picking is a camera ray, so a collider
standing proud of its building silently eats the clicks aimed at anything in front of
it. A uniform 14m box over the 6m police station made its own cars unselectable — the
ray clipped the corner of the box on its way down. Symptom: units in one part of the
map cannot be clicked, everywhere else is fine.

## Lightbars and doors

Both are presentation, so they run in `_process` rather than on the physics tick —
the flash rate has nothing to do with the simulation step.

**The lightbar is not a node.** The prefabs model the bar into the hull mesh and share
one palette atlas across the whole vehicle, so there is nothing to switch on and no
way to recolour just those polygons. `build_vehicles.gd` puts a pair of coloured beads
on top of the modelled bar instead, each with an `OmniLight3D` inside it.

Their positions are **measured, not guessed**: read the hull's own vertices and take
everything within 12 cm of the roof peak, which on an emergency vehicle is the
lightbar and nothing else. That gives x[-0.52, 0.52] y[1.63, 1.74] z[-0.31, -0.06] on
the patrol car, and the bar over the cab on the ambulance.

The beads use `emission_energy_multiplier = 8`, well above 1, so the environment's
glow picks them up. At RTS zoom in daylight the lamp contributes almost nothing — the
bloom is what you actually see.

They **alternate with a double blink** on each side rather than a plain on/off. That
pattern is what reads as an emergency light instead of an indicator, and it survives
being two pixels across from the far end of the district. The test samples both beads
over several cycles and fails if they are ever lit together, because a lamp that is
simply switched on would pass a bare visibility check.

**Bar and siren share their automatic source but not their switches.** Both run on
`(_navigating and is_responding()) or <own switch>`, so an order sent by right-click
lights the bar and sounds the horn together and arriving kills both at once — and a
vehicle recalled to the station drives home dark and quiet, because `ReturnOrder` is
the one order that answers `is_emergency()` with false. On top of that each has a
**manual switch** — `Lights` (`J`) and `Siren` (`K`) — which work parked or moving.
They stay two buttons rather than one because the cases where they come apart are the
ones worth having: parked at a scene you want the bar lit and the district quiet.

`siren_on` and `lights_on` are therefore plain flags that `_update_siren` *reads*.
Neither starts or stops anything on assignment — an earlier `siren_on` setter that
called `play()`/`stop()` itself had to go when the automatic source arrived, because
two authorities over one speaker disagree the moment they are both consulted.
`_update_siren_audio()` guards on `playing` before calling `play()`, since `play()` on
a running player restarts the stream, and on a per-frame caller that is a siren stuck
in its own first millisecond — an easy silence to misread as a stream that failed.
The siren sound is a **recording** (`Game/Audio/siren.mp3`, August 2026), played
through an `AudioStreamPlayer3D` that `Vehicle` builds at `_ready` on every emergency
vehicle. The synthesised two-tone hi-lo it replaced is still on disk at
`Game/Audio/siren.wav` and still works: `SIREN_STREAMS` is an ordered list and
`_looped()` takes the first entry that exists, so the placeholder is the fallback
rather than dead weight. With neither file present the switch still flips; it just
has nothing to say.

`_looped()` is where the format matters. Looping is three fields on an
`AudioStreamWAV` and a single `loop` bool on an `AudioStreamMP3` or
`AudioStreamOggVorbis`, and the MP3 importer leaves that bool **false** — so a
straight path swap gives a siren that plays once, runs out after 2.9 seconds and
falls silent for the rest of the call, while every check that only asks whether a
sound is loaded and playing stays green. That is what *and the sound loops rather
than running out mid-call* pins, via the `Vehicle.loops()` helper. Both switches show their state on their command tile, which fills
blue while one is running — `Ability.is_active()` is the seam, and only toggles
ever return true from it.

**Only the ambulance has doors.** `Door_l`/`Door_r` are separate meshes on it and part
of the hull on everything else, so `door_left_path` is empty elsewhere and
`open_doors()` is a no-op. Each door's origin is its own outer edge — that is where
the prefab hinges it — so opening one is a plain yaw, mirrored between the two.

Watch for the door **glass**: it hangs off the door as a child, and the generator's
flat part-copy used to drop it. `_copy_part()` now recurses. A door that swings open
leaving its window in mid-air is worse than one that never moves.

## The ambient population

60 pedestrians and 22 civilian cars, spawned by `build_map.gd` and driven by
`Civilian.gd` and `TrafficCar.gd`. Both extend the player's own classes — a civilian
walks exactly as an officer does, a taxi drives exactly as a patrol car does — so
neither reimplements locomotion. What they add is a driver, and what they lack is a
player: no abilities, and `is_selectable()` is false.

They navigate by `CityGrid`, not by random points on the navigation mesh:

- **Pedestrians** walk a graph, not the mesh: one hop at a time along their block's
  sidewalk ring (or anywhere in a park), pausing a few seconds at each, and the only
  way across a road is the kerb tile facing a painted zebra -- `CityGrid.walk_moves`
  is the whole rulebook. The person navigation mesh still covers the roads, but that
  freedom belongs to the player's units; a shopper who used it jaywalked constantly.
  A fire within 14m sends them hopping the same graph, taking whichever legal step
  puts the most distance between them and it -- across at the zebras even in a panic.
- **Onlookers.** A body on the pavement or a suspect kicking off (`watch_radius`
  18m) draws them the *other* way -- `_approach` is `_flee_from` mirrored, the same
  one-legal-hop-at-a-time, refusing tiles inside a raised cordon and any tile closer
  than a tile's width to the scene, so the crowd rings a collapse without standing
  on the paramedic's patch. They stand facing it, stop strolling, and disperse when
  the scene clears. Fires deliberately draw nobody: a gather radius outside the flee
  radius would have the same crowd walking in and running out.
- **Traffic** drives junction to junction, aiming at lane points offset
  `LANE_OFFSET` to the **right** of the centre line — which is what the kit's double
  yellow means. Following the navigation mesh instead would put them down the middle
  of the road meeting each other head-on.

A leg is two waypoints — back into lane just past the junction being left, then the
stop line at the junction being driven to — plus a third when the leg starts with a
**left turn**: `CityGrid.turn_apex` puts a point inside the crossroads on the
driver's own quadrant, right of the incoming direction *and* of the outgoing one, so
the car goes around the middle of the junction instead of chording across the
oncoming halves of both streets. Right turns hug their own corner and get nothing.
The returning player vehicles share the same helper. The first is driven *through*
rather than stopped at, and exists purely to hold a car to its own side coming out of
a turn — aiming only at the far end, a car leaving a turn wide corrected over thirty
metres and drove most of the block on the oncoming side. The lane test went from 16
samples over the line to 0 when it was added.

**The fleet is not all blue.** The pack paints every vehicle body off the shared
`PolygonCity_01_A` atlas, so an untreated district is a procession of blue vans.
Parked cars are folded through the Alts palettes by the generator (each colour is
its own batch — the batch key already included the material); ambient traffic
repaints its own body surfaces at spawn (`TrafficCar._repaint`), touching only
surfaces wearing the stock body material, so glass, plates and taxi liveries stay
themselves. Both picks draw from **dedicated paint RNGs**: taking them from the
layout or routing streams shifted a proven district twice — paint must not steer.

Traffic runs at **city speeds (~10 m/s)**, and that is a handling limit rather than a
stylistic choice. `Vehicle` caps yaw rate by available grip, so the tightest turn a
car can hold is `v²/max_lateral_accel` metres. At 15 m/s that is a **16m radius and a
junction is 10m across** — they physically could not get round a corner, and swung
wide into the oncoming lane and the buildings. At 10 m/s it is 7m, which fits.

Two things they must not do, both learned here:

- **Block a click.** They are on their own collision layers (64 traffic, 128 crowd)
  and `RTSController.PICK_MASK` excludes both. Marking them unselectable is *not*
  enough — the picking ray still stops on them, so a shopper wandering between the
  camera and an officer makes that officer unclickable until they move on.
- **Gridlock.** Every vehicle masks every other one (`build_vehicles.VEHICLE_MASK`),
  so nothing drives through anything. This was asymmetric until August 2026 — traffic
  saw the player, the player did not see traffic — on the theory that mutual collision
  would deadlock a queue the moment a patrol car nosed into it. What it actually
  bought was cars sliding through each other, measured at **0.16m between two
  centres**. Solidity is affordable because both sides got a rule: traffic gives way
  at junctions and re-plans when it gets nowhere, and the player's autopilot steers
  round what is in its way. Traffic still yields to anything within 9m and 45° of
  dead ahead — a group scan, not a physics probe, because a ray would catch the
  buildings a car turns towards and stop it at every corner.

**Three rules keep solid traffic moving**, and each earned its place by a jam that
happened without it:

- **Give way at the crossroads** (`_junction_taken`). The follow rule deliberately
  only sees traffic going the *same* way, so crossing cars ignored each other and,
  once solid, met in the box. The rule is a **strict total order** — give way to any
  approaching car nearer the junction, ties broken by instance id — so in any group
  exactly one car waits for nobody and a cycle of "after you" cannot form. Anything
  already inside the box has right of way outright: the middle of a junction is the
  one place a car must not be asked to stop.
- **Re-plan when you get nowhere** (`_reroute`). Watched as *progress*, not speed: a
  car wedged against a kerb shuffles back and forth under the escape manoeuvre
  forever, never stopped and never arriving. After 8 seconds without getting closer
  to its waypoint a car re-anchors to the nearest junction and takes another street.
  This is the backstop that makes solidity safe — a car shoved off its lane and
  pinned against a parked patrol car has no way to nose through, so waiting is not a
  plan. Removing it puts a permanent stall back in the district within a minute.
- **Space them when they are laid down** (`build_map.TRAFFIC_SPACING`). Two cars used
  to spawn 3.9m apart, which is inside each other for a 5m body. It went unnoticed
  for as long as they were ghosts; the day they became solid the physics engine did
  what it is supposed to and flung the pair apart, and one of them left the world at
  600 metres down. The station's dispatch slots learned this same lesson first.

**Yield only to traffic going the same way.** A direction-blind cone deadlocks: two
cars meeting at a crossroads each hold the other in front, both stop, and neither ever
moves again. Six of nine cars stalled permanently, and the rest queued behind them.
Queueing is the case worth handling; crossing paths is already covered by traffic not
colliding with traffic. A five-second timeout backs it up, because a junction that
never clears is worse than a moment of overlap.

**Traffic pulls over for blues.** A player emergency vehicle *driving under a
response* within `pull_over_radius` (16m) makes a traffic car tuck in at the kerb —
ahead and to the right, over a car length or two — and stop until the responder is
clear (with hysteresis, so one sitting on the boundary does not flick the car in and
out). Two details earned their lines: the trigger requires `is_navigating()`, because
a vehicle *parked* at a scene should be driven around, not parked behind — a
direction-blind version stalled the whole district against the shift on the
forecourt; and the manoeuvre borrows a tighter `arrive_radius` (1.0 vs the stop
line's 2.2), because stopping 2m short of the kerb point is most of the tuck not
happening. The navigation mesh, inset by the vehicle agent radius, clamps how far
right "the kerb" can actually be asked for.

## Picking is a camera ray

Worth its own heading, because it caused the same bug twice in different disguises.
Selection casts from the camera through the cursor, so **anything solid on that line
consumes the click**, whatever it is.

- A building collider taller than its building eats clicks aimed in front of it.
  Give each block the height it was actually built to (`_terrace_height`).
- A camera focused on a *block centre* sits over the building, putting everything on
  the apron below behind its roof. The game shipped briefly with all seven starting
  units unselectable for exactly this reason; the opening camera now frames the
  forecourt.
- At the camera's 52° pitch a 6.8m frontage occludes roughly 4.5m of ground in front
  of it, so units are not parked against walls.

`_test_starting_units_are_clickable` runs first, before anything is teleported, and
checks every unit the map ships can be picked from the view the game opens on. Nothing
else catches this: the units work perfectly, you just cannot select them.

## Changing the map

`Playground.tscn` is generated. Edit the layout in `build_map.gd` and re-run it —
**with a window, not headless**:

    godot --path . --script res://Game/build_map.gd

The district is drawn with `MultiMeshInstance3D` — one node per (mesh, material), so
~2000 pieces cost a few dozen nodes and draw calls. A `MultiMesh` keeps its instance
transforms in the **RenderingServer**, not in the resource, and `--headless` is the
dummy driver, which discards them. The build still reports success, the scene still
saves, every `buffer` comes back empty, and the city renders as *nothing at all*.
Navigation still bakes correctly headless, because it reads collision shapes rather
than meshes — which is what makes the failure so quiet.

Editing `Playground.tscn` by hand in the editor works too — just know that re-running
the generator overwrites it, and that moving a solid object means re-baking.

The build is **reproducible**: `_rng` is seeded, so the same source produces the same
district. Use `_shuffle()` rather than `Array.shuffle()` for anything that affects
layout — the built-in draws from Godot's *global* random state, which is seeded afresh
at startup and ignores `_rng` entirely. The crowd moved on every rebuild for a while
because of that, and since only the crowd moved the district looked stable; it surfaced
as a picking test failing on a build that had changed nothing near it.

## Character animation

`Assets/animations/` holds Synty's Universal Animation Library — 43 clips, in an
in-place set and a root-motion set. Units use the **in-place** one, since code owns
their position; the RM copy suits precisely-placed one-shots.

The two rigs were unrelated: the characters use Synty's own naming (50 bones) and the
library uses the **Unreal mannequin's** (65 bones). Both are now mapped onto
`SkeletonProfileHumanoid`, so the importer renames their bones to a shared set and
fixes the rest poses. The maps live in `Rigs/`, and the importers reference them via
`retarget/bone_map`. To redo it from scratch:

    ... --script res://Game/setup_retarget.gd     # writes maps, patches importers
    ... --import                                  # reimport with retargeting
    ... --script res://Game/build_character.gd    # rebuild Character.tscn
    godot --path . --script res://Game/check_retarget.gd    # verify (needs a window)

**Synty's bone names do not mean what a humanoid profile means by them.** `Shoulder_L`
is the upper arm, `Clavicle_L` is the shoulder, `Elbow_L` is the forearm and `Ankle_L`
is the foot. Swap any of those and the rig folds inside out. Synty also merges
middle/ring/little into one finger chain, so only thumb, index and that chain map —
invisible at this camera distance.

`Character.tscn`'s layout is load-bearing: the clips' tracks are authored as
`Armature/GeneralSkeleton:BoneName`, so the skeleton must sit at exactly that path
under the `AnimationPlayer`'s root or nothing binds.

One trap worth knowing: an `autoplay` set on an **instanced** scene's child is not
preserved by `PackedScene.pack()`. A first attempt at a check scene did that and
rendered six identical T-poses that looked exactly like a failed retarget.
`check_retarget.gd` therefore plays clips at runtime and asserts bone rotations differ
from rest, rather than trusting a saved scene.

`AnimationViewer.tscn` browses all 43 clips on the retargeted character — run it
directly with `godot --path . res://Game/AnimationViewer.tscn`.

## Verifying

    godot --headless --fixed-fps 60 --path . --script res://Game/smoke_test.gd

`--fixed-fps 60` decouples the headless loop from the wall clock: same fixed-step
physics, same checks, ~20 seconds instead of ~9 minutes.

650 checks. Runs real physics without a renderer: the fixtures buy and dispatch a
shift through the station (the map ships empty), and every bought unit is clickable
from the opening view; the crowd strolls, runs from a fire and cannot be selected or
picked through; traffic drives the roads and yields; units start parked, drive to a
target, stop on arrival, turn around for a target behind them, cross the district
corner to corner, route around the centre block, and — ordered into the middle of a
block — come to rest out on the street instead; synthesised input for select /
deselect / box-select / shift-add / control groups / order / queued order / Stop /
marker / respawn; camera pan, clamping and zoom; the interface — the bar stays docked
and leaves the world clickable, the command grid tracks the selection in keyboard
order, hotkeys arm and fire, the roster lists the shift and refuses civilians, a chip
selects its unit, every unit has a rendered portrait; calls — an incident opens one,
a spreading fire stays one, a casualty upgrades it, a unit arriving marks it attended,
a loss fails it, clicking a row jumps the camera; roles — an officer is offered no
Treat and resolves a casualty to Move, a paramedic no Extinguish, Collect follows the
service, Secure declines a right-click but accepts an armed one, an officer walks over
and sets a cordon out, and the public leaves it; dispatch — the station counts the shift
it starts with, hands out what is left and then refuses, and a unit sent home stands down
and frees its slot; freeplay — the director sleeps until F2, opens calls of every kind
clear of the forecourts and each other, holds the cap and the breather, an RTC reads as
one named call, a fast response outscores a slow one, a lost casualty costs points
rather than the shift, and the debrief waits for the last call to close; and
personnel — walking onto the pavement, animation clip selection, the two navigation
layers, boarding, unloading and seat limits. Exits non-zero on failure.

Three things the harness has to do, all learned the hard way:

- **Clear the map's own incident first.** The demo shout is a live fire that
  *spreads*, and each new fire is a body parented under `Incidents`. Left alone it
  litters the street the tests work in and swallows the clicks meant for the car —
  which looks exactly like a picking regression. Nothing in the suite needs it; every
  incident test spawns its own.
- **Exercise the ambient population, then delete it.** The crowd and the traffic are
  tested first and then removed, because everything after that teleports units around
  and clicks on them, and nine independently-driving cars are not a fixed backdrop.
  Where a check depends on what is nearby — traffic yielding — the test clears the
  other cars rather than asserting on where they happened to drive.
- **Sample a reaction while it is happening.** The flee check reads `is_fleeing` after
  0.75s, not 3s. By 3s the civilian is clear of `flee_radius` and correctly back to
  strolling, so the later sample reads false and looks like a broken reaction.
- **Do not assume a particular unit is in a convenient spot.** The civilian picking
  check used to aim at whichever civilian happened to be first, which meant it depended
  on one standing clear of the lamp posts. It now *looks* for one the camera has a line
  to. A check that fails because the crowd moved is a check nobody trusts.
- **Order can make a check vacuous.** The roster is meant to exclude civilians — but
  the suite clears the crowd long before the roster is tested, so the check passed with
  the filter deleted. It now puts a civilian back on the map first. Reverting the fix
  and watching the test still pass is the only way to catch this.

- **Set `root.size` explicitly.** `--headless` gives a **64x64** viewport, which makes
  `unproject_position` meaningless and leaves the docked command bar spanning the
  entire screen, where it eats every click as GUI input before `_unhandled_input` sees
  it. Symptom: right-clicks silently do nothing, but only after a *clicked* selection
  — a code-driven selection still works, which makes it look like an input bug rather
  than a layout one. `_test_bar_is_docked_and_solid` now asserts the bar leaves at
  least 70% of the window to the world, which catches this directly.
- **Push events with `Viewport.push_input`,** not `Input.parse_input_event`, which
  only queues; nothing reliably pumps that queue without a display server.

Two of these checks assert things no behavioural test would notice, because the code
never reads them: that a walking officer's model faces the way they travel, and that a
casualty is actually lying down. Both would otherwise pass while looking wrong.

`screenshot.gd` renders the scene to PNGs under `user://shots/`. Pass a scene after
`--` to render that one instead, e.g. the pack's own `Scenes/Demo.tscn`.

## Notes on the assets

- **The pack ships no `.fbx` files** (bar `Characters.fbx`) — the meshes are
  pre-extracted `.res` files under `Models/extracted/`. Nothing is missing.
- **`Mat_01` … `Mat_04` are palette swaps** over identical UVs: 01 blue, 02 red,
  04 orange. That is how the pack's own Demo scene gets its colour variety. The car is
  red because `Car.tscn` overrides to `Mat_02`; change that one line to recolour it.
- **The Synty meshes face `+Z`**, but Godot's forward is `-Z`. `Car.tscn`,
  `Person.tscn`, `Paramedic.tscn` and `Suspect.tscn` all yaw their visuals 180° to
  correct it. Miss that on a character and it moonwalks — steering is right, the
  model just looks backwards — and *every other test still passes*, because nothing
  in code reads the model's orientation. It has now happened twice (the officer, then
  the suspect), so **every scene that walks gets an explicit check** that the
  visual's `+Z` lines up with the direction of travel. The same blind spot hides a
  character facing the wrong *target*: the suspect's punches played perfectly while
  landing on empty air, until a check compared the model's forward axis with the
  bearing to the officer.
- **`Car.tscn` does not instance the car prefab.** That prefab wraps its chassis and
  each wheel in `StaticBody3D` nodes, which would fight the `CharacterBody3D`. It
  references the same meshes directly; wheel offsets match the prefab exactly.
- **The POLYGON City kit is a strict 5m grid**, with a corner origin at `x[0,5]
  z[-5,0]`. Ground tiles, façade courses and roof caps all share it, so one placement
  helper serves the lot. Two-tile pieces (`Road_ParkingLines_01`, `Shop_03`) and the
  monolithic buildings do not, and are placed by measured footprint instead.
- **Read a piece's orientation off a plan view, never off a raking one.**
  `inspect_tiles.gd` at 90° pins screen-right to `+X` and screen-down to `+Z` by
  writing the camera basis out longhand. It used to use `look_at`, which for a
  straight-down view has a colinear up vector — Godot warns and picks an arbitrary
  roll, so the sheet renders at some unknowable rotation. Two orientation bugs came
  from trusting that sheet: the whole road kit went in at right angles to its streets.
- **Props do not all stand on their origin.** `TrafficLight_01/02/03` hang *below*
  theirs (`min y = -0.9`) because they are heads meant to bolt onto a mast arm —
  dropped on a pavement they are entirely underground. `TrashCan_01` is centred on its
  origin and sits half-buried. Measure with `inspect_meshes.gd` before placing, and
  look at it with `inspect_tiles.gd` before trusting the name: `LightPole_Base_01` is
  a 6.5m signal mast, `Base_02` is a complete 5m lamp standard.
- Collision layer 2 marks knockable props, and the car's `platform_floor_layers`
  excludes it — otherwise driving over one makes the car inherit the struck body's
  velocity and flings it off the map. Nothing on the city map is knockable yet; the
  layer and the exclusion are kept for when cordons and cones arrive.
- **The pack's `WorldEnvironment` is tuned for a product shot.** Its depth fog sits at
  density 0.26, which over this district bleaches the far blocks, the skyline and
  the sky to a flat grey. `build_map.gd` duplicates the resource and thins it rather
  than editing anything under `Assets/Synty`.
- People are on collision layer 4 with mask 1: they collide with the static world
  only, not with vehicles or each other. Crowd shoving and being run over are their own
  problem and neither belongs in a first pass.

## Restoring the original project settings

`setup_project.gd` changed one thing beyond the input actions: the main scene, which
was `uid://c1taxtw64csmx` (`Assets/Synty/PolygonStarter/Scenes/Demo.tscn`). The
original file is preserved as `project.godot.orig`.
