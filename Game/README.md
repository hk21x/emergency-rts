# RTS playground

An Emergency 4–style demo built on the Synty POLYGON packs: select units, order them
somewhere, and they drive or walk themselves there through a city district — cars
keeping to the roads, people using the pavements.

Everything written for the game lives under `Game/`. The Synty packs themselves are
unmodified, though the POLYGON City pack was relocated on import — see `PROGRESS.md`.

## Where this is up to

**All 15 planned phases are done, plus 16 (the world reacts), 17 (audio), 18 (game
framing), 19 (the fire service) and all of phase 20 — the career economy and the
campaign scenarios.** 1123 automated checks, all passing.

A 260m city district — twenty-five blocks of varied size, with parks, parking lots and
four tower families — with 60 pedestrians and 22 civilian cars going about their business.
The map opens **quiet and empty** — a career starts with £2,000 and no units, buys
its fleet from the DISPATCH block, and keeps it between sessions. `F2` opens a
**freeplay shift**: five, ten or fifteen minutes of calls the district produces — busier
towards the end — scored per call cleared and weighted by response time, with every
task paying its points in pounds. A debrief closes it: score, best, and what was
earned. You command what you have bought from panels floated into the screen's
corners — roster left, commands and dispatch along the bottom, map bottom-left — and work each
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
sample by sample, ready for recordings to replace them the same way. The **fire service**
now has a real appliance — a POLYGON Town aerial, 3.11 x 2.84 x 8.82 against the van in
orange paint it replaced — and, since August 2026, **a real crew**: the POLYGON City
Characters pack supplied a firefighter and a paramedic in their own kit, closing the last
asset gap in the game. The paint check in the suite still guards them; it simply guards a
real turnout kit now instead of a repaint.

Since then the fleet has grown past the road: a **helicopter** that spools its rotors,
climbs, turns on the way and holds a hover where it was sent; a **recovery truck** that
winches away the wreck a collision leaves behind, so an RTC has a tail for the first time;
and an **armed response unit** whose officer talks a weapon down before anybody moves in
to arrest — the first time `Person.speciality` decides what a unit can do rather than only
how fast it does it. The shop and the roster are the user's UI kit now: a requisition
modal and a status sidebar, both drop-ins that kept the old public surface.

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
| **Right click a heating cylinder** (firefighter selected) | stand off it and hose it cool before it goes |
| **Right click a trapped casualty** (firefighter selected) | lift the load off them so a paramedic can work |
| **Right click a casualty** | kneel beside them and treat |
| **Right click a stable casualty** (paramedic selected) | fetch the stretcher from the ambulance and wheel them aboard |
| **Right click a suspect** (officer) | apprehend them; right-click again once cuffed to walk them to a patrol car |
| **Right click a shed load** (officer or firefighter) | lug the spilled cargo off the carriageway until the street reopens |
| **Right click a wreck** (recovery truck) | pull up alongside and winch it away, reopening the street |
| **Right click an armed suspect** (ARV officer) | close in and talk the weapon down before anybody moves to arrest |
| **Right click the ground** (helicopter, airborne) | fly there — it spools up, climbs, turns on the way and holds a hover on arrival |
| **Shift + right click** | queue that order behind the current one |
| `Ctrl` + `1`–`9` | assign a control group |
| `1`–`9` | recall a control group |
| `Z` `X` `C` `V` `B` `N` `M` `G` `H` `J` `K` `L` `T` `Y` `U` `I` `O` `P` | the command tiles, left to right — bottom row, then home row, then top row |
| Command tile | `Move`, `Treat`, `Extinguish`, `Cool`, `Secure`, `Clear` (`O`), `Board`, `Collect`, `Disarm` (`I`), `Connect` (`P`) and `Land` (`Y`) arm the cursor for a target click; `Stop`, `Unload`, `Return` and `Take off` (`U`) fire at once; `Lights` (`J`) and `Siren` (`K`) are toggles — the tile turns blue while one is running |
| Roster row | click to isolate that unit, `Ctrl`-click to drop it, double-click to follow |
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
| `F5` | open the call spawner — pick any call kind instead of waiting for the roll |
| `ENTER` / `SPACE` (title) | play — the session opens on the title card |
| `ESC` | cancel, then pause. It unwinds the innermost thing first: it disarms an armed ability, else closes the shop, else opens the pause menu (resume, restart shift, settings — volume, shift length, call rate, time of day, weather including SHIFT'S OWN — quit to title). Was `P` until August 2026 |

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
| `AudioBuses.gd` | The Music and UI buses, created in code rather than a bus layout |
| `UI/Markers.gd` | The selection bracket and destination reticle, built at load |
| `UI/ClickSounds.gd` | The interface's click and rollover; finds its own controls |
| `UI/Palette.gd` | Every colour the interface uses, in one table |
| `UI/build_theme.gd` | Bakes `UI/Theme.tres` from that table |
| `UI/Glyph.gd` | Every symbol: pack icons with drawn fallbacks, shared by tiles, avatars and pills |
| `UI/ControlsPanel.gd` | The controls card: keycap icons, sectioned by function |
| `UI/GameMenu.gd` | The framing: title card, pause menu (`ESC`), settings, game speed |
| `UI/ShopPanel.gd` | The unit shop: portraits, prices, blurbs, BUY |
| `UI/Icons/`, `UI/Keys/` | Curated icons and keycaps from the pack under `Assets/padding` |
| `UI/Portrait.gd` | Who is selected and what they are doing |
| `UI/Roster.gd`, `UnitChip.gd` | Every unit under command, as clickable avatars |
| `UI/HealthBar.gd` | A hurt crew member's health, under their chip. People only, and only when hurt |
| `UI/CommandGrid.gd`, `CommandIcon.gd` | Command tiles, drawn from ability metadata |
| `UI/UnitBadge.gd` | A unit as a circular avatar, used at three sizes |
| `UI/StatusStrip.gd` | Shift clock and what is outstanding, top-centre |
| `UI/ScoreStrip.gd` | Score, fleet count, and the buttons for pause and settings, top-right |
| `UI/ObjectiveBar.gd` | What to do next, top-left; follows its own label rather than being switched |
| `UI/Minimap.gd` | Overhead map, click to jump the camera |
| `UI/MapControls.gd` | The map's zoom buttons, beside the card rather than on it |
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
| `HUD.tscn`, `HUD.gd` | The floating command panels and the world overlays |
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
taken on purpose at 9 m/s billed £38 at the original rate, and charging for obeying an order is a bill the
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

### Dressing the district, and why height is decoration everywhere but two blocks

Reported from play as the city looking bland and reusing the same assets. The count agreed,
and it pointed somewhere more specific than "bland": the generator named **22 of the 174
props the pack ships**. Buildings were never the problem — those were already at 51 of 75.
It was the street furniture, which is what the RTS camera actually looks at.

`_kerb_prop` is now fifteen ways rather than twelve. Ten are the civic staples it always
had, unchanged; four hand the slot to `_street_litter`, which draws from a table keyed on
the **block's kind**. A parade of shops puts a hotdog stand and a cash machine out, flats
put bins and bags out, a car park and the tower service yards put cones, pallets and a skip
out, a park puts a table and a deckchair out. Two neighbouring blocks no longer collect
identical litter. The district places **45 distinct prop meshes** now.

**Every offset in that table is measured.** A one-off script dumped the AABBs, and the
numbers matter: `SM_Prop_ATM_01` sits centred on its origin (min y −0.77) and needs lifting
or it is buried to the waist; `SM_Prop_Billboard_01` floats 0.72 above its origin because it
expects a pole; `SM_Prop_TrafficLight_01` runs min −0.90 to max 0.00 because it is a signal
head meant to hang off a mast arm. That last one is why the junction signs use
`Sign_Stop_01` instead, and the same trap is written up there.

**Heights vary per block, from a generator keyed on the block rather than a draw.** Facades
and colliders are built in two separate passes, and a shared random stream hands the two
passes different answers depending on how many draws happened in between — a collider
standing proud of its building eats the clicks aimed in front of it. Twenty-one terraces used
to share **three** silhouettes; they now stand at eight.

**Except the two blocks with a forecourt**, which keep the kit's height exactly. Raised a
storey, the police station's wall put itself between the opening camera and every unit parked
on its own apron, and all seven became unclickable at the start of a career. The suite named
it in one line — "ray stops on Block_13" for all seven — and it is the reason height is
decoration everywhere on this map except the two places vehicles park.

### Traffic declines a tuck it has no room for

`TrafficCar._update_pull_over` aims seven metres ahead and a couple across to nose into the
kerb for a passing response. Near the district's boundary that lands outside it: reported
from play as `Traffic3 was sent off the map, to (-86.2, 0.0, -131.0)` on a map that ends at
130. `Vehicle.navigate_to`'s guard caught it, named the caller and clamped — which is that
guard doing exactly the job it was written for — but clamping is the wrong answer here,
because it aims the car at the boundary rather than at a kerb and it performs a tuck towards
nothing while warning, with a stack trace, mid-play.

The point is worked out **before** the manoeuvre is committed to, and the tuck is declined
outright if it leaves the district. Declining is truer than clamping: a car with less than a
tuck's length of district in front of it has nowhere to pull in, so it keeps driving and the
responder passes it like any other obstruction.

The check needs its **positive control** to be worth anything — asserting that an edge car
does not pull over would pass just as happily if the manoeuvre were broken everywhere, which
is the commonest way a check here turns out to be worthless. So the same car, with the same
responder, is then moved into open district and must tuck.

While fixing it, the suite's own staging turned out to be firing the same warning on every
run: `_test_traffic_pulls_over_for_a_response` aimed a car 400m up the street to make a
destination it could never reach, landing at z 402. The distance was never load-bearing — the
test pins the car in place every frame — and a warning that fires by design is chaff that
hides the ones that matter. It very nearly hid this one.

### The shop is grouped by service

Eight buyable types in one row ran off the side of the screen the moment the doctor and the
doctor's car were added — measured, **1906 wide in a 1600 viewport**, with the paramedic's and
the doctor's BUY buttons off the edge. A container that overflows *clips*; it does not wrap,
so those two units were simply unbuyable.

One row per service now, grouped off the `service` key every catalogue entry already carries,
so a new unit lands in the right row without a second list to keep in step. Headings take the
service's own light ink from `Palette.service()`, the same signal the roster and the selection
rings use, so the row is read before the words are.

Rows cost height, and three of them multiply every vertical saving by three: the first grouped
pass came out 964 tall against 900, so the portrait dropped 96 → 72 and the separations moved
onto the named scale. It measures 909 × 844 now.

**Three checks, deliberately, because they say different things.** That every BUY is on screen
and that the storefront fits are assertions about the *symptom*, and both would go green again
if somebody merely shrank the cards. That each service's shelf holds exactly its own units is
the assertion about the *feature* — without it the grouping could be deleted and only the
sizes would complain.

### Specialists inside a service, and the doctor

`Unit.service` is identity — it decides the brand colour, the roster grouping and which
calls a unit is considered for — and until August 2026 it was also the only thing that
decided capability: `Person._build_abilities()` matched on it and nothing else. That made a
*specialist* inexpressible. A doctor can do something a paramedic cannot, but a doctor is
not a fourth emergency service, and inventing one would have been a lie the interface then
had to carry into the palette, the roster and the call routing.

So capability is now service **plus** `Person.speciality`. Empty means the ordinary member,
which is what nearly every unit is. It deliberately does **not** feed `_build_abilities()`
yet: the doctor's difference is what their treatment achieves, not a new command tile, and a
hook with no caller is the kind of thing this project has had to delete before. The hazmat
team is the one that will want it.

The doctor is the first specialist. `Casualty.needs_doctor` marks a casualty beyond what a
paramedic can finish; `Casualty.treat(amount, advanced)` takes *who is treating* as an
argument, and a paramedic on one of these **holds the decline off** without ever
accumulating towards stable. That in-between state — alive, and going nowhere — is the whole
mechanic: the paramedic is how you buy time, and the answer to the question is a dispatch.
The verb is deliberately the same one on both units, because a paramedic sent to a dying
patient should still get to work; telling the player "you cannot even try" would be both
unkind and untrue. `describe_state()` says `needs a doctor` so the readout, not a manual,
teaches it.

**The director gates `collapse` on owning a doctor**, on exactly the terms it gates building
fires on owning an engine and a firefighter. A casualty nobody on the roster can stabilise
is not a hard call, it is a broken one — paramedics would hold them indefinitely and the
call would never close.

**The doctor's car** is the patrol hull repainted, and it is what makes the specialist
dispatchable at all — a doctor who walks the district arrives after the call has resolved
itself. It carries **no stretcher**, deliberately: a rapid-response car that could also run
the patient to hospital would quietly replace the ambulance and dissolve the bottleneck the
doctor exists to be. It brings the doctor to the casualty; the ambulance still does the
carrying.

The paint is worth a paragraph because it has caught this project twice. An alt palette is a
**texture atlas, not a colour** — each mesh's UVs index a swatch of it, so one palette paints
two meshes two different colours. `04_A` is genuinely orange on the patrol-car hull
(rgb .44/.32/.24) and is flat charcoal on the van and olive on a person; picking by name once
shipped a black fire engine and dressed the firefighter in green for months. The check
samples the built scene through the mesh's own UVs rather than trusting the path: sabotaged
back to the stock blue material it reads −0.03 against +0.11 healthy.

**The trap a specialist springs, which is worth reading before adding the next one.**
`Station.type_of()` identified a unit by `(service, vehicle)`, which is exact only while
each service has exactly one kind of person. The doctor made MEDICAL-and-not-a-vehicle match
two catalogue entries; the scan returned the first. Neither symptom points anywhere near the
cause: `write_off()` took a doctor off the books by decrementing the **paramedic** count, and
`_alive()` counted every doctor as a paramedic, so the dispatch panel offered paramedics that
did not exist and refused doctors that did. Units now carry the catalogue id they were bought
as (`Unit.type_id`, stamped in `dispatch()`), and the scan survives only as a fallback for a
unit nobody bought. Any specialist added from here would have re-broken it identically.

A second, smaller one: `ShopPanel` read `config["portrait"]` unguarded while `Station` reads
the same key with `has()`. One catalogue entry without a portrait threw inside `_ready`,
which builds the whole shop, and took out every card and six unrelated checks with it.

### Corner braking comes from the route, not the path

The junction overshoot on the fast cars — two F3s from play, the doctor car sweeping a
90° turn at 16.1 m/s and sailing ten metres past another — is fixed at its root, and the
root is architectural: with junction-to-junction waypoints, **the agent's path ends at
the junction**. The turn onto the next street lives in the *next* waypoint's path and
does not exist in this one until the 7m waypoint switch — far too late to brake from
26 m/s. Every corner the old planner appeared to read out of the path was an artifact of
the car's own off-line position swinging the measured vector (one vertex read 15° at 16m
and 132° a moment later), which is why four rounds of speed tuning over the file's
history changed nothing: the planner was braking for corners it could not actually see,
at strengths set by where the car happened to sit.

So the corner now comes from the thing that genuinely knows it: **the route annotates
its aim with the turn's exact angle** (`Vehicle.turn_at_aim`, set in `MoveOrder._aim`
from the legs either side of the waypoint — the district is a lattice, the angle is
exact and costs one subtraction), and the planner brakes on plain distance-to-aim. Two
companion pieces made it land: the turn's cap **holds while the car is in the box**
(`turn_here` — without it the 7m switch handed the aim onward and erased the constraint
with the car still seven metres short, asks bottoming at 13.1 against a holdable 7.9),
and the in-path scan was rebuilt honest (symmetric windows about each vertex, scan from
the car's true vertex rather than the agent's racing index, and the anti-creep floor
capped by `_turn_speed(PI/2)` so it can never out-ask the physics).

Measured: the doctor car's lane intrusion fell from 3.65/2.86/2.23m to 2.66/1.17/0.46m
across the three probe legs with two legs *faster* (slower in, cleaner line, faster
out); the ambulance's leg-one **60-second timeout became 22.9s**; both F3 geometries
replay clean with zero escapes; and on the empty-district A/B the braked car never
enters within 5m of the box centre at all where the unbraked one crosses it at 13.3 m/s
— which is the suite check's assertion, seen to fail at exactly that number. One
pedestrian landmine on the way: people run MoveOrders too, and the first cut of the
annotation wrote to `unit as Vehicle` unguarded — seven checks were silently truncated
by the Nil write while the suite read green, caught only by the SCRIPT ERROR sweep.

### The bounded turn: manoeuvres planned against the road

The shuffle the black box spent a year recording — a car rocking back and forth over
seven metres, full throttle, nothing in front of it — is fixed, and the diagnosis is
worth more than the code. 42 records from real play, batch-read against the pure-pursuit
capture bound (a point at distance L and bearing a needs **L ≥ 2R·sin(a)**; R is 4.44m
for the patrol car, 6.87m for the engine, which owned 17 of the 42), plus a per-frame
trace of a 20m dead-behind order, settled it: the manoeuvre machinery was a reverse
latch that released at 55° of error into full-lock forward arcs that drift sideways by
R(1−cos 55°) — 1.9–3m, more than the half-carriageway available — so the car stopped
dead on the kerb face, and a blind 1s escape backed it 4m into the same failing arc.
Both safety nets were structurally blind: the escape wants near-zero speed (a shuffling
car has plenty), the latch wants 115° of error to a steer point that sits near the nose
by construction. On an empty street it all works, which is why five earlier staged
reproductions came out clean — the pathology needs traffic or kerb context.

`_begin_turn` / `_drive_turn` / `_plan_turn_leg` replace it with a **bounded multi-point
turn**: each leg is a full-lock arc walked in half-metre samples against
`CityGrid.is_road` and the map bounds *before it is driven*, so a leg can never cross a
kerbless junction mouth or the boundary — exactly where a first, reactive version's legs
went (a flip-on-stall shuttle discovers the edge of the road only by hitting things, and
at junction mouths there is nothing to hit). Legs alternate direction, both rotating the
nose the same way; the latch arms the turn, a crooked-nose escape (>45°, not queueing,
not owned by the mount or return) converts into it, and it exits on its own terms — a
rolling forward leg inside 20° — or abandons on caps (8 legs / 10s) into a 3s re-entry
rest, so it can never own a car it cannot help. The one interaction that mattered: the
conversion must not fire into a shut street, because the pavement mount's licence
accumulates only under 2 m/s and turn legs at 4 m/s starve it.

Measured: `probe_orbit` (all three vehicles, overshoots, dead-behind) arrives everything
in 4.6–8.9s with zero escapes; `probe_corner` 68.4s against 71.4 baseline with zero
frames off the carriageway; `probe_journeys` engine **24/24 at 31 escapes against 23/24
at 75**, patrol 24/24 at 14. The suite check's comment carries the sabotage map — what
it guards, what only the probes can see, and the measured redundancy of the arming and
exit paths.

### Taking the pavement past a shut street, and getting back off it

Right-clicking a verge is one way over a kerb; the other is **earned**, and it is what a
vehicle on a shout does when the carriageway ahead is simply shut. It exists because a
walled street was a journey that never finished: an appliance behind three vehicles abreast
did not get past in sixty seconds, because nothing in the code could tell *queued* from
*shut* and the kerb stayed as solid as it is for a car cornering.

The licence is `road_is_blocked(move_target)` while crawling, accumulated into
`_blocked_time`. Three other signals were tried and each was defeated by the car's own
manoeuvring — `_held_time` peaked at 0.15s, the latched blocker at 1.88s, both against a
2.50s bar — because turning the nose or backing off takes the obstruction out of whatever
corridor was being watched. `road_is_blocked` measures along the way the car is *trying* to
go, which is the one thing shuffling cannot fake, and `_blocked_time` is forgotten at **half**
the rate `_cooled` uses: the test is a snapshot and it flickers (397 of 1409 crawling frames),
so double-rate cooling kept it just under the bar for ever.

Three terms then decide whether the manoeuvre is sane, and the third is the one that matters:
the vehicle must be **on a shout** (`is_responding()`, which is also what the lightbar and the
speed limit hang off, so routine driving and ambient traffic never qualify); the pavement spot
must be standable **and** genuinely off the carriageway (`standable` alone is true of a road,
and with only that test the car drove happily to somewhere it could already drive); and it
must be **clear of a junction**. A kerb runs along a street, but a junction mouth is off the
navigation mesh with *no step on it at all*, so a car mounting there drives onto flat tarmac
and off its route — that one term is the difference between all three junction turns staying
byte-identical to baseline and one of them going from 76.7s to unfinished in 150 seconds.

Once started it is a **latched manoeuvre with its own clock**, like the escape it suppresses.
Recomputed from the blocker each frame it cancelled itself by working, because swinging the
nose towards the kerb is exactly what unlatches the blocker that licensed it. The aim is fixed
in world space and laid out along the route rather than off the bonnet — measured off the
bonnet, after seconds of manoeuvring the "side" of the car points down the street and the aim
came back on-carriageway on both sides every time.

**Going up is only half of it, and the other half is not optional.** From up on the pavement
the navigation agent's nearest reachable point is the carriageway the car *just left* — on the
**near** side of the obstruction. Left to the agent, a successful mount became a loop: 555
frames off the carriageway, 161 of them turning round, driving back into the wall and mounting
again, a 33.3s journey unfinished in sixty seconds. So `_returning` / `_return_line()` steers
the car forwards past the obstruction and puts it down, and two plausible versions of that are
wrong. Deciding it when the mount ends never fires, because a mount ends three metres short of
a seven-metre offset and the car is still over a road tile — coming down is a *state of being
off the carriageway*, watched every frame, gated on the `_mount_point` breadcrumb so it can
never reach ambient traffic. And capping the recovery speed, which reads better on paper,
lets the cornering factor hold the car at 2.69 m/s until the window expires with it still up
there: 40.1s becomes a timeout. It has to be allowed off the pavement briskly.

`Game/probe_mount.gd` is the fixture, and every part of it is load-bearing — three abreast
(one is overtaken, two flap on a decimetre of spacing), an appliance (a patrol car squeezes
through), and a destination under `CityGrid.LANE_ROUTE_MIN` (past that the order writes the
shut street off and drives round the block, which is a perfectly good answer and not this one).

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
  so a test run is reproducible. Every one of those numbers comes from its **kind** —
  see below.
- **`Hazard`** is a pressure cylinder that cooks off if a fire is left burning beside
  it. The first thing in the district that hurts back — see below.
- **`Casualty`** has two separate quantities: `health` runs down on its own, and
  `treatment` is what a worker adds. Treatment stabilises; running out of health does
  not. That gap is the point — arrive late and they are lost, which is a failure the
  player can feel. One can also be **trapped** under a load — treatable where they lie,
  but unmovable until a fire crew works `Free` on them.
- **`Suspect`** paces and gives it some mouth until an officer works `Apprehend` on
  them, fights back while being worked, and is then walked to a patrol car on foot. One
  can also **recruit**: left alone, a public-disorder suspect draws bystanders in until
  somebody stands in it or a cordon goes up.
- **`Cordon`** is the odd one — an officer's ring of cones, not something that gets
  worse. Its only mechanical job is containing a disorder call; the crowd treats it the
  way it treats a fire, and it is deliberately not solid.

**Ask a civilian what it is wearing — never read its `scene_file_path`.** The two live one
directory apart: `res://Game/Civilians/BusinessWoman.tscn` is the *unit*, and
`res://Game/Characters/BusinessWoman.tscn` is the outfit inside it. `ResourceLoader.exists()`
says yes to both, so passing the wrong one fails **silently**: `_wear_outfit()` instantiates
an entire Civilian — script, collision and movement — as the incident's body, and that body
then walks away under its own logic, leaving the incident with nothing to see.

It shipped twice, in `Suspect._draw_one_in()` and `Hazard._hurt_people()`, and was found
from play as *"the third person in a public disorder is invisible"* — third because a
disorder starts with two and the third is the first recruit. `Civilian.outfit_scene()` is
the answer, and asking the civilian beats mapping the paths by name because it stays right
if the two folders ever stop mirroring each other.

The check to copy for any future case is not "a body exists" but **"the body is one of
`Incident.OUTFITS`"** — under the bug a body existed, it was just the wrong kind of thing.
Sabotage also turned up a second-order effect worth knowing: a nested Civilian is a *live
unit*, so `_draw_one_in()` could find and recruit one, and the disorder cascaded faster
than its own table allowed.

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
| `Free` | 32 | firefighters | somebody pinned blocks everything else at that scene, including their own treatment |
| `Treat` / `Apprehend` | 30 | people | the person *is* the job: a casualty or a suspect beside a fire gets worked first |
| `Cool` | 28 | firefighters | a warming cylinder outranks the fire beside it — the fire will still be there in ten seconds |
| `Collect` | 25 | paramedics | a stable casualty means "run the stretcher" — see the casualty journey |
| `Escort` | 25 | officers | a detained suspect means "walk them to the car" — on foot since August 2026 |
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

### Fires have kinds

A fire used to be a fire, and the only thing that varied was whatever the Director set
on it at the call site: four call kinds each poking the same four fields inline. Which
meant the *character* of a fire lived in the Director, where you could not see it, and
adding a fifth kind meant a fifth block of field-setting.

`Fire.Kind` — `BIN`, `VEHICLE`, `BUILDING` — with one `KINDS` table holding the plume,
the rates, whether a hose is needed and the whole spread configuration. The Director
now sets one field.

| kind | plume | spreads | who can fight it |
| --- | --- | --- | --- |
| **Bin** | `FX_Fire_Small_01` | never — its threshold is put out of reach | anyone, quickly |
| **Vehicle** | `FX_Fire_Medium_01` | rarely, short range | anyone, slowly |
| **Building** | `FX_Fire_Large_01` | aggressively, crew-scaled | a hose only |

Two traps, both paid for:

- **`kind` needs a setter, not just an export.** `Director._spawn()` adds the incident
  to the tree and *then* configures it, so a value applied only in `_ready` is applied
  before the Director has said what it is. The setter re-applies when it is already in
  the tree.
- **The default matters.** Making `BUILDING` the export default reddened five existing
  checks at once, because everything already on the map inherited building rates. The
  default is `VEHICLE`, which carries the historical numbers the older checks were
  written against.

A spread fire inherits its parent's kind for free, because `_spread()` uses
`duplicate()` — which is right: a building fire spreads building fire.

### Different fires want different things put on them

A fire used to yield to anyone with a hose, and the only question was how fast. Now each
kind names the **agent** that touches it, and the wrong one does nothing at all — the
same refusal `needs_hose` already uses, because "slower" is invisible at RTS zoom and a
player who cannot tell refusal from slowness learns nothing from either.

| kind | class | agent | who has it |
| --- | --- | --- | --- |
| Bin | A | water | the appliance, or a carried extinguisher |
| Building | A | water, **and volume** — `needs_hose` | a crew on the appliance's hose |
| Vehicle | B (fuel) | **foam** | the appliance's second tank, only |
| Electrical | C | **dry powder** | **the patrol car, and nothing else** |

Two things make this a decision rather than a lookup.

**Foam is a separate finite tank, and a hydrant will not fill it.** Water is what the
street supplies; foam is what the station stocks. Park by a hydrant and a crew can fight
bins and buildings all day, but the fourth car fire of a shift sends the appliance home.
The tank is the existing `water` plumbing duplicated, not reinvented — `carries_foam`,
`draw_foam()`, `has_foam()`, and `_supply()` asks the tank the *fire* needs, so an
appliance out of foam is still a perfectly good supply for a building.

**The electrical fire inverts the roster.** Water on live electrics is worse than
useless and the appliance carries no powder, so it is the one call the fire service
cannot answer and the police can. Dry powder is genuinely multi-class, which is what
lets an officer keep every fire they always had while gaining one nobody else can take
— the change adds police work rather than quietly removing it. It is small and it does
not spread, because a call that inverts the roster should be a puzzle and not a
punishment.

`describe_state()` appends `-- needs foam` / `-- needs dry powder`, and the board already
renders that string on the call row, so the whole rule is discoverable for no interface
work at all. Without it this would be a memory test: a crew drives across the district,
finds the hose does nothing, and has no way to know why.

**All three look different, and that is not decoration.** Water is thin ribbon streaks
that fall (`WaterJet.tscn`, off the pack's rain material); foam is soft blobs that hang
and swell (`FoamJet.tscn`, off `Dust_Soft_01`); powder is a short wide sulphur-tinted
puff that snaps to full opacity and vanishes (`PowderJet.tscn`, off `Dust_01`). Three
scenes rather than one recoloured, because a rule the player cannot see is a rule they
have to be told.

Powder borrowed the water jet for its first day and that was a genuine defect, not a
missing polish: an officer fighting an **electrical** fire was drawn spraying water, on
the one call whose entire rule is that water is the wrong thing to put on it. A visual
that contradicts the mechanic is worse than no visual at all.

The related bug underneath it is worth keeping: the jet was handed **`fire.agent`** — what
the fire *wants* — when it should have been handed what the *unit is applying*. The two
coincide often enough to hide, and they part company exactly where it matters: an officer
on a bin fire carries dry powder whatever the bin would prefer. `_applied_agent()` is now
a separate question from `_can_apply()`, and only the latter is about the fire.

One trap worth recording. **`Kind.VEHICLE` is the default fire**, so making car fires
want foam broke four existing checks at once — all of them measuring the *water* economy
against a fire they had never named. The fix was to make those checks say which fire they
stage rather than to weaken the rule; a check that leans on a default is measuring
whichever row the table happens to hold.

### A car fire bills what is parked in it

A `VEHICLE` fire scorches any `Vehicle` within `scorch_range`, per second, scaled by
intensity, straight into the `repair_bill` the career economy already reads. Nothing new
was needed — `Vehicle.scorch()` accumulates fractional pounds and bills whole ones, and
the `took_damage` signal, the readout and the debrief row all existed.

It gives parking a consequence. Park the appliance nose-in beside a burning car and it
costs you about £13 for three seconds; stand it off and it costs nothing. The suite
pins both, and the second half matters as much as the first: a check that only asserts
damage happens cannot tell you the radius is doing anything.

### The water is visible

Until August 2026 a firefighter fought a fire by standing near it playing a clip. The
fire went down, so the mechanic worked; nothing said where the water was going.

`Game/Units/WaterJet.tscn` is a stream of ribbon droplets fired along local -Z with
enough gravity to droop. There is **no water in the particle pack** — what it has is
rain, which is short ribbon streaks on a vertex-coloured unshaded material, so the
material is the pack's `Rain_01` verbatim (vendor files are never edited) and the nozzle,
spread, velocity and gravity above it are ours.

`Person.spray_at(point)` is an **expiring ask**, the same shape as the appliance's
ladder: an order calls it every frame it delivers water and simply stops calling it when
it does not. Nothing has to remember to switch the jet off — which matters, because there
are four ways to stop working (finished, shoved out of range, cancelled, target freed)
and a latch would need releasing on all four. The jet is instanced lazily on first use
rather than shipped in each character scene: there are eleven of those, all generated,
and only a firefighter or an officer will ever want one.

A firefighter **holds the appliance's own nozzle** while working —
`SM_Veh_Firetruck_Hose_Nozzle`, already a part on the built engine, taken off the shelf.
Its position is read off the skeleton's `RightHand` bone each frame rather than hung on a
`BoneAttachment3D`, because an attachment would have to live *inside* the character
scene, and those eleven scenes are generated by `build_character.gd` — anything added
there is lost at the next rebuild. The water then leaves the muzzle, 0.52m down the
barrel, rather than the grip: otherwise the first half-metre of the stream is inside the
tool that is supposed to be producing it.

An officer gets no tool at all. **There is no fire extinguisher in any pack** — 516 props
and not one — and handing them the appliance's hose nozzle would say the wrong thing
about what a patrol car carries. Their water comes from the chest and the tool stays
implied, which is how the crew and the appliance themselves were handled before the Town
pack arrived.

Two details are load-bearing:

- **The jet is `top_level`.** Its particles are in world space, so if the nozzle
  inherited the person's transform, turning to face a second fire would swing the water
  already in the air round with them.
- **It is driven by water delivered, not by the order running.** Both call sites sit
  *below* their "no supply" early return. A firefighter with no appliance in reach still
  walks up and still plays the animation and still gets nowhere; an officer in front of a
  building fire likewise. Drawing a jet in either case would say water is landing when
  the whole point is that none is. The suite pins this from both sides — an officer on a
  building fire shows nothing, the *same* officer on a bin fire sprays — because a check
  that only asserts the absence cannot tell you the mechanism is connected at all.

### Hover, and a spacing scale with a name

Several things here stop the mouse and answer a click -- roster chips, call rows, dispatch
rows, the CONTROLS chip -- and every one of them used to look exactly like the things that
do not. `Game/UI/Hover.gd` brightens `modulate` on `mouse_entered` and restores it on exit.

**Brightness rather than a stylebox swap, deliberately.** Half of these are bare containers
with no panel at all -- a `UnitChip` is a `VBoxContainer` -- and giving one a stylebox
changes its size. A control in the bar that changes size makes the bar taller, and a taller
bar covers whatever floats above it. Six incidents deep, that is not a trade worth making
for a hover effect, and a check asserts the bar does not move when something is hovered.

The gaps are named in `Palette` -- `TIGHT SNUG STEP WIDE GAP` -- and the container defaults
in `build_theme.gd` come from them. **The twenty-four existing `separation` overrides are
untouched**, which is a deferral rather than an oversight: retuning a gap inside
`CommandBlock` rewraps the tiles, grows the bar, and re-opens the trap above. Even deleting
one that merely matches its default needs the container type read at each site. The
`HFlowContainer` h_separation keeps its own number and is commented as load-bearing
geometry, because it is what decides how many tiles fit a row.

### Group orders spread, and queued ones are drawn

Two things an RTS player notices in the first minute, both absent until August 2026.

**Ten units ordered to a point all went to the same coordinate.** `MoveAbility.make_order`
never saw the selection, so it could not do anything else. The seam is two fields on
`Target` — `slot_index` and `slot_count` — filled by the controller before the per-unit
loop and read only by `MoveAbility`. Every other ability ignores them, so the controller
still never branches on a verb, which is the property the scoring ladder exists to protect.

Slots are assigned **by navigation layer first** (vehicles path on the carriageway, people
on the pavement, so one formation for both would put a car on a kerb) and then
**nearest-first**, or eight units cross each other's paths on every order. The layout is a
spiral of rings, six to a ring — what a crowd naturally takes around a thing they are all
going to.

A slot is checked twice: `CityGrid.standable()` first because it is cheap, then
`Unit.can_reach()`, which is `map_get_path` **with the unit's own navigation layers**.
That second test exists because `map_get_closest_point` takes no layer filter and both
regions share one map — it answers "0.00m" for a spot in the middle of a pavement when
asked about a car, and it has already produced one completely vacuous check here. A slot
that fails either test falls back to the ordered point: stacking two units is much better
than putting one inside a building, and a group order that silently dropped a unit would
be worse than both.

**A lone unit always gets the raw point**, which is why the terminal-approach figures the
docs treat as a regression tripwire did not move by a byte: 4.2m off the centre line,
stopping 13.0m clear of the building it was aimed into, before and after.

**Queued orders now have markers.** Shift-right-click has queued since phase 1 and nothing
ever drew it, so a player who lined up three stops could not see what they had asked for —
or notice they had queued one by accident. `_update_markers()` walks `unit.orders` rather
than `current_order()`; the current one keeps the bob and the spin at full size, the rest
sit still at 0.55. Told apart by size rather than colour because the marker is a duplicated
scene, and recolouring one would mean its own material per copy.

### Your own people can be lost

Until August 2026 nothing in the district could touch a unit the player had paid for.
Damage existed only on `Vehicle`, and the blast that turned bystanders into casualties
walked straight past the firefighter standing in it. Every scene was safe to walk into,
which removes the one decision the genre is built on.

A `Person` now has `health` and one entry point, `hurt()`, shaped like `Vehicle.scorch()`.
At zero they go down: hidden, unselectable, and a `Casualty` is filed where they fell —
carrying a back-reference and **wearing their own kit**. The whole medical chain then
works unchanged: treat, stretcher, ambulance, hospital. Reaching hospital puts them back
on the forecourt whole; not reaching it calls `Station.write_off()`, which is the only
thing in the game that makes `owned` go **down**.

**The downed person stays in the tree**, and that is the load-bearing decision.
`Station._alive()` counts group membership, so a unit lying in the street still counts
against `available()` — the player cannot dispatch a replacement for them. Freeing the
person and spawning a bare casualty would have made being blown up *refund* a unit.

Three guards in `hurt()`, each paid for:

- **The crowd is not crew.** `Civilian extends Person`, so any `as Person` cast catches
  shoppers. `Hazard._hurt_people()` tests `Civilian` **first**, and `hurt()` no-ops for
  `Service.NONE` — otherwise a blast both converts a bystander and down-states them.
- **A passenger is not standing there.** An aboard person rides at the carrier's
  position, so without the `is_aboard` guard a blast beside the appliance took the crew
  sitting safely inside it — measured at 0.17 health under sabotage.
- **Already down cannot be hurt again**, or one blast files two casualties.

A crew casualty scores **neither** arm: delivering a firefighter you got hurt should not
pay £100 for the privilege, and losing one should not be fined on top of losing the asset.
The punishment is the write-off, and the debrief names it. Same argument the hazard arm
makes about not charging twice for one mistake.

One ordering bug worth keeping. `Mission` read `casualty.crew` from the `resolved`
handler and always saw null — settling clears it, and a written-off unit is freed, so
there was either nothing or a dangling reference. `was_crew` is latched in `_finish()`
before either happens.

Two sources of harm ship: the hazard blast (`blast_harm 1.2`, scaled by the same falloff
as the damage — at 0.85 the strongest possible hit left a firefighter standing on 0.22,
so a cylinder in the face was survivable every time), and a resisting suspect, who costs
the arresting officer condition per second. The second makes a lone arrest expensive
rather than lethal, and turns "send two, or cordon first" into a decision.

**Deferred deliberately:** standing near a big fire. `ExtinguishOrder` *holds* a
firefighter at its work range, so a burn radius that overlaps it makes the fire service
unplayable — and that would read as a balance bug rather than a feature. Measure the
settled stand-off distance first, and cut the source if the two overlap.

### An arrest is walked in, not teleported

A patrol car used to drive to a cuffed suspect and they appeared inside it. Two things
were wrong with that, and they are the same two the paramedic's stretcher run fixed years
of phases earlier.

**The car had to reach them.** A car only goes where the carriageway goes, so the pick-up
reach was stretched to 5.5m purely to bridge the kerb — and that only worked because the
director opens crime calls against a kerb *on purpose*. Anybody standing further off the
road than that was uncollectable. Escort now belongs to the **officer**: feet go where
wheels cannot, and the big wheels wait at the kerb.

**And the loading was a teleport.** `LoadSuspectOrder` is now four beats — walk to them,
take hold, walk them back, hand them over — with the suspect following a metre behind,
visible and unpickable, the same arrangement `Casualty.is_carried` uses on a stretcher.

The guard in `Stage.HANDOVER` is the load-bearing part and it exists because of a
sabotage result: deleting `walk_with()` outright left **every loading check green**,
because the handover put the suspect in the car from wherever they happened to be
standing. The walk was decorative and the teleport was still there under a longer
animation. Handover now refuses unless `suspect.escorted_by == unit`, and the same
sabotage reddens four checks instead of one.

A patrol car holds **two**. One was the shipped figure, and it made a second arrest at the
same scene need a second car — which the disorder call turned from an occasional nuisance
into the normal case, since that one produces three or more suspects at a single kerb by
design.

A detained suspect now **stands where they are**. They used to trudge back to the spot the
call opened on, because that kerb was where the car's reach was measured from; nothing
needs them at a particular place any more, and walking off would mean an officer sent to
collect somebody arrives to find them somewhere else.

### A crowd that turns

A `Suspect` can **recruit**. Left alone, one draws in the nearest bystander every
`recruit_interval` — taking the person who was standing there and the clothes they were
wearing, the same thing a blast does to a civilian and for the same reason. Off by
default, so the ordinary Disturbance is still the single mouthy individual it always was;
only the `disorder` call turns it on.

This is **the one call that gets worse for want of units rather than for want of time**.
A fire spreads on its own schedule whatever you do. A disorder call spreads only while
nobody is standing in it, so arriving *is* the intervention, and arriving late costs you
the size of the job rather than a few seconds of it.

**And it is the first job `Secure` has ever had.** Containment is an officer on foot
within `police_reach`, *or* a raised `Cordon` over the spot. Until now nothing in the game
required a ring of cones — NEXT.md carried "nothing yet requires a cordon" as a standing
gap — and a verb that never matters is a verb the player correctly ignores. A patrol car
parked at the scene does not count: it takes an officer out of it, which keeps the call
about the roster rather than the fleet.

Containment **resets** the countdown rather than pausing it, so a scene left half-attended
cannot be picked up exactly where it was.

`Director.DISORDER_SIZE` scales the starting group and the cap to the officers owned —
`BUILDING_SIZE`'s rule again: the job fits whoever can be sent rather than being withheld
until the roster is big enough. That was tried on building fires, it was miserable, and a
one-officer career never seeing the interesting police call would be the same mistake in a
different uniform.

### Pinned under something

A `Casualty` can be **trapped**. They can be treated where they lie — a paramedic kneels
beside them either way — but nothing can move them until a fire crew lifts the weight off.

This is the first call in the game that needs two services **in sequence** rather than in
parallel. A rescue wants an engine and an ambulance at the same time; this wants the crew
to have *finished* before the paramedic can start, so arriving in the wrong order costs
real time instead of being a matter of taste. A paramedic who gets there first still has
something useful to do — treating stabilises them, and a stable casualty stops declining —
which is what keeps the wait from being dead time.

`Free` (`T`) is the verb, and it is the odd one in the game: it heals nobody and puts
nothing out. A firefighter cuts the casualty loose and then has no further part in the
call. Fire service only — a paramedic who could free people would collapse the whole
thing back into one unit.

Three details worth keeping:

- **`CollectAbility` declines rather than scoring low.** A paramedic right-clicking a
  trapped casualty gets a **Move** and walks to them, which is the right thing to be
  doing while the crew work — instead of standing over them running an order that cannot
  finish.
- **The load is a real prop**, `SM_Prop_Pallet_01` — and it was chosen for its **origin**
  rather than its look. The first cut used a four-metre pipe, laid flat by a quarter turn
  about X (the trick the held nozzle uses); but that mesh runs from its origin along +Y
  with its AABB centre 2m out, so the whole length ended up beside the casualty with one
  end resting on their shins. The pallet's mesh is centred on its origin, so it needs no
  rotation and no offset: dropped at the body, it covers the body.

  The check is the part worth keeping. It asserted only that a `Pin` node existed, which
  a prop lying *next to* someone satisfies perfectly well — that is how the bug shipped.
  It now transforms the mesh's AABB centre into world space and requires it within 0.6m
  of the casualty: **0.00m** with the pallet, **2.00m** with the pipe restored.
- **`describe_state()` says "trapped" first**, ahead of every other description including
  "stable". Trapped is what stands between the call and its next step, and a board that
  read "stable, needs an ambulance" over someone nobody can lift would send the player
  for the wrong unit.

The director opens these at weight 12 with `needs_fire_service`, and starts them
declining at 0.6 of the usual rate — they are losing health the whole time they are
pinned and nobody is treating them, so the sequencing the call exists to create would
otherwise just be a way to lose people.

### A cylinder that goes off

`Hazard` gains `heat` while any active `Fire` is within `heat_range`, scaled by that
fire's intensity so a fire being knocked down stops threatening it before it is out. It
sheds heat on its own when nothing is burning near it — slowly, so walking away from a
warm cylinder is not a plan, but not never, so putting the fire out first is a real
answer and not merely a way of freezing the problem.

At `heat >= 1.0` it goes: everything nearby takes damage falling off with distance,
every civilian in range becomes a `Casualty` **wearing the clothes they were already
wearing**, one or two new fires are thrown through the same `CityGrid.standable` test a
spread uses, and a flash and dust cloud are freed on a timer. Then `_finish(false)` —
an explosion is a job that was not done.

There is no explosion in any pack on disk, so the blast is composed: the largest fire FX
the particle pack ships, its dust, and a synthesised bang.

**Beaten two ways**, which is what makes it a decision rather than a timer. Cool it with
a hose — a firefighter standing still, doing nothing about the fire — or put the fire out
first and let it cool itself. Both are right in different scenes.

The hose is the new verb, `Cool` (`L`), scoring **28**: above Extinguish's 20, so a
firefighter standing between a fire and a warming cylinder deals with the cylinder,
which is the right default — the fire will still be there in ten seconds and the
cylinder may not be. Below Treat and Apprehend at 30. Folding it into Extinguish was
cheaper and was considered; a separate tile was chosen because "put this out" and "stop
this exploding" are different decisions and the player should be able to see the choice.

Two ordering traps here, both found by a check rather than by play:

- **The blast is tested before anything is allowed to take heat off.** The first cut
  cooled first and tested second, so a cylinder sitting at exactly 1.0 shed a fraction
  and survived. In play the two happen in the same frame and it never showed.
- **The hazard is freed by the time you read the result.** `_finish()` calls
  `queue_free()`, so a test that reads `hazard.active` after the blast raises a runtime
  error — which in this suite does not fail a check, it silently abandons the rest of
  it. Four checks vanished and the run still said green. Take the outcome off the
  `resolved` signal instead.

### A bus on its side — the RTC at triage size

`bus_rtc` is the two-body road traffic collision grown to the size where dispatch order
becomes the game: a Town-pack bus (or school bus) lying along one of the junction's own
streets, and three to five casualties fanned across the carriageway around it. The
count comes from `Director.BUS_SIZE`, keyed on the medical hands the career owns
(ambulances plus paramedics) in the `DISORDER_SIZE` mould — the job fits whoever can be
sent. Every casualty declines at the trapped call's gentled 0.6× rate, because the
point is *triage pressure*: an ambulance carries two stretchers, so five patients is at
least three hospital runs and a standing question about who rides first — not a race to
save anyone at all.

Two traps are load-bearing here. The five body spots all sit within a few metres of the
junction centre because `Call.GROUPING_RADIUS` (14m) is measured against a centroid
that moves as each casualty is adopted — spread them wider and the board splits one
scene into two calls. And the wreck is freed by a lambda on each casualty's
`tree_exited` that **scans a captured Array** for anyone still in the tree — a captured
int counter would be a copy (GDScript captures ints by value), and the bus would either
leave early or never.

### A shed load, and the street it shuts

`shed_load` is the one call whose patient is the road: a delivery truck at the kerb,
cardboard boxes strewn mid-lane (a `Debris` incident), and the street genuinely shut
until somebody shifts them. Nothing is burning and nobody is hurt — on the board it
deliberately reads with the fire palette via the same `_recentre` arm the gas cylinder
uses, because a shut street is a scene hazard and a cross would send the wrong service.

Shutting a street honestly takes three mechanisms, because three different consumers
need telling:

- a **raised `Cordon` child** (raised directly, never via `raise_cordon()` — that would
  cone the scene, and the boxes are the visual) turns the ambient traffic back;
- a **solid `Blocker`** body on layer 1 — the one deliberate exception to the
  strip-collision rule — actually stalls a vehicle that drives at it, because both
  consumers of `road_is_blocked` only fire on a stalled vehicle;
- a **debris scan in `Vehicle.road_is_blocked`** lets the stalled vehicle's own
  machinery see the pile, which is what unlocks the street write-off, the reroute and
  the pavement mount that already existed for walls of traffic.

The verb is `Clear` (`J`), a `WorkOrder` in the Free mould, and unusually it belongs to
**two services** — officers and firefighters both — because box-lugging is not
specialist work. Its `REACH` of 3.6 is load-bearing: the Blocker's face is 2.75m from
the debris origin and a person's capsule holds them ~0.3m off that, so the first cut's
2.6 left the officer pushing the boxes forever. Clearing scores `DEBRIS_POINTS` (60) on
the cylinder's reasoning: a disaster prevented, not a job finished.

### The wreck outlives its casualties

Every other incident ends when the last body leaves. A road collision did too: the car was
a script-free prop stripped of collision, drawn for the look of it, and freed with the
call. So an RTC had no **tail** — the moment the second casualty was aboard the ambulance,
the crossroads was a crossroads again.

`Wreck` (`Game/Incidents/Wreck.gd`) is the first incident that is still there once nobody
is hurt. It is modelled on `Debris`: its own group, an amber marker, a `Blocker`
`StaticBody3D` on the world layer that traffic and pedestrians route around, and a
`cleared` float that only the winch moves. `clear_per_second` is 0.1, so a recovery truck
takes ten seconds on station; the street reopens when the wreck goes.

**Three separate ways this shipped broken, all the same mistake.** Each time the check
reached past the interface and vouched for nothing:

- The first check called `wreck.clear(1.0)` directly, so it proved the float counts up and
  nothing about whether a truck can reach one.
- `WorkOrder` drove the truck at the wreck's *centre*, which is inside the blocker: it
  wedged against the car it had come for and never arrived. `VEHICLE_STANDOFF` (3.4m)
  aims it at a point out along the vector it approached from instead.
- The truck did not carry `ClearAbility` at all. `can_tow` gated whether the ability
  *would score*, but nothing put it in the unit's list, so a right-click on a wreck
  resolved to Move — drive over, stop, lift nothing. Every check had built a
  `ClearAbility.new()` by hand and so could not see it.

`ClearOrder.VEHICLE_REACH` is 8.0 against the 3.6 a person works at, and it is **measured
where the truck actually comes to rest** rather than derived from the standoff plus the
blocker — the arithmetic answer was optimistic by enough to leave it winching thin air.

### The collapse nobody can diagnose

`drunk` is the call the board cannot tell you the truth about, because nobody at the
scene knows it either. Somebody is flat out on the pavement with a bottle beside them
(a civilian taken where possible, in their own clothes), the row says "Person
collapsed, drink suspected", and the readout commits to nothing: "unresponsive — cause
unknown". The truth — `Casualty.turns_rowdy`, rolled 50/50 on the director's seeded RNG
at spawn — stays hidden until a paramedic's treatment crosses `ASSESS_AT` (0.4).

Half the time it is exactly what it looks like and carries on as an ordinary medical
call. The other half, the patient **stands up swinging**: a `Suspect` in the casualty's
own outfit appears where they lay, the casualty retires *silently* — no `resolved`
emission in either polarity, because failure fails the whole call and success pays £100
for a patient nobody delivered — and the same call flips MEDICAL → CRIME on the board
(kind is re-derived when `_prune` drops the departed casualty). The swap's ordering is
the load-bearing part: suspect in the call's list first, casualty out second, or the
list empties and the call closes RESOLVED for a job nobody did. It is the first call
dispatched on genuinely incomplete information — sending a paramedic *and* an officer
is insurance, and the assessment is what the paramedic's first seconds buy.

### The missing child — a marker that admits what it does not know

`missing_child` is the first call the player *searches*. The board's marker stands on
a `MissingChild` anchor — a parent at the place the child was last seen, police-blue
ring, flavour "Child reported missing" — and never moves. The child themselves is a
`ChildWanderer`, spawned by the director 45–90m away and strolling the pedestrian
graph tethered to a 32m roam radius, wearing **no marker of any kind**: being a
`Civilian` subclass makes them unselectable, invisible to the picking ray and absent
from every board and minimap by construction. The find is physical — the anchor scans
four times a second for any *person* with a service within 6m of the child (vehicles
deliberately do not count; driving past is not finding anyone).

**Found is the middle of the job.** The child cannot be clicked, so the escort is not
an order: they attach to whoever found them and walk at heel (`follow()`, re-aimed a
few times a second). Brought within 4.5m of a **police** vehicle — the reach bridges
kerb-to-lane like the suspect escort's — they climb in (`ride()`: hidden, inert,
cosmetic seat, no cell bookkeeping because a child is not a prisoner; an ambulance is
refused). The call closes only when that car pulls up within 10m of the parent:
search, walk them to the car, drive them home — three beats on the call row's bar
(0.4 found, 0.7 aboard), and only the reunion pays `MISSING_POINTS` (90).

Two structural decisions carry the design. The child is **not an Incident** — if they
were, `Call._recentre()` would average them into the call's position and the marker
would chase the answer it is supposed to not know. And the child is excluded by class
from all three systems that consume civilians (`Director._pick_civilian`,
`Suspect._draw_one_in`, `Hazard._hurt_people`): any of them taking the child frees the
body the report is scanning for, upon which the report retires silently — the
drunk-call rule, so a vanished child closes the call without banking a find nobody
made. There is no failure arm in the scoring: in this game a missing child is never
*lost*, only still missing when the clock runs out, which the failed call already
counts.

No child-sized mesh exists in any pack — Synty's "SchoolBoy" is a school uniform on
the standard 1.84m adult rig — so Child.tscn scales an ordinary outfit to 0.7. At RTS
distance, small is young.

### Spawning a call on demand — F5

The director rolls from a weighted table, so seeing a particular call means opening a
shift and waiting: `trapped` is 12 of about 166 weight, roughly one call in fourteen.
Four kinds shipped in August 2026 that were never once looked at during the work that
added them, and everything a check cannot judge about them — whether a blast reads,
whether foam looks unlike water, whether a pinned casualty is legible at RTS zoom — can
only be settled by looking.

`CallSpawner` lists every row of `Director.KINDS` and opens the one you click. Three
things about it are deliberate:

- **It asks the director rather than placing anything.** `Director.open_kind()` was split
  out of `_open_call()` for this, so a spawned call runs the same `_clear()` and
  `_pick_pavement()` guards a rolled one does. Those are the single funnel enforcing that
  nothing ever opens inside a property, and a spawner with its own placement could put a
  fire in a wall and look like a bug in the game rather than in the tool.
- **The list is built from the director's own table**, so a call kind added there appears
  here without anyone remembering to list it twice. A check pins the count.
- **It is inert until F5 is pressed** — nothing is built, watched or spawned before that.
  The map ships quiet by design and a director that could start on its own breaks dozens
  of checks at once. A check pins that too, and it is not theoretical: sabotaging the
  spawner to build its panel in `_ready` put the panel on screen from frame one, where it
  swallowed clicks and made the map-click checks miss by 84.9m.

The panel also carries a **PREVIEW WEATHER strip** — CLEAR / RAIN / FOG / SNOW — on the
same argument as the calls: a rolled SHIFT'S OWN sky is one draw in four-ish, and snow
at dusk can only be judged by looking. It drives `Daylight.set_weather()` directly and
deliberately does **not** touch the settings card's stored choice: it is a preview, not
a setting, and a dev tool that silently rewrote what the player chose would be worse
than no tool. The strip's buttons reflect whatever the sky is actually doing.

Third of the same shape as `F3` (force a black-box record) and `F4` (navigation overlay).

## The tutorial town

A second playable scene, reached from a **TUTORIAL** button on the title card: the
user's hand-authored Synty town (`Assets/PolygonTown/Scenes/Tutorial.tscn`, treated
as **read-only input** — the vendor-dir rule) wrapped by a processor-emitted shell at
`Game/Tutorial.tscn`. Rebuild with `godot --headless --path . --script
res://Game/build_tutorial.gd` whenever the town's **roads or pavements** change (the
navmeshes are baked at build time); prop and building edits need no re-run, because
the shell *instances* the vendor scene rather than copying it.

**The click costs about 819ms, and a pre-warm that claimed to remove it did not
work.** Almost all of that is parsing the vendor town's 2.4MB of text `.tscn`. A
`ResourceLoader.load_threaded_request` was added to do it on a worker while the title
was up; threaded, that file comes back a **parse error every time** — at boot, delayed,
with the type named, in either scene — while the same path loads perfectly
synchronously. The 819ms → 0ms measurement that seemed to prove it was a resource-cache
hit in a probe, and the check guarding it asserted only that a request had been *made*.
Both are gone. It hid because nothing reads stderr on a normal run; making the menu its
own boot scene put the errors at the top of a clean console.

The town could instead be re-saved binary and read twenty times quicker, and
deliberately is not: the shell *instances* the vendor scene, which is exactly what lets
the town be edited and played with no processor re-run.

The architecture is three pieces:

- **`build_tutorial.gd`** stamps road/pavement collision layers by prefab family
  (`TutorialMap`'s classifier), bakes the two navmeshes with the district's own
  parameters, and assembles the system nodes around the instanced town — Station on
  the user's spawn point (10, 0.45, −3) at 270°, single dispatch slot, its **own
  career file** (`user://tutorial-career.cfg`, reset on every entry — practice never
  touches the district's books); the Hospital pad co-located with the spawn by
  design; no Traffic, Crowd, Director or CallSpawner (all lattice-native).
- **`TutorialMap.gd`** ("TutorialSetup", deliberately the scene's first child) flips
  `CityGrid.lattice_fits` off in `_enter_tree` and back on in `_exit_tree` — the
  tables describe the generated district, and on this map every answer would be a
  confident lie, so eight guard sites (lane routing, street write-offs, the
  turn-planner's road test, kerb mounts, slot validation, addresses) fall back to
  the navmesh and physics while it is false. Deleting the restore reddens fourteen
  district checks at once — measured; that is how load-bearing the one line is. It
  also re-stamps the collision layers `pack()` deliberately dropped, and swaps the
  minimap to its schematic street plan (the baked photograph is the district).
- **`TutorialDirector.gd`** is the whole script, and it opens **a job at a time**:
  on the first PLAY a collapsed person, and only once that is dealt with does the
  bin fire come in. Both at once was the first cut and taught nothing — a player
  still learning to select a unit had two markers, two services, and a fire growing
  while they read the first row. Staging needs one thing from elsewhere:
  `Mission.more_to_come`, because the scripted win rule declares victory on a clear
  map and a staged shout is briefly clear between its stages. Clearing the last one
  drives the same path to the SHOUT COMPLETE card; `begin_shift` is never called.

  The two spots are 74m apart in different parts of town — they were 60m apart on one
  street until August 2026, which read as the same incident twice. Both came from a
  reachability sweep of the baked meshes, and the sweep has a trap in it: **both
  navmeshes share the world's default navigation map**, told apart by
  `navigation_layers` rather than by map, so `map_get_closest_point` answers off the
  *union* of the two and every pavement point reports as being on the road as well.
  `region_get_closest_point` is the call that can tell a kerb from a carriageway.

### The tutorial points at what it is talking about

Naming a unit in a prompt is thin help when the storefront holds eight cards. A
`Spotlight` node pulses whichever control the current prompt means: the cart button
while anything is unbought, the two named cards once the shop is open, the roster's
standby chips once they are bought and still parked. Nothing glows during the parts of
the lesson that are about the world — a glowing panel would be pointing the wrong way at
"right-click the casualty".

**The words and the glow are one reading.** `TutorialDirector._lesson()` works out what
is missing once and records it in `_to_buy` / `_to_send`; the prompt and the spotlight
are two renderings of that single answer. Working it out twice is how a tutorial ends up
saying "buy an ambulance" while pointing at the fire engine — and the checks are written
to catch precisely that: swapping the spotlight's two branches leaves both prompt-text
checks green and reddens only the three that assert *which* control is lit.

`Spotlight` writes `modulate` every frame, which is the same property `Hover` uses, so a
spotlit control outranks a hovered one while the glow is on it. Releasing restores 1.0
rather than whatever Hover last set; if the pointer is resting on the control as the step
completes, Hover puts its own lift back on the next `mouse_entered`.

**The gardens walk, and the town is inhabited.** The person mesh covers pavements
*and* open ground, so a walker crosses lawns and slips through the gaps between
houses — but not through the living rooms. That rule is one geometric test in
`TutorialMap.stamp`: a lawn tile with a pavement, a road or a building on top of it
is scenery rather than ground. It exists because this town tiles grass **under
everything**, and the two naive readings both failed measurably — parse the grass
as-is and two walkable surfaces stack in every cell until the navigation *map*
reports more than two edges per rasterisation cell and answers every query with
nothing; drop the grass outright and a walker is confined to the pavements. Sinking
the lawns 20cm was tried too and does not help: the map's height cells are 25cm and
both surfaces still land in one. Note also that Recast has no notion of an
*obstacle* — feeding it the houses so they would carve the mesh simply baked their
roofs as walkable, 34,236 polygons of them. Where a walker may not go is decided by
what ground is baked, exactly as in the district.

**The kerbs carve the drivable mesh, and that is the driving fix.** The town's
pavement slabs are 16.5cm kerbs that overlap the road tiles at every corner, so a
vehicle mesh baked from roads alone claimed ground a kerb face was standing in. Play
caught it before any check did: four black-box records in one session, an ambulance
at full throttle and zero speed jammed against a sidewalk corner, fifteen metres
short of the forecourt, escaping and re-approaching for ever. The vehicle bake now
parses the pavements with the kerbs **lifted half a metre** — 8.5cm of real
proudness is invisible under a 25cm rasterisation cell, so the real kerb alone does
not carve anything — and the person bake runs immediately after with them back down,
because a walker steps over a kerb rather than driving into it. Measured on the
route that failed: never arrived, twelve escapes, 27% of frames going nowhere →
**12s, no escapes, 1%**. Flat road furniture (manholes, drains, speed bumps) is made
non-solid by the same stamp, after one sat exactly where the tutorial's casualty lay
and an ambulance ground against a drain cover for forty seconds.

**…and then the lifted pavements are thrown away, which is the other half.** The
carve leaves the raised tops in the mesh, and they were written off as "islands no
car on the road can reach — the same harmless shape as a roof". They are not. A
kerbside shout parks the ambulance beside one; it snaps onto it; and its route home
is on the other sheet. That is six black-box records of a car shuffling as it *left*
a shout — the last of them saying `reachable: false` while sat on a road collider
with nothing within 14m. Measured afterwards: **four components, two of them
map-spanning and interleaved**, 457 of 685 sampled drivable points unable to reach
the station. `build_tutorial._drop_lifted()` now discards every polygon whose mean
height sits above the carriageway datum plus half the lift, taking the mesh from 695
polygons to **117 in one component**. The datum is read off the baked mesh rather
than assumed — this town's ground is at y≈0.45, not 0, and a hardcoded floor threw
the entire carriageway away on the first attempt.

Two checks guard the pair, and they are not the same check twice: a **two-sided**
polygon bound (80..200 — the old `> 600` was pinning the broken mesh, and a bound
that can only grow is not a measure of a road network), and a sweep asserting every
drivable point can reach the station. Cutting the two polygons that bridge the
station to the town reddens the second alone while the first stays green at 115.
Worth knowing what did *not* catch it: the tutorial's real drive-home check stayed
green through the whole fault, because a forty-second drive does not happen to start
where the strand is.

**The teaching line reads the world rather than scripting it.** `TutorialDirector`
borrows the HUD's own mid-screen line — free here, since the district's hint needs a
Director this town does not have — and every prompt is a *state* the player is in,
not a step they have been counted through: buy the units, send them out, treat,
carry, wheel, drive home, then the fire half. A player who buys the engine early or
treats before the ambulance has parked is never told to undo it, and one who
restarts mid-lesson picks up where the town actually is. It says nothing before the
shift starts (the title card is talking) and nothing once the shout is complete (the
banner is).

Two dozen civilians are put down at load from the **person mesh's own vertices** —
the one description of this town that cannot drift from it — and they stroll by
mesh as well: `Civilian` gains off-lattice branches for strolling, fleeing and
gawping that use `map_get_path` where the district's crowd uses `walk_moves`.

Three traps the build measured, kept here because each looked like something else:
the navigation map ingests regions **asynchronously (~30 frames)** and answers
half-synced queries confidently; the town's **5m-wide streets** need a 1.0 vehicle
agent radius where the district's 10m streets take 1.5; and **driveways and lawns
must not be road/pavement** — driveways bake as marooned two-polygon islands severed
by the sidewalk they cross, and the town's blanket of grass under every pavement
gave the person mesh degenerate coplanar edges the server refused to answer queries
on. Lawns are unwalkable in the tutorial; nothing in its content stands on one.

## Sound

The four **world** sounds are **synthesised**, not recorded — `build_audio.gd` writes
16-bit mono WAVs sample by sample, because the project owned no sound library and
buying one was not the point. They are placeholders a real recording can replace
file-for-file. The interface sounds and the music bed are not synthesised; they are
CC0 assets, and `Game/Audio/CREDITS.txt` says which and from where.

| Sound | Where it lives | Driven by |
| --- | --- | --- |
| Siren | `AudioStreamPlayer3D` on the vehicle | the `K` toggle |
| Engine | `AudioStreamPlayer3D` on the vehicle | road speed, as pitch and level |
| Crackle | `AudioStreamPlayer3D` on the fire | its intensity |
| Radio chirp | `Soundscape` (non-positional) | `CallBoard.call_opened` |
| City bed | `Soundscape` (non-positional) | nothing; it just plays |
| Ambient bed | `Soundscape`, on the Music bus | nothing; it just plays, in the game only |
| Click / rollover | `ClickSounds`, on the UI bus | any button pressed, any control crossed |

### Three buses, made in code

`AudioBuses.ensure()` adds **Music** and **UI** beside Master, both routed through it,
so the settings card's master slider still means "the whole game" and the new music
slider is *balance* rather than level. They are created in code rather than shipped as
a `default_bus_layout.tres` for the same reason everything else here is generated: a
`.tres` is a resource nobody can diff, and `ensure()` is idempotent so any scene can
call it without owning it.

### The interface finds its own controls

`ClickSounds` is a passive watcher on `SceneTree.node_added`, not a `Click.attach()`
helper. Interactive controls are built in nine files and several are built at runtime —
roster chips, command tiles, call rows, shop cards — so a call-site rule would have been
missed at the tenth site, and silently. What counts as interactive is narrow on purpose:
a `Button`, or a `Control` that stops the mouse **and** has something connected to
`gui_input`. That second clause is what keeps the click off panels that stop the mouse
only so a click cannot fall through to the world.

The rollover is rate-limited to one per 60ms, which is less about taste than about the
roster: it rebuilds whenever the fleet changes, and a chip re-entering under a
stationary pointer would otherwise tick every time.

### The music is the district's, not the title's

`Soundscape` lives in `HUD.tscn`, and the main menu deliberately has no HUD — so "plays
in the game and not over the menu" needed no condition anywhere. The menu has the
backdrop's own city for atmosphere.

**Why the bed is a mono WAV and not an OGG.** `Soundscape._player()` casts what it loads
to `AudioStreamWAV` — which is also why an OGG dropped into that folder produces silence
rather than an error — and `AudioStreamWAV` is the only format whose loop points this
code sets sample-exactly. An MP3 carries the encoder's padding as an audible gap at the
loop, which on a three-minute bed you would hear every time round. The published track is
a 320kbps stereo MP3; it is converted to 16-bit mono at 22050 Hz, because stereo at that
length was a 16 MB file. `ClickSounds` has its own loader that does *not* cast, so the
UI sounds stay as the OGG they shipped as.

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

**A record says where things are, not just how far.** Each nearby unit carries a bearing
off the car's nose (`90° left`, `dead ahead`, `behind`), and every record ends with a
`touching:` line built from `get_slide_collision_count()`. Both were added in August 2026
after three stalls that read *"on a road, full throttle, zero speed, nothing in front"*
and could not be told apart — a car wedged against a vehicle, one wedged against scenery,
and one whose trouble was entirely its own steering all produce that same block, because
`holding behind` only ever names a vehicle in the *forward cone*. Range without bearing
cannot be reconstructed into a geometry, so none of the three could be staged from.

The record also separates **`turning round:`** from **`escaping:`**, because a car reverses
under two unrelated mechanisms and `is_turning_round()` only ever reported one of them.
Four records read `turning round: false` while the car was doing -5 m/s under a stuck
escape, which reads as "no recovery is firing" when it was firing repeatedly and not
helping — opposite conclusions wanting opposite fixes.

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

It is one tile because the command bar held exactly **seven** before the
`PanelContainer` grew and silently swallowed the CONTROLS chip above it. An eighth took it
from 148px to 176px. That trap has now caught this project six times; adding a command
tile is never free. The bar is **two rows** as of August 2026 and the chip sits above
that height — see "The interface" for what finally stopped it recurring.

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
| Gas leak (10) | A kerb | A firefighter on a hose — a cylinder with a bin fire beside it, cooking |
| Electrical fire (12) | A pavement tile | **The police, and only the police** — the appliance carries no dry powder |
| Person trapped (12) | A kerbside pavement tile | A crew to cut them free, **then** a paramedic and an ambulance — in that order |
| Public disorder (12) | A kerb | Officers *standing in it*, or a cordon — it grows while nobody is |

A medical call **takes a civilian** when the crowd can supply one: the director swaps
a shopper for a casualty where they stand (`_spawn_medical`), so the collapse is
somebody who was just there — the crowd is one lighter for the rest of the session —
and only falls back to a bare pavement tile when nobody qualifies. A vehicle fire is
a `Fire` with a script-free car prefab as a child, parked `KERB_OFFSET` off the
centre line of a street leg; that one is decoration and goes when the fire does. A
collision's wreck is not — see "The wreck outlives its casualties".

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

A gas leak is a cylinder and a small fire placed four metres apart — close enough to be
cooking it, far enough that a crew can work either without standing in the other. It is
the one call with a **deadline you can see coming**: the board reads "warming", then
"venting", then "about to go", and the bar on the row drains toward the blast rather
than filling toward a finish. Two answers work — hose the cylinder, or put the fire out
and let it cool itself — and choosing is the call.

**Scoring is where calls become authoritative.** The mission's tallies: 50 a fire out,
100 a casualty delivered, 75 an arrest booked in, 60 a hazard made safe, −150 a casualty
lost — a loss costs points, not the shift. A cylinder that goes off needs no explicit
penalty: it fails its call, injures whoever was near it and lights fresh fires, all of
which the existing table already costs. On top, each call cleared pays a response bonus off
`Call.response_age` (the age at which its status first turned `ON_SCENE`): the full
100 inside a 10-second grace, sliding linearly to a floor of 25%. Fast attendance is
worth more than the fire it puts out, which is the game telling you what it is about.

The shift is `shift_length` (300s) of new calls, ending when the board is clear: time
running out with a job open means finishing the job. The status strip shows the score
and time remaining; the debrief card shows the score, calls cleared and failed,
delivered and lost — and arrests, when there were any. `F2` after a debrief starts the
next shift.

## Campaign scenarios

The freeplay director produces *rolled* shifts. A scenario is the other thing — a
shift somebody wrote down. Three of them, on a **SCENARIOS** card off the title:
SATURDAY NIGHT (police, par 3:00), RING ROAD PILE-UP (medical, 4:00) and WAREHOUSE
ALIGHT (both services, 5:00).

They are deliberately thin, because everything underneath already existed:

- **`Scenarios.gd`** is data — `{id, name, brief, par, requires, waves}`, each wave a
  time and a list of call kinds. Adding one is adding a dictionary.
- **`Director.open_kind()`** already knows how to place all sixteen call kinds
  sensibly on the district, so no scenario has to know where a junction is.
- **`ScenarioDirector.gd`** is the order and the clock: it opens each wave when the
  timeline reaches it and holds `Mission.more_to_come` until the last one is out —
  the same flag the tutorial's staged shout needed, because the scripted win rule
  reads a clear map as a job done and a staged shift is clear between its waves.
- **`Mission.shout_score()`** and the modal debrief already say what a shout came to.
  Scenarios add one row: par, said as a margin ("02:59 under") rather than a target,
  so the player is not left doing the subtraction.

**The runner is created at runtime, and that is what makes it cheap.**
`Playground.tscn` is generated by `build_map.gd`, so shipping a node in it means
editing the generator and regenerating *with a window*. A node the menu builds and
adds to the running scene needs neither, and a scenario nobody picks costs nothing.
It finds the Mission and Director among its own siblings **by type** — neither is in
a group, the HUD reaches them by exported path, and a runtime node has no way to be
handed one.

**The freeplay director stays stood down.** `begin_shift()` is never called, so
`Mission.scoring` stays false and the scripted win path is live — which is also why
the score has to come from `shout_score()`: `Mission.score` is zero throughout.

**A scenario the career cannot field is not offered.** Each declares what it
`requires`, the picker reads the roster, and a row whose units are missing is
disabled with the reason under it — the same argument the freeplay director's
`needs_fire_service` gating makes, made once at the door instead of on every roll.
The card is rebuilt every time it opens, because the roster is what decides that and
the player buys units between visits.

### Two cards, and only one of them is modal

`UI/DebriefCard.gd` draws both endings, from `Mission` rows, built in code because
their number varies with what actually happened:

- **`show_shift()`** — the end of a freeplay shift. `debrief_rows()`: score, best,
  money, calls, average response, repairs, crew. It never takes the mouse; the player
  leaves it behind by pressing `F2`.
- **`show_shout()`** — the end of a scripted shout, the tutorial's included. It
  *replaced the `SHOUT COMPLETE` banner*, which could say the job was done and nothing
  else. `shout_rows()` is deliberately shorter: what it was worth, how long it took,
  how fast the turnout was, and only the tallies that are not zero. It is **modal** —
  `MOUSE_FILTER_STOP` while up, with a `CONTINUE` button — because it is the end of the
  thing the player was doing, not a readout beside it.

**A shout scores in freeplay's currency, without being paid for it.** `scoring` is off
during a scripted shout, so `Mission.score` stays zero throughout and would be a lie on
a card. `shout_score()` adds the same table up from the tallies instead — the same
point constants, plus the response bonus — and pays nothing and banks no record. A
mark, not a wage. To make the response half of it available at all, `_on_call_closed`
now tallies `calls_cleared`, `response_total` and `response_earned` **whether or not
the shift is scored**: they are facts about the mission, not about the shift, and
`begin_scoring()` zeroes every one of them so freeplay still opens on a clean sheet.

The modality has a reach worth knowing about: `_evaluate` declares a scripted win
whenever the last incident resolves outside a scored shift, which in the suite is most
of it. A fire doused in a radio-log test left a modal standing over the district and
cost four later click checks their targets — so `_click`/`_drag` dismiss any open card
first, the way a player would, and the modal's own behaviour is asserted where it
belongs: on the tutorial's finished shout.

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

CLEAR / RAIN / FOG / SNOW, on the same node and the same settings card — plus a fifth
button, **SHIFT'S OWN**, which is a policy rather than a sky: the director draws the
weather from its seeded stream when a shift opens (`Director.WEATHER_ROLL`, clear-heavy
on purpose), so every shift has its own weather and a reproduced `shift_seed` is rained
on identically. The visual half is a 40m precipitation box following the camera's
ground focus — thin fast streaks for rain, slow drifting flakes for snow, one
parameterised builder — plus a per-weather fog/exposure treatment applied *after* the
hour's preset so hour and weather compose without a row per pair. The fog treatment
**switches the fog on**: the map ships with `fog_enabled` off and its fog in depth
mode (where density is an opacity cap), so every density write in the project's
history was going into a disabled renderer path. Two sabotage passes measured the
numbers moving and never the look; a player pressing FOG and seeing nothing was the
measurement that counted. Weather flips to enabled exponential fog at an absolute
density and the baseline restore flips it back, so CLEAR remains the map exactly as
shipped. Fog also **lights the city at noon** — street lamps and every vehicle's
headlamps, through `Daylight.lights_on()`, which is what the lighting consumers now
ask instead of `is_dark()`: dark is a fact about the hour, lit is a decision about
the conditions, and real fog lights real cities.

The mechanical half is one number per state. `Vehicle.grip_scale` multiplies both grip
terms, and the autopilot already derives corner entry from `sqrt(max_lateral_accel *
grip_scale * radius)` and caps yaw by the same term — so `Daylight.GRIP` (rain 0.72,
fog 0.88, snow 0.62) lengthens braking distances and lowers apex speeds for the
player's units **and** the ambient fleet without a single branch asking whether it is
raining. Measured on one junction: **8.9 m/s dry, 7.2 wet.** Fog's 0.88 is caution
rather than a surface — what fog takes is sight, and `is_wet()` deliberately answers
false for it.

Rain's 0.5 was tried and rejected: junctions are 10m across and the planner already
sits near the limit of what a car can hold, so ordinary turns began missing their apex
and getting re-routed, which reads as a broken car rather than as weather. Snow's 0.62
sits between that rejected floor and rain. Note the grip figure has **two** consumers —
the corner planner and the yaw cap — so a sabotage aimed at only one leaves the other
still slowing the car.

Wet weather is also a **dispatch fact**: the rtc and bus_rtc rows of `Director.KINDS`
carry a `wet_weight` (double their dry weight) that `_pick_kind` swaps in whenever
`Daylight.is_wet()` — more collisions when the road does not grip, with the weather
node as the single source of truth.

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
> it, and whatever sits above the bar silently stops being clickable. It is no longer
> a height check that catches it — see "The interface".

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
| **Police** — officers, patrol cars | Move, Apprehend, Escort, Extinguish, Secure, Board, Stop — all on the officer; the car carries two |
| **Medical** — paramedics, the ambulance | Move, Treat, Collect (the stretcher run), Board, Stop; the ambulance carries and delivers |
| **Fire** — firefighters, the engine | Move, Extinguish, Cool, Free, Board, Stop; the engine carries the crew and the hose |

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
officer can stand in front of one all day and the intensity will not move. Since the
agents landed they also have the **electrical** fire outright, which is the first job in
the game that is police work *because* it is a fire rather than in spite of it.

**Cool** is fire-only and stricter still. A hazard has no reduced rate for a crew who
have walked away from the appliance: an extinguisher against a pressure vessel is not a
slower answer, it is not an answer. The order still runs and the animation still plays,
which is deliberately the same lesson a building fire teaches a patrol car — the game
says no by doing nothing visible, not by refusing the click.

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

### Armed response, and the first speciality that gates a verb

`Person.speciality` had been in the codebase since the doctor was added and had never once
decided what a unit *can do* — the doctor is a `Person` who treats faster, not one who can
do something a paramedic cannot. Armed response is the first case where the hook does the
job it was written for.

An **armed** `Suspect` (`@export var armed := false`) is not offered `ApprehendAbility` at
all. `ApprehendAbility.score()` returns `NOT_APPLICABLE` while the weapon is up, so an
ordinary officer right-clicking one falls through the ladder to Move and walks over to
stand next to an armed man, which is exactly the wrong outcome and exactly what the ladder
is for: the verb is absent rather than refused. `DisarmAbility` scores 34 — above
Apprehend's 30 — but only for a `Person` whose `speciality` is `Person.ARMED`, so the tile
appears on the ARV and on nothing else.

`disarm_per_second` is 0.25: about four seconds for one officer, two for a pair, after
which `armed` goes false, the pistol leaves the suspect's hand, and the scene reverts to an
ordinary arrest anybody can make. **Armed response makes the scene safe; it does not make
the arrest.** That is the division of labour the whole call is built around — the ARV
without a patrol car behind it achieves nothing.

The officer holds the weapon on them while they work. `DisarmOrder.CLIP` is `Pistol_Idle`,
and the weapon in hand is `SM_Wep_PistolSwat_01` — chosen because the shared animation
library has six pistol clips and **no rifle clips at all**, so a rifle would have been a
model held at the wrong angle by every animation the unit ever plays.

> Two traps came with the weapon. Synty's weapon prefabs ship a `MeshCollider`
> `StaticBody3D`; parented inside a character and teleported to the hand every frame, it
> **shoves its own carrier** — the first ARV drifted 19.5m in six seconds with zero
> velocity. `Unit.strip_collision()` is the shared answer. And the pose has to be sampled
> *while the order is running*: the check first read the animation after the disarm
> completed, by which point it is back to `Idle`, and reported a failure that was not one.

### The paramedic and the firefighter are wearing police blues

The City pack ships police characters and nothing else — no paramedic, no firefighter —
and no fire appliance either. For most of this project's life that was worked around: the
paramedic wore `Character_Female_Police` and the firefighter was `Character_Male_Police`
folded through `PolygonCity_02_A`, so that at RTS distance the crew read as fire rather
than as more police.

**Both were replaced in August 2026** from the POLYGON City Characters pack
(`SK_Character_FireFighter`, `SK_Character_Paramedic`), which ships them in their own kit.
The repaint machinery is gone from `build_character.gd` and `build_portraits.gd`; both now
shoot the thing the unit actually is.

**The pack sits on a third skeleton**, and that is the part worth remembering. It is mostly
Unreal-mannequin naming with some bones capitalised (`Pelvis`, `UpperArm_L`, `Hand_L`,
`Thigh_L`, `Foot_L`), the head lowercase, Synty's merged finger chains, and **no `Root`** —
close enough to the mannequin map to look reusable and different enough that it is not, since
bone names are matched exactly and case-sensitively. `setup_retarget.CITY_CHARACTERS` is its
map; it renames the rig onto the same `SkeletonProfileHumanoid` the Starter characters and
the animation library already share, after which one shared `AnimationLibrary` drives all
three rigs. The targets are built by **scanning the pack directory** rather than listing
nineteen import paths, because a character that misses the map imports under its own bone
names and then silently plays nothing at all — it does not fail, it just stands still.

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
both re-read from whatever the call holds, so nothing has to announce the change — and
since the drunk call arrived, the re-read also happens when something *leaves*: a
call whose casualty stood up swinging flips to **Disturbance** the frame the prune
drops them, by the same mechanism.

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

**Floating panels in the corners**, with the city visible between them. It was a docked
bar owning the bottom 176px until August 2026 — portrait, roster, command tiles and
dispatch laid out in one opaque strip — and the restructure onto the user's reference
layout unpicked it. As it now stands: the roster down the left, commands along the
bottom, minimap bottom-left, objective top-left, clock top-centre, purse and score and
speed top-right, call board down the right. The corner cart button was **retired in
August 2026** — the requisition sidebar carries a full-width REQUEST UNITS button of its
own, and two ways into the same shop was one too many. The
radio log is hidden (August 2026) — it kept composing its lines out of sight, and the
board it duplicated took over the edge it left empty.

Each panel stops the mouse over itself, so a click that lands on one is a click on the
interface and never also an order out in the world; the layers *between* them ignore it,
so the gaps are still city.

**The move was an anchors job, not a rewrite, and deliberately so.** `HUD.gd` resolves
fourteen nodes with `$`, the suite resolves about thirty `HUD/Root/...` path strings, and
two baked scenes carry `../HUD/Root/SelectionBox` — so every node kept its name and its
place in the tree, and only anchors, offsets and container types changed. `Root/Bar` and
`Root/Bar/Row` are the visible scar: a `PanelContainer` and an `HBoxContainer` that are
now transparent full-rect `Control`s with no stylebox and no size of their own, kept
under those names because renaming them would have cost forty path edits to no end.

The camera still renders full-screen behind the panels rather than into a letterboxed
`SubViewport` — which is now the only sensible arrangement, since there is no longer a
solid edge to letterbox against.

### What replaced the bar's six checks

The docked bar had six geometry checks, and every one of them named the neighbours it
compared — so a renamed panel made them pass *vacuously*. They are gone, replaced by one
invariant over `_hud_panels()`, a name→rect table resolved by path so a rename fails
loudly instead: no two panels overlap, all are on screen, the middle 40% belongs to the
city, and no panel rect moves when the selection changes. All four have been seen to
fail — the overlap one names the offending pair, which is worth more than a bare red.

The last of them is the one that earns its keep: `CommandBlock` is pinned in **both**
axes because an unpinned grid wraps to an 873px column for a full-roster selection. That
is the exact fault that once put the CONTROLS chip under the bar and stopped it being
clickable.

### Size panels from a probe, not from arithmetic

Every number in `HUD.tscn` that pins a panel came off a throwaway script that instantiates
the district, buys the suite's seven-unit fixture, selects everything, and prints each
panel's rect **and its `get_combined_minimum_size()`**. Laying the August 2026 slim-down
out by hand instead put the dispatch block through three neighbours at once, and the
second attempt still had the command block resizing with the selection.

Two things the probe tells you that arithmetic does not:

- **A `PanelContainer`'s content minimum beats its offsets.** Pin it smaller than its
  contents and it silently grows, so the offsets you wrote are a lower bound and not a
  size. The failure looks like a panel that moves on its own.
- **Bottom-anchored offsets give the height as their difference.** `offset_top = -145`
  with `offset_bottom = -22` is a 123px panel, not a 145px one. Both numbers are negative
  and it reads like the first one is the height.

Current minimums, for reference: roster 300×238 with eleven units across three services,
commands 500×141 for the fattest (14-ability) selection. Re-measure rather than
extrapolate — the roster's is a function of fleet size *and* column width, so a bigger
career grows it downward into the dispatch block, and the overlap invariant is what
reports that.

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

The scheme is **dark**, and since August 2026 it is a **UI kit the user supplied**
(`ui-kit/` at the project root: 210 vectors, design tokens, nine-slice margins, and a
reference Godot theme). It went light → dark → kit; each move is recorded in
`Palette.gd`, because the reasons are not obvious afterwards.

`Palette.gd` holds every colour, `build_theme.gd` bakes `Theme.tres` from it, and the
drawing code reads the same constants. Without one table the theme and the `_draw`
calls drift, and a unit ends up one blue in the roster and a different blue on the map.

### What the kit changed, and the one guard it broke

The chrome is now **art**, not styleboxes: `Game/UI/Kit/frames/` holds 114 vectors and
`build_theme.gd` bakes them into `StyleBoxTexture`s. Nine-slice margins come from
`ui-kit/NINE-SLICE.md` and are not free parameters — too small and a 6px corner
stretches into an ellipse, too large and the middle stops repeating. Circular pieces
(slider grabbers, status dots) are never nine-sliced; the kit says so and an oval
grabber is the proof. Type is the kit's pairing: **Rajdhani** for display, headings and
button labels, **Barlow** for body copy, which is most of why it reads as the reference
rather than as stock Godot.

`Palette`'s chrome constants are the kit's tokens **to the byte**, so the drawn parts
(minimap, command tiles, avatars) match the frames around them. The split worth knowing:
**chrome is the kit's, signals are the game's.** Service and marker colours stay as they
were, because they are read over a lit 3D city rather than on a dark panel, and the kit
has no opinion about that.

**One guard had to be re-pointed, which is worth being plain about.** The suite asserted
that adjacent surfaces differ by ≥1.3:1 in fill. The kit separates surfaces with a
*stroke* and a gradient instead — its raised panel is `#18222F → #0E1620` inside a
`#212D3C` line, and the fills either side are 1.16:1 apart — so that row failed on art
that is plainly legible. The check now makes each pair **name its separator**: a pair
with no stroke is still held to 1.3, and a pair that claims one must show that stroke
stepping clear of the darker fill. It is a loosening; what stops it being the kind that
gets obeyed-by-lowering is that the original failure mode — a surface the same colour as
its ground with nothing between them — still fails either arm.

**What wears the kit now**, beyond the theme itself: the top bar (a framed strip of
stat blocks, rebuilt from a centred pill cluster — the node stayed a `StatusStrip` at
the same path and changed what it *is*, which is what made the adoption cheap), the call
list (kit list rows with the kit's status dots, mapped onto the board's three real
statuses — the fourth dot goes unused rather than being wired to something it does not
mean), the radio log (notification frames toned by outcome: a new job amber, a delivery
green, a lost casualty red), the minimap (the kit's map frame), the unit readout (the
kit's unit-selection panel, header bar and all), the command tiles (the kit's grid
plate) and the shop cards (the recessed panel, replacing a hand-rolled well).

Three suite fixtures had to learn the new shapes, all the same class of thing: a
positional `get_child(3)` into a call row that gained a status-dot column, and two
readers that expected a log line to *be* a Label when it became a Label inside a frame.
Each now finds what it wants by type rather than by counting to it.

Two checks pin the kit itself, because nothing else here can see it: the suite is
headless and never looks at a pixel, so a builder edit that dropped back to flat
styleboxes would restore the old look with everything green. They assert a card is drawn
from a texture under `Game/UI/Kit/` and that button labels are set in a face under
`Game/UI/Fonts/`.

### The shop and the roster are the kit's now

Both were swapped in August 2026 for panels from the user's UI kit, and both were done the
same way: **a drop-in that keeps the old public surface**. `RequisitionPanel` keeps
`station`, `open_shop()`, `close_shop()` and `card_button(id)`; `RosterSidebar` keeps
`controller`, `station`, `standby_chip`, and the `request_button()` the tutorial pulses.
Nothing outside had to know. `ShopCatalogue` is the bridge: it reads `Station.TYPES` and
hands back the kit's `UnitDef` records, so there is still exactly one list of what can be
bought.

The sidebar shows every unit as a row — callsign, type, a real render of the vehicle, a
service stripe and a task line ("Fighting fire", "Treating", "Arresting") — and collapses
to an 80px rail carrying per-service tallies.

> **Rows are pooled, never freed.** The first version rebuilt them every tick, which
> destroyed and recreated the `Button`s continuously — and broke **arrests**, ten checks
> away, because an order held a reference to a control that no longer existed. The
> population is counted before the decision: rebuild only when the on-map or waiting count
> actually changed, otherwise restate the rows that are there.

#### The crash, and why five attempts to reproduce it failed

The game began dying with `EXC_BAD_ACCESS` (SIGBUS) inside Metal — always in play, never
headlessly, because **headless has no Metal**. Three diagnoses were confidently wrong:
deferred signals, the row pooling, the `AtlasTexture` cropping. What made it findable was
the player noticing that *spawning armed response* did it reliably; that produced a 20
-second staged probe with a 33–50% crash rate, and a real bisect became possible.

| Variant | Crashes |
| --- | --- |
| Baseline sidebar | 4–7 of 12 |
| Rows with no children | 6 of 12 |
| No rows at all | 7 of 12 |
| Sidebar never refreshed | **0 of 12** |
| Refresh without selection marking | 3 of 12 |
| Refresh without the layout call | 6 of 12 |
| **Catalogue cached** | **0 of 24** |

The cause was not the rows at all. `ShopCatalogue.units()` **instantiates and frees
thirteen vehicle scenes** to measure them, and `RosterSidebar._rebuild()` was calling it
once per unit — roughly 533 instantiate-and-free cycles per rebuild, several times a
second, on the renderer's own resources. A `static var _cache` fixed it. A later play
session ended with no crash report, which is the only confirmation that counts.

The lesson is the bisect, not the cache: **the crash was in a file nobody had touched**,
three panels away from anything on screen, and every attempt to reason about it from the
symptom picked a wrong answer.

### The main menu

Built to the reference the user supplied: a title plate, a column of icon rows, a
version plate at the foot. `Game/MainMenu.tscn` is the project's `main_scene` — the
game opens on it.

**The scene is authored at its hour** — night, since August 2026 — so what the editor
shows is what ships. It was not
at first: `Daylight` rewrote the lights and the environment on load, and the saved scene
described a bright midday forecourt that nothing ever rendered — which makes placing a
light in the editor guesswork. `Game/author_menu_hour.gd` writes the preset for
`MenuBackdrop.HOUR` into the scene's two suns and gave it its own environment copy (`Game/UI/MenuEnvironment.tres` —
the vendor `.tres` it referenced is shared with the district, and editing that in place
would have dimmed the whole game). The values were **read out of `Daylight.PRESETS`**
rather than retyped, and every one of them is an absolute assignment, so the runtime
grade running over an already-dusk scene is a no-op rather than a second darkening. The hour stays a
one-line change **with a second half**: `MenuBackdrop.HOUR` is what the game applies,
and `author_menu_hour.gd` — which reads that same constant — is what teaches the saved
scene about it. Change the one without re-running the other and the game is right while
the editor lies.

**The lighting is authored too.** Street lamps on every pole, headlights and a lightbar
on each emergency vehicle — 18 nodes written in by `Game/author_menu_lights.gd`, so the
editor viewport shows what ships and each light can be dragged, recoloured and re-aimed
by hand. What run time still owns is the *flashing*, because a saved scene cannot blink:
`MenuBackdrop` finds the beads and runs `Vehicle`'s double-blink over them. The cost,
worth stating: the lamps used to hang off the shell's `StreetLights` node, whose
visibility `Daylight` switches with the hour; authored, they are simply on. That is the
right trade only because this scene is a *set* — it is always dusk here and the hour is
a constant. It would be the wrong trade in the district, where the hour is a setting.

**The picture is a scene, not a still.** The user authored
`Assets/PolygonTown/Scenes/MainMenu.tscn` in the editor — a petrol station well alight,
a police cordon, an appliance pulled up — and it is treated as read-only input exactly
like the tutorial town: `MenuBackdrop` instances it and dresses it at run time, so cars
can be moved about in the editor and the menu simply shows the new arrangement. Dusk
and rain come from [Daylight], the district's own weather node pointed at the vendor
scene's two suns, rather than anything painted in. The environment resource is
**duplicated before it is touched**, because Daylight writes fog and ambient into
whatever it is given and that `.tres` is shared — dimming the district's sky as a side
effect of opening the menu is the bug that would otherwise be waiting.

**No HUD, because there is no HUD in the scene.** The bar, minimap and call list cannot
leak onto the title screen when they are not there to leak; that is the thing a
separate menu scene buys over an overlay. The cost is that PLAY, TUTORIAL and SCENARIOS
are now scene changes, and two of them carry state across the gap: `GameMenu.skip_title`
so the district does not open a second title card on arrival, and
`GameMenu.pending_scenario` so a scenario picked from the menu starts once there is a
district to run it in. Statics rather than signals because the two menus never exist at
the same time — one scene is torn down before the other is built.

Two checks pin the layout, because both failure modes are silent. A centred card would
satisfy every other check on this screen while looking nothing like the reference, so
one asserts the column starts in the left tenth and ends before 40% across. And the row
icons are looked up by name at build time -- `_icon()` returns null for a missing file
and a Button treats that as "no icon" -- so a renamed asset would cost the menu its
pictures without costing it a row. The other counts them.

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
closed: the CONTROLS chip above the bar (or F1) opens it.

### The bar is two rows, and the check pins the symptom

For six phases the command block was sized so the tiles fit **one row**: let them wrap
and the `PanelContainer` grows, the bar grows with it, and whatever sits just above is
silently covered. A check pinned the bar at 148px ± 4 and caught it every time.

Pinning the height was still wrong, and August 2026 is how that showed. The block was
widened for a ninth tile; the height was untouched; a height check would have gone red
for a change that was fine. So the check was rewritten to assert the **symptom** — that
the CONTROLS chip is still visible and unoverlapped — which is what actually broke five
times. A magic number is what would have let it break the sixth.

Then the rewritten check found a bug that had been live all along. It selected one
patrol car, whose tiles fit one row; the sabotage agent reverted the widening and the
check stayed green, because the fault never reached the measurement. **A scenario that
cannot provoke the fault is no better than an assertion that cannot see it.** Selecting
*everything* is the real worst case, because `RTSController.available_abilities()`
returns the **union** across the selection: a mixed box-select offers 14 tiles, wraps to
two rows whatever the width, and put the chip under the bar. It had been unclickable
that way since long before this tranche; nobody had box-selected across services and
then reached for the chip.

The fix is a bar that is two rows tall always, with the chip above that height. One more
correction worth keeping, because it inverts the obvious reading: the `Bar`'s own
`offset_top` is a *minimum*, so once the tiles wrap the content sets the height and the
offset is inert — sabotaging it back to 148 changes nothing. It earns its place by
stopping the bar changing height between selections, not by stopping the overlap. The
chip's offsets are what do that.

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
keycode would put them in alphabetical order instead, which teaches nothing. The list
runs bottom row (`Z X C V B N M`), then home (`G H J K L`), then top (`T Y U I O P`) —
and a verb whose key is *not* in it files last alongside every other unplaced verb,
which is a silent way for the row to stop meaning anything.

> **`Clear` was on `J` and so was `Lights`.** The rationale was written down as fact —
> one is a foot verb, the other a vehicle verb, so they never meet — and it held until
> `can_tow` gave the recovery truck the winch, making it the one unit carrying both.
> `_handle_hotkey` takes the first match in tile order, so the truck's lightbar was
> unreachable from the keyboard. Clear is `O` now, the only letter the camera does not
> poll and no other verb had taken, and there is a check that sweeps **every** unit scene
> for a key that answers twice, for a key the camera polls, and for a key with no slot in
> `COMMAND_KEYS`. The lesson is not the key: it is that an invariant maintained by
> reasoning about which units exist stops holding the moment a new unit does.

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

## The helicopter does not drive

`Aircraft` (`Game/Units/Aircraft.gd`) is a `Unit` that ignores the navigation mesh
entirely. There is no air layer and there does not need to be: nothing in the sky is an
obstacle, so a flight is a straight line at `cruise_height` (24m) and the whole
"navigation" problem disappears. It is the one unit in the game whose movement is not the
autopilot.

**Five phases, and the order of them was the whole feature.** `GROUNDED`, `SPOOLING`,
`CLIMBING`, `CRUISING`, `DESCENDING`. Rotors were first driven off *altitude*, which is
the obvious reading and wrong in both directions: it lifted off with the blades barely
turning and it wound them **down** as it came in to land, which is precisely backwards
from how a helicopter lands. They are driven off the phase now — `rotor_spool` is 4.0
seconds of blades before the skids leave the ground, and they stay at full speed all the
way down.

`_leave_ground()` is a **single door**: `take_off()`, `navigate_to()` and `land_at()` all
go through it, so there is no path into the air that skips the spool-up. `is_airborne()`
deliberately excludes `SPOOLING` — a machine with its rotors running is not yet flying.

Two things that each cost a debugging session:

- **`_ground_y` cannot be read in `_ready`.** Anything positioned after it enters the tree
  — which is every helicopter the map places — records the wrong ground, and a parked
  aircraft sat on the forecourt spinning its blades. It is captured at `_leave_ground()`.
- **`LandAbility` beat `Move` on every right-click.** It scored 12 against `MoveAbility`'s
  floor of 0, so ordering a helicopter anywhere landed it there and hovering was
  unreachable. It is armed-only now: `score()` returns `NOT_APPLICABLE` and `can_target()`
  does the work, which is the pattern for any verb that should fire only when the player
  asked for it by name. The suite had a landing check and it called `land_at()` directly,
  so it never touched the ladder and never saw this.

Turning is rate-limited (`turn_speed` 1.6 rad/s) rather than snapped, with `SIDEWAYS_SPEED`
letting it drift a little while it comes round. Snapping to the new heading read as a
sprite being rotated, which is what it was.

Take off is `U` and fires at once; `Land` is `Y` and arms the cursor for a spot.

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

### One library, referenced — and the line that decides it

All eleven character scenes share `Rigs/ual_standard.res`, and the sharing rests on a
single call in `build_character._extract_library()`:

    library.take_over_path(LIBRARY_PATH)

`ResourceSaver.save()` writes the file but leaves the in-memory resource **pathless**,
and `PackedScene.pack()` inlines any resource it cannot point at. Without that line
the library is saved correctly, referenced by nothing, and copied whole into every
character scene — which is exactly how it stood until August 2026: eleven 3.02 MB
scenes carrying byte-identical keyframes (16 differing lines in 18,167, all node ids
and mesh refs), **315 ms each to parse**.

Nothing looked wrong. It was measured only when the tutorial's opening delay was
chased with a stopwatch:

| | before | after |
|---|---|---|
| the eleven characters, cold | 3,461 ms | **66 ms** |
| tutorial's first frame | 5,770 ms | **28 ms** |
| a casualty or missing-child spawn | ~630 ms | **~1 ms** |
| the scenes on disk | 3.02 MB each | 29 KB each |

The library is deliberately **binary** (`.res`, not `.tres`): the same 43 clips are
3.0 MB of text that parses in 313 ms, and 1.2 MB of binary that loads in 7 ms. Text
parsing of keyframed float tracks was the whole cost, and every character-bearing
scene paid it — a casualty spawned two, its own and the outfit `_wear_outfit()` puts
on it, which is why missions hitched as they opened.

Two checks guard it, because a regression here is invisible: the game looks and plays
exactly the same, it just quietly gets slow again on the next rebuild. They assert
that all eleven scenes hand back **one** library instance, and that its path is the
file on disk (an embedded copy has none of its own).

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
physics, same checks, ~60 seconds instead of ~9 minutes.

1123 checks. Runs real physics without a renderer: the fixtures buy and dispatch a
shift through the station (the map ships empty), and every bought unit is clickable
from the opening view; the crowd strolls, runs from a fire and cannot be selected or
picked through; traffic drives the roads and yields; units start parked, drive to a
target, stop on arrival, turn around for a target behind them, cross the district
corner to corner, route around the centre block, and — ordered into the middle of a
block — come to rest out on the street instead; synthesised input for select /
deselect / box-select / shift-add / control groups / order / queued order / Stop /
marker / respawn; camera pan, clamping and zoom; the interface — the panels stay in
their corners without overlapping and leave the world clickable, the map's zoom buttons
move the camera, the score strip counts the fleet and pauses the district from its own
button, the command grid tracks the selection in keyboard
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
  `unproject_position` meaningless and leaves the command panels spanning the entire
  screen, where they eat every click as GUI input before `_unhandled_input` sees it.
  Symptom: right-clicks silently do nothing, but only after a *clicked* selection
  — a code-driven selection still works, which makes it look like an input bug rather
  than a layout one. The panel invariant catches it directly: "the middle of the screen
  is the city's" cannot hold on a 64x64 viewport, whatever the panels do.
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
