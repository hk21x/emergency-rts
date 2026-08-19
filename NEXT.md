# What is left to do

Follow-up work, in the order it is worth doing. `PROGRESS.md` is where things *are*;
this is where they are going.

**The August 2026 roadmap has shipped in full.** Phases 16 (the world reacts), 17
(audio), 18 (game framing) and 19 (the fire service) are done, and so is phase 20 —
the career economy first, then the campaign scenarios that were its other half. The
interface has since been rebuilt on the user's UI kit and floated off its docked bar.

So there is no roadmap left, and most of what follows is a **gap rather than a plan**:
things that are missing and would each stand alone. The two that were flagged here as
worth reading first have both since been closed — the crowd refills now, and the
economy has a sink — so pick by what you want the game to be, not by urgency.

**The one exception is the section immediately below.** "Debts owed" is not a menu: it is
what the last stretch of work left unfinished, including four features' worth of checks
that have never been proven to detect anything and a live hotkey collision that the
reference file still describes as impossible. Clear those before starting something new.

---

## Debts owed (August 2026) — do these before anything new

Not gaps. Things the last stretch of work left behind, listed because each one is a
promise this project made to itself and has not kept.

### ~~Four features' worth of checks have never been seen to fail~~ — closed August 2026

All four are done: the **wreck**, the **ARV**, the **pistol pose** and the **roster
sidebar**, each fault reinstated one at a time and watched go red. The exercise found four
real gaps rather than merely confirming what was there — all written up in PROGRESS.md:

- **The wreck**: `WorkOrder.VEHICLE_STANDOFF` could be zeroed with the suite entirely green,
  because `ClearOrder.VEHICLE_REACH` absorbed the fault. Closed with an assertion on the aim
  point.
- **The ARV**: the speciality gate — the entire reason the unit exists — had nothing
  watching it. Closed, and then proven to be the only assertion in the suite that catches it.
- **The roster**: its worst shipped bug (rows stuck on AVAILABLE) had no check, and the
  check written for it took **three rewrites** before it could see the bug.
- **Readability**: every `resolve()` assertion printed `<RefCounted#-92233708...>`, so the
  failing line — often a sabotage's only evidence — could not tell Disarm from Apprehend
  from Move. They name the ability now.

**What to carry forward.** A sabotage produced a green suite four times over, from four
completely different causes: a competing constant absorbing the fault, a second gate
enforcing the same rule upstream, a scenario that never provoked it, and an assertion a
sentinel satisfied. Only one of those is "the check is bad" in the ordinary sense. Green
under sabotage starts a diagnosis rather than ending one, and the question to ask of the
output is not whether the measurement *moved* but whether it *shows the fault*.

**Still worth doing**, in the same family: `Glyph._fallback` ends in `_: _unknown(...)`, so
a typo'd `icon()` key draws a generic symbol and ships silently. Nothing asserts every
ability's icon resolves. Three verbs already share `shield` (`apprehend`, `escort`,
`disarm`) and an armed officer offers all three, so that grid carries three identical tiles.

### ~~`Clear` and `Lights` both answer to `J`~~ — closed August 2026

`Game/README.md` states the rationale as fact: *one lives on foot rosters, the other on
vehicles, so they never meet*. That stopped being true the moment `can_tow` gave the
recovery truck `ClearAbility` — it is a `Vehicle`, so it also has `LightsAbility`, and one
of the two tiles is now unreachable from the keyboard on the only unit that needs the
winch.

**Fixed.** Clear is `O` — the only letter the camera does not poll and no other verb had
taken — and `COMMAND_KEYS` now carries `Y U I O P` as well, so the four verbs added since
the helicopter have defined slots in the row instead of being filed last together.

The repair that matters is the check, not the key: `_test_no_unit_offers_two_verbs_on_one_key`
sweeps all fourteen unit scenes (92 bound verbs) for a key that answers twice, a key the
camera polls, and a key with no slot in `COMMAND_KEYS`. It has to add each unit to the tree
to do it — `_abilities` is built in `_ready`, so reading them off a bare `instantiate()`
returns an empty list and passes everything, which is the vacuous version of this check.

**What is still open here** is the other half of that roadmap item: nothing asserts that
every `icon()` key resolves in `Glyph.gd`. `Glyph._fallback` ends in `_: _unknown(...)`, so
a typo'd icon key draws a generic symbol and ships. Worth noting while looking: three verbs
already share `shield` (`apprehend`, `escort`, `disarm`) and an armed officer offers all
three, so that grid has three identical tiles. Not a defect — but not a design either.

### `ShopPanel.gd` is dead; `Roster.gd` is not

`Game/UI/ShopPanel.gd` has **zero references anywhere** — the requisition modal replaced
it entirely. Delete it.

`Game/UI/Roster.gd` looks equally dead and is not: `RosterSidebar` loads it by path under
`LEGACY_ROSTER=1` as a bisect escape hatch. Deleting it means deciding that hatch has
served its purpose — which it arguably has, now that the crash it was built to bisect is
found and fixed. That is a call to make deliberately rather than by tidying.

### Twelve probes and a diagnostic still on disk

`Game/probe_*.gd` (twelve of them) and `Game/diagnose_driving.gd`, referenced only from
comments. **Move the measurements those comments cite into `Game/README.md` first** — a
live comment pointing at a deleted file is worse than the dead file it points at.

### The suite is one 12,815-line file, and it is the next thing to grow

`Game/smoke_test.gd` is now **12,815 lines** — comfortably the largest file in the project
and around a third of all the GDScript in it. It has grown ~1,000 lines in a month, and
anything done to the campaign adds a hundred checks on top of that.

Split it as a **pure move**, proving nothing broke by check-count identity: `all checks
passed (1123)` before and after, with no other change in the same pass. A
`Game/Tests/TestCase.gd` holding the fixture, N files cut along the section comments
already in the file, and a ~100-line runner summing per-file counts.

The per-file counts are the real prize rather than the tidiness. A runtime error inside a
check **skips the rest of that check silently** — the suite still reports green and only
the total falls, which is how two checks stopped short for months and cost three out of six
hundred without anybody noticing. Per-file totals make that failure mode legible for the
first time.

### The game has never been built

There is no `export_presets.cfg`. Not once, in twenty-one phases. It is the largest single
unknown in anything downstream of "ship this", and it wants smoke-testing **early** rather
than at the end: make a macOS build, launch it, and confirm the `user://` paths, the icon,
and that the CC0 audio and kit assets survive the export filter.

`config/name` is also still `Polygon_Starter`, and it sets both the window title *and* the
`user://` folder — so renaming it orphans every saved career, record and setting unless a
migration copies the old folder forward. Decide before the first public build, not after.

## Standing gaps

### Audio — one recording in, four placeholders to go

Phase 17 shipped in August 2026: a manual two-tone siren (`K`), an engine note
pitched by road speed, a fire crackle scaled by intensity, a dispatch chirp on every
call the board opens, and a city bed under it all. All five were **synthesised** by
`build_audio.gd` rather than recorded — the project owns no sound library — as honest
placeholders that a real recording could replace file-for-file.

The siren has since been replaced for real, and it proved the swap costs about ten
minutes: drop the file in `Game/Audio/`, add it at the head of the vehicle's stream
list, `--import`. Two things the first swap turned up, which the other four will hit
too. **Looping is a per-format property** — three fields on a WAV, one `loop` bool on
an MP3 or Ogg, and the importer leaves that bool false — so a straight path swap
yields a sound that plays once and stops, past every check that only asks whether a
sound is loaded; `Vehicle._looped()` now normalises this and `Vehicle.loops()` lets a
check pin it. And **a mastered recording is roughly 6dB hotter** than the generated
tones, which peaked near half scale, so `volume_db` wants dropping by about that much
or the new sound arrives shouting.

Engine, crackle, radio and city bed are still synthesised. Engine is the awkward one:
it is pitch-shifted by road speed at runtime, so a recording needs to be a steady
idle rather than a rev, or the shifting fights the performance baked into it.

The **automatic siren is now settled** and this entry used to argue the other way, so
the reversal is worth keeping rather than overwriting. It read: *deliberately still
manual — an automatic siren on every unit at once was noisier than it was useful in
the one test of it.* That test was run against the synthesised two-tone, which was a
harsher noise than the recording that replaced it, and it was run before the siren had
any reason to stop: what makes it bearable is that it is tied to `_navigating`, so it
ends the moment a vehicle arrives rather than running for a whole shift. Since August
2026 the audio hangs off the same `(_navigating and is_responding()) or <switch>`
condition as the lightbar, so an order sent by right-click lights the bar and sounds
the horn together and arriving kills both. `J` and `K` are still two separate switches,
because the cases where they come apart — lit and quiet at a scene — are worth having.

What is still missing: voice acknowledgements ("on scene", "casualty aboard"), which
would need either a voice pack or speech synthesis; and per-surface tyre noise.

### The two asset packs, and what is left in them

POLYGON Town and a particle pack landed in August 2026. The fire appliance and the
fire/smoke FX were taken from them (see PROGRESS.md). What remains, and why it was not:

- ~~**The crew is still a repainted police model.**~~ **Closed August 2026.** The
  POLYGON City Characters pack arrived with `SK_Character_FireFighter` and
  `SK_Character_Paramedic` in their own kit, and both are now what the units are built
  from. The paint-warmth check did not need re-pointing -- it guards the real turnout kit
  now instead of the repaint trick, and passes with more margin than it did (+0.18).

  **The pack sits on a third rig**, and that is the transferable part: mostly Unreal
  mannequin naming, some bones capitalised (`Pelvis`, `UpperArm_L`, `Foot_L`), Synty's
  merged fingers, and no `Root`. It needed its own bone map --
  `setup_retarget.CITY_CHARACTERS` -- which renames it onto the same
  `SkeletonProfileHumanoid` the Starter rig and the animation library already share. So a
  new character pack is **a bone map plus a `--import`**, not a project, *provided its
  naming is close to one of the three already mapped*. Without the map a character
  imports under its own bone names and silently plays nothing at all.
- **Town's people cannot be used for the crowd.** They are skinned to a *different*
  skeleton (`Ankle_L`, `Clavicle_L`, `Elbow_L`) from the City pack's humanoid rig
  (`Hips`, `Spine`, `UpperChest`, `LeftShoulder`), and `Game/Rigs/ual_standard.tres` is
  authored against the latter. Adding them is a retargeting project, not an asset swap.
- **The pack's rain was left alone deliberately.** `FX_Rain_01` is 500 drops in a 1m box
  with a `RibbonTrailMesh`, built for a small scene. The district's rain encodes a
  hard-won fix -- a narrow box, small faint drops, `BILLBOARD_PARTICLES` -- and swapping
  it risks relearning "the rain's first build put glass rods over the city".
- **Untaken and cheap**: Town has playground equipment, a fountain, hedges and flower
  patches that would make the district's parks read as parks (`_park_tile` in
  `build_map.gd`), and seven more vehicle bodies (bus, school bus, pickup, delivery and
  garbage trucks) for the ambient fleet. The traffic bodies want measuring first: a bus
  is far longer than anything currently driving, and the driving checks are sensitive.
- **The Heist pack is spent, and it was the cheapest pack yet.** It arrived on the *same*
  rig as the existing characters, so everything in it was a drop-in through machinery that
  already existed. `SM_Veh_SwatVan_01` became the prisoner van (two dictionary rows and a
  portrait — no new code at all), `SM_Chr_Male_SWAT_01` became armed response,
  `SM_Veh_Car_Police_Heist_01` a second patrol body, and `SM_Veh_Helicopter_01` the air
  unit. What is **still untaken** is the interesting half: bank interiors, an ATM, a vault
  and an alarm, which together make an **armed robbery** authorable as a call kind — and
  which would give the SWAT van a second job and the ARV a reason to exist beyond one
  director roll. The pack's `PolygonHeist_04_A` atlas is also where the helicopter's
  Rescue livery came from; it was nearly missed, because grepping filenames for "rescue"
  finds nothing and only a per-atlas diff turned it up.
- **Weight.** `Assets/PolygonTown` is 44MB, almost all of it buildings, props and
  characters the game does not use. If the repo size ever matters, a `.gdignore` in its
  `Scenes/` and `Prefabs/Buildings/` would cost nothing -- the pattern already exists at
  `Assets/padding/.gdignore`. Do not ignore `Models/`, `Materials/` or `Textures/`: the
  appliance's material chain runs through all three.

### Campaign scenarios — shipped August 2026

Three designed shifts on a SCENARIOS card off the title: SATURDAY NIGHT, RING ROAD
PILE-UP, WAREHOUSE ALIGHT, each a timeline of calls against a par time. See the
campaign section in `Game/README.md` for the architecture; the short version is that
it was mostly authoring, exactly as this entry predicted — `Director.open_kind()`
places all sixteen call kinds already, `Mission` already scored a scripted shout, and
the debrief modal already existed to say what it came to.

What a second pass could add, in rough order of value:

- **More of them.** The cost of a fourth is one dictionary in `Scenarios.ALL`.
- **A best time per scenario**, banked the way `Mission.best_score` is banked for
  freeplay — the par row invites it, and the ConfigFile is already there.
- **Objectives beyond "clear it"** — save all six, keep the fire from spreading past
  a building, no casualties lost. `Mission` has the tallies; what is missing is a
  place to say the target and a line to show it mid-shift.
- **A campaign order** — scenarios unlocking in sequence rather than all three at
  once, which is the point at which this stops being a list and starts being a
  campaign.

**One of them is a live bug rather than an addition.** `Mission.fail_on_casualty_lost`
defaults to `true` and nothing overrides it for a scenario, so **a single dead casualty
ends a designed shift on a bare red banner** — no debrief, no par time, no retry, in a
mode whose whole point is being replayed until it is beaten. `_evaluate()` runs the
incident rules whenever `scoring` is false, which is exactly the scenario case; the LOST
arm needs the `show_shout()` with a RETRY that WON and OVER already have, and the flag
needs to be a per-scenario key. Roughly fifteen lines, and it is the first thing to do
here.

The other prerequisite is **scenario provisioning**: scenarios are currently gated behind
units the career has to buy, while only *freeplay* fills the purse — so the campaign is
locked behind grinding the mode it is an alternative to. `Station.career_path` is a `var`
rather than a `const` precisely so a scene can carry its own book, and the tutorial already
does this. Repoint it to `user://campaign-<id>.cfg` on `ScenarioDirector.begin()`, issue
the units, restore on exit.

> **This is the single largest exposure to a known trap in this codebase.** Anything that
> purchases units without repointing `career_path` first overwrites the player's real
> fleet and purse, silently — that already happened once, from a throwaway probe that had
> no business touching the books. Whatever is built here wants a check proving
> `user://career.cfg` is byte-identical across a scenario run.

### The crowd: refilled, but still orderly

**Fixed in August 2026** — `CrowdRefill` puts a shopper back on the pavements every thirty
seconds, up to the size the map was built with and no further. See PROGRESS.md.

The two companion pieces it unblocks are still open, and both are cheap now the crowd
can refill:

- **Onlookers becoming casualties** — a spreading fire catching someone who stood
  watching too long. The mechanism is not merely available, it is **in use**:
  `Hazard._hurt_people()` does exactly this swap when a cylinder goes off, taking the
  person who was standing there and the clothes they were wearing. Pointing the same
  code at a fire that has grown past a civilian is most of the work.
- **Panic** — phase 16's crowd flees along the pavement graph and crosses at the
  zebras even while running, which is orderly to a fault. A crowd that scattered
  badly, blocked a stretcher or ran into the road would make a scene feel dangerous.

Everything else the crowd does landed in phase 16: they flee fires, keep out of
cordons, gather at a collapse or a disturbance and watch from a standoff, and a
medical call takes one of them.

### The economy: what the sink does and does not cover

**Repairs shipped** in August 2026 — see PROGRESS.md. Damage accrues on impact, is
settled when a unit is booked in at the station, and never takes a unit off the board.
That is the first thing that takes money back.

It is not enough on its own. A careful player still accumulates, and a career that has
bought everything has nothing left to spend on — the £1,400 engine is a one-time hurdle
rather than an ongoing decision. The two options not taken:

- **Write-offs** — a unit lost at a bad scene. The sharpest, and the cruellest.
- **Running costs** — a per-shift wage bill, so an idle fleet is a liability.

Repairs was built first because it charges for **how the player plays** rather than for
time passing, and because it can be paid in instalments: the purse empties but never goes
overdrawn, and what it cannot cover stays owed. Either of the others would want that same
property, or a very careful look at what happens to a career that cannot pay.

### Driving: where it stands

Three faults were reported from play across August 2026 and all three are fixed — see
PROGRESS.md for each. The session that confirmed it produced **no records at all**, the
first clean one of the investigation:

- **The 360° loop.** A route began at the nearest junction even when it was behind the
  car, forcing a 180° turn the reverse latch would not make at 48m. Measured at 523° of
  turning before any ground was made toward the destination.
- **The touring.** The give-up timer blamed the road for the car's own trouble, wrote off
  streets nothing was blocking, and turned a journey 200m east into twenty waypoints
  ending at the western edge of the map.
- **Orders off the map.** An out-of-rect minimap click converted to a destination outside
  the district, which the navigation agent silently clamped to somewhere else entirely.

All three were found by the **black box** (`Game/StuckLog.gd`), not by a staged test —
and that is the durable lesson. Every headless staging of "a unit gets trapped" came out
clean, because the faults were not traps: they were bad routes, bad orders and a
misattributed cause. Three fixes built on staged evidence in the same period were
measured, found wanting and reverted. When the next handling fault is reported, **read
the log before writing a probe**, and make sure a record carries a trail — a snapshot
cannot tell a car that stopped where it stood from one that wandered off its route first.

What is still known and unfixed:

- **A car can pin itself against a kerb.** A 7cm kerb is a vertical wall to a box
  collider, so a car driven at one stops 2.8m short and oscillates. Bevelling it was
  built, shipped and removed: the kerb turns out to be what contains cars through
  corners, and made climbable it put 328 of 1836 frames of a turning journey on the
  pavement. There is no middle setting *in the geometry* — a kinematic body climbs any
  slope under `floor_max_angle` at any speed. Fixing this properly means the *steering*
  holding the car in lane, not the geometry.

  **A third attempt (August 2026) put the step-up on the vehicle instead of in the
  ground and shipped** — `Vehicle._climb_kerb`, a manual lift gated on the car's own
  state, on the reasoning that the "no middle setting" rule binds a slope but not a
  body. Right-click a pavement and the car drives to the kerb, climbs it and parks on
  top: measured, the order completes and the car ends **on the pavement** 2.0m from the
  target having climbed four times, against never getting up and stopping 6.7m short on
  the road with the lift disabled. The corner is untouched — 12.9s, 0 of 773 frames off
  the carriageway, 0.0m off the mesh, identical to the metre with climbing on and off.

  **Three refinements came from play, after it "worked".** The lift must not wait on the
  stuck timer for an off-road order (the car sat grinding at the face until slow enough
  to be allowed over); it must carry the car forward as well as up, or it drops back
  against the face and fires again — 33 lifts on one journey; and the reverse latch and
  escape manoeuvre must be off within `off_road_approach`, or a car that has just climbed
  up reverses off at 8 m/s and starts over. Damage is excused for non-vehicle contacts on
  that approach too. Together: up at 1.4s, two lifts, order complete in 2.4s, £0.

  **What made it work was changing the gate, not the lift.** The first cut gated on
  being stuck, and that is the wrong question twice over: it fires on corners (where it
  causes the bevel's damage) and never fires where the player wants it. The gate that
  ships is *the player asked* — a destination off the vehicle navigation layer sets
  `_off_road_target`, which both keeps the order alive and licenses the climb. A car
  with a road destination still has to earn a climb the hard way, through
  `climb_escapes`, which is what keeps corners honest.

  Three things measured on the way, each a finding about the district rather than about
  the lift, and all three are why the stuck-gated version fired nowhere:

  - **A car is never *routed* over a kerb.** An order aimed at a pavement completes on
    the first frame — the agent clamps an off-mesh destination to the nearest reachable
    point and `is_navigation_finished()` goes true before a wheel turns.
  - **A car never *reaches* a kerb.** It queues 7m short of a blockade, and threads a
    single obstruction — even one angled across the lane — in 11.4s without touching the
    verge. The carriageway is simply wide enough.
  - **The autopilot will not drive into one.** Aimed along the road with its nose at a
    kerb it steers away, 18.7m up the street.

  Gated loosely it is actively harmful, and the numbers are the bevel's own returning:
  the turn into junction 1,3 went **12.9s → 41.2s**, with **423 of 2473** frames off the
  carriageway and **3.3m** off the drivable mesh, against the bevel's 30.6s / 328 / 4.9m.
  The gate that fixed that is `climb_escapes` — climb only after the reverse-and-retry
  manoeuvre has already failed twice, which a cornering car never does. With it the
  corner is identical to the metre with climbing on and off.

  Note that this does **not** address the fault reported from play — cars stuck *behind
  other vehicles*, which every black-box record names as `holding behind: <a vehicle>`.
  Driving onto a pavement is a verb the player now has; it is not a fix for queueing.

  Still open on it: a car put down on a pavement is off its own navigation layer, so the
  order that took it there is the last one that works cleanly — sending it away again
  drives it off the kerb, which is free, but the route out is whatever the agent makes
  of a start point it does not believe in. Worth watching in play before doing anything
  about it.

  Two harness lessons from the same stretch, both of which nearly produced a wrong
  answer. **Running both conditions in one process measured the process, not the
  feature**: whichever ran second failed, and reversing the order reversed which one
  failed — 11.4s and 30.0s, exactly swapped, with the climb firing zero times in the run
  that supposedly proved it harmful. One condition per process. And **a landing check
  written with `map_get_closest_point` was completely vacuous** — that call takes no
  layer filter and both navigation regions share one map, so it answers 0.00m for a
  point in the middle of a pavement. The trap is written up over `_passing_line` in
  `Vehicle.gd` and I walked into it anyway; the only reason it was caught is that adding
  the check did not move the measurement by a single frame.
- **Corners are taken too wide, and the cause is *not* where the arithmetic says it is.**
  Reported from play as "almost as if the vehicles are oversteering", which is what a car
  at full lock still running wide looks like from above. `Game/probe_corner.gd` measures
  it: on the turning leg (1,1)→(4,3) a patrol car gets **3.33m into the oncoming lane**,
  and the corner planner's slowest ask over the whole leg is **11.23 m/s** for a
  right-angle turn its own geometry can only hold at **7.88** — 43% too fast. Once it
  arrives over-speed the yaw cap in `_apply_yaw` clamps the turn rate to a 5.91m arc
  where the steering describes 4.44m.

  **Two plausible fixes were built, measured and reverted, both no-ops.** The planner's
  anti-creep floor really is inconsistent — it is `max_speed * corner_speed_ratio`, which
  on the patrol car is 9.10 m/s against a holdable 7.88, so the floor is capable of
  vetoing the physics — but flooring it by `_turn_speed(PI/2)` as well changed the
  trajectory by **not one byte**, because `limit` never descends to the floor in the
  first place. Saturating `_turn_speed` below a right angle (on the theory that the mesh
  cuts the junction box, so a street corner reads as ~73°) moved 3.33m to 3.36m, which is
  noise. Neither is the cause; both are reverted.

  **The mechanism is now known, and it is the angle measurement.** Tracing
  `_corner_speed_limit`'s own terms through a turn (`CORNER_TRACE=1` on the probe) shows
  the same vertex reading **15° at 16m, 21° at 13m, 30° at 9m, 47° at 5m, 85° at 3m and
  132° a moment later**. The corner is not a fixed property of the path as that loop
  reads it: `incoming` runs from wherever the car *is* to the vertex, and a car sitting a
  lane's width off the centre line swings that vector round as the gap closes. So the
  turn reads at its gentlest exactly when there is still room to brake — 32 m/s allowed
  at 16m out — and admits to being a right angle with three metres left, at which point
  the car is doing 14.3 and needs 9.0. That is the overshoot, and it is why every attempt
  to fix this by adjusting speeds failed: the speeds were being computed from a corner
  the planner could not yet see.

  **Two remedies were built and measured and both are reverted.** Measuring the angle
  along the path (`path[i] - path[i-1]`) instead of from the car took one leg 42.5s →
  29.0s but stopped detecting corners at all on two others, which went to `26.00 m/s`
  planned, i.e. no limit. And a **waypoint-capture** test in `MoveOrder` — the switch at
  `MoveOrder.gd:97` is pure proximity, so a car that sweeps within `WAYPOINT_SWITCH` of a
  marker without turning still ticks it off and jumps its aim to the next junction, which
  is the player's own diagnosis and is correct — took leg 1 to 24.4s but sent the others
  to 59.1s and 35.5s, because a car that cannot round a marker orbits it. A 1.5s dwell
  fallback tamed the orbiting (34.6s, 24.1s) but left every leg **3.7m into the oncoming
  lane** against 0.00m at baseline. Baseline is 42.5 / 15.9 / 18.0s and 3.33 / 0.00 /
  0.00m; beat that before shipping anything.

  Note for whoever takes it: **halfway waypoints do not fix this**. The switch is
  proximity-only, so an overshooting car ticks off an intermediate marker exactly as
  readily as a junction one — more markers means more of them wrongly consumed, not
  fewer. The test is what is wrong, not the resolution. And the two faults compound: the
  planner lets the car arrive too fast to turn, and the order then rewards it for
  missing. Fixing the angle first is the right order, because a car that arrives at a
  speed it can hold never reaches the capture problem at all.

  **Three defects are now identified, all real, and fixing all three is still not enough.**
  Beyond the angle-from-the-car fault above, the trace exposed a second: **the agent's
  path index races ahead of the car.** On one leg it went vertex 2 → 5 → 7 in a fraction
  of a second, against vertices spaced twelve metres apart at 18 m/s. `_corner_speed_limit`
  starts its scan at that index, so it was scanning *past* the corner while the car was
  still approaching, and honestly reporting nothing ahead. The car-relative angle had been
  masking this, because a long vector from the car to a far-ahead vertex still crosses the
  corner geometry; fix the angle and the index fault surfaces as `NO CORNER SEEN`.

  All three were fixed together — a symmetric `_direction_before()` window, a scan
  starting at `mini(agent_index, nearest_vertex)`, and the geometry floor (which only
  becomes load-bearing once the other two land, at which point every leg bottoms out
  exactly on it). **The planner then behaves correctly: it asks 7.89–7.91 m/s for a
  corner holdable at 7.88, on every leg, against 11.23 / 14.24 / 13.14 before.** And the
  car still corners wide: 31.8 / 29.3 / 23.6s and 3.34 / 3.25 / 2.29m against a baseline
  of 42.5 / 15.9 / 18.0s and 3.33 / 0.00 / 0.00m — leg 1 much better, legs 2 and 3 worse.
  Worse still, the suite went **red at 648/650**: a car ordered at a block centre
  overshot the road and parked *inside* the block footprint, 12.7m from centre where the
  test wants ≥14m, because the terminal approach depends on the old floor to stop short.
  All three are reverted; the tree is baseline and green.

  **The combination was then run and is the worst of the lot.** All three planner fixes
  plus waypoint-capture-with-dwell: leg 1 improves to 24.1s, legs 2 and 3 go to 32.6s and
  24.9s against a 15.9 / 18.0 baseline, and the suite falls to **645/650** — the two
  block-centre assertions still red, plus a shut-street leg, an obstacle-avoidance check,
  and, worst of all, lane discipline on the response at **20% over the centre line**
  against a project baseline the docs treat as a sensitive regression indicator. So the
  sequencing theory — that capture would work once cars arrived at a holdable speed — is
  **tested and wrong**. All four are reverted; the tree is baseline and green at 650.

  A useful by-product: that 20% reading proves the lane-discipline metric is **alive**.
  Worth knowing because at baseline the same check now reports **0 of 818, 0%**, where
  PROGRESS.md cites 9% in six places and the check's own comment at
  `smoke_test.gd:4519` says "this is not zero: a car coming round a corner is over the
  line by definition". Its bar is `wrong * 5 < samples`, so 0% and 9% are
  indistinguishable to it and it cannot tell you which you have. The likeliest reading is
  simply that **9% is a stale figure** and the response drive genuinely improved at some
  point — 0% is better, not worse — but the number in the docs should not be trusted as
  the current baseline, and the check would be worth tightening now it has headroom.

  **Diagnosed, August 2026: the car is not steering, and speed was never the constraint.**
  Two instruments settled it. First the metric was wrong: `_lane_offset` returns zero
  inside a junction box (`in_x == in_z`), so every "deepest into the oncoming lane"
  figure above measures the *exit* from a corner and is blind to the corner itself — a
  leg reading 0.00m was an unmeasured turn, not a clean one. `probe_corner.gd` now fits a
  circle to the arc the car actually describes, which can be compared against the two
  radii theory supplies. Then all five readings were taken **on the same frame**, at the
  closest approach to the corner:

  | at the apex | leg 1 | leg 2 | leg 3 |
  | --- | --- | --- | --- |
  | speed vs what the planner allowed | 11.90 / 13.53 | 9.63 / 26.00 | 8.71 / 13.63 |
  | steer angle of the lock available | **2.2° of 24.7°** | **0.9° of 26.3°** | 26.8° of 26.9° |
  | yaw wanted vs the cap | 0.16 / 1.18 | 0.05 / 1.45 | 1.53 / 1.61 |
  | steer point | 2.0m, **2° off the nose** | 4.6m, **1° off** | 3.6m, 101° off |
  | is it past the corner? | **yes** | **yes** | **yes** |

  The car is **obeying** the planner on every leg and going slower than allowed. The yaw
  cap is never reached, so `max_lateral_accel` is not the limit either. On two of three
  legs the car applies **under 3 degrees of lock** at the point it is closest to the
  corner. It is not being prevented from turning; it is not trying.

  The cause is the fifth row. `_update_autopilot` steers at
  `_agent.get_next_path_position()`, and that point is **past the corner on every leg** —
  which from the car's seat looks 1-2° off the nose, so `heading_error` is nearly zero,
  so `steer_input = heading_error * steer_gain` is nearly zero. The car drives straight
  at a point on the far side of the bend and arcs across it. Measured arcs: **12.29m,
  8.02m and 10.61m against the 4.44m its steering could describe.**

  This is why four rounds of speed fixes changed nothing: they were all treating a car
  that arrives too fast, and the car arrives *slow enough and does not turn the wheel*.
  The fix belongs in the choice of steer point — clamp it to the sharp bend when one lies
  within the lookahead, rather than letting it run past. Two caveats for whoever takes
  it: the circle fit spans a 16m zone and so blends in the straights either side, which
  inflates the absolute radii (the comparison between them is sound, the absolutes are
  an overestimate); and leg 3 does reach full lock, so there is a second, smaller story
  there about *when* the lock arrives rather than whether.

  **The fix works and is not yet shippable.** Bounding the steering lookahead — project
  the car onto its path, then aim a fixed arc length ahead, classic pure pursuit — does
  exactly what the diagnosis predicts. Steer angle at the apex went from 2.2° and 0.9° to
  **full lock on both legs**, and the three legs went from 42.5 / 15.9 / 18.0s to
  **18.6 / 22.2 / 20.8s** — 19% quicker overall and, more tellingly, no 42.5s outlier.

  It also breaks other things, and the failures move as the lookahead floor is tuned
  rather than clearing:

  | `steer_lookahead_min` | suite | response lane | what fails |
  | --- | --- | --- | --- |
  | 4.0 | 646/650 | 9% | traffic drive-off 20/22, damage ordering, block-centre pair |
  | 6.0 | 647/650 | **17%** | damage ordering, block-centre pair |
  | 8.0 | 647/650 | 13% | traffic move-off, damage ordering, block-centre on-road |

  Two lessons in there. **Snapping the aim to a path vertex stalls cars** — the nearest
  vertex is often *behind* the car, so the lookahead is spent getting back to it and the
  point returned sits level with the bonnet: measured, a car crawled home at 1.8 m/s
  against a 12.0 limit and never parked, and four of twenty-two ambient cars never pulled
  away. Interpolating along the path instead fixes that completely and is what the code
  above does. And **too short an aim suppresses acceleration**: `turn_factor` reads
  heading error as a reason to slow, so a near aim turns every kink in the path into a
  reason not to accelerate.

  All of it is reverted; the tree is green at 650. What survives is one small piece that
  is right on its own merits: `_climb_kerb` now refuses a landing that is not
  `CityGrid.standable`, so a car sent at a block centre can no longer climb the kerb into
  a building footprint.

  **Attempted again, August 2026: four failures down to one, and two of the three
  stragglers turned out to be tests that had never measured what they claimed.**

  - **The damage-ordering check was comparing two turn-round scrapes.** It starts the car
    yawed 180 *away* from the wall, so the 60m run-up was spent turning round: the long
    trial billed **54.8m from the wall, 7.4m from where it started**, having never
    reached the obstacle. Both trials therefore hit at the same 9 m/s and the ordering
    came down to which scrape was worse — it passed on luck, and any steering change
    flipped it. Faced at the wall, both trials land 3.7m from it at **10 and 25 m/s**
    (£133 against £315). Fixed and kept, independent of the steering work.
  - **The block-centre check encoded the pre-kerb world.** Measured along that block, the
    building is **0-9m**, the pavement ring **10-14m**, the carriageway **15m+**. A car
    ordered at the block centre now correctly mounts the kerb and stops at the building
    line around 12.8m — which is the verb the player asked for, working. The check now
    asserts `CityGrid.standable` and >10m rather than on-a-road and >14m: same guarantee
    (it never gets *inside*), updated for the fact that a pavement is somewhere a vehicle
    may now legitimately be. Fixed and kept.
  - **What is actually left is one check**: `20 of 22 traffic cars drove off`, against a
    bar of 21. It is **deterministic — 20 every time, three runs of three** — and it is a
    slow start rather than a stall: all 22 are on a road and all 22 are still moving at
    25s, but two fail to clear 3m in the first 5s. In isolation the same measurement
    gives **22 of 22 under both the bounded and the unbounded aim**, so it depends on the
    suite's context — most likely a player vehicle the earlier tests left parked where it
    blocks two cars pulling away. That is the one thing to chase next, and the way in is
    to print each car's displacement and `is_yielding` at frame 300, which the check
    currently throws away in favour of a bare count.

  **It shipped.** `_steer_point` + `_closest_on_path` + three `steer_lookahead_*` exports
  are in `Vehicle.gd`, the suite is green, and `probe_corner.gd` measures **60.4s against
  a 76.4s baseline with all three legs at full lock** where the old aim managed 2.2
  degrees. The traffic straggler resolved on the lookahead floor: at 4.0 two ambient cars
  circled (**2.4m and 2.8m of net displacement in 5s at 2.9 m/s**, against a fleet minimum
  of 13.9m), at 6.0 they clear it at 5.7m and 8.8m. That floor is not arbitrary — too near
  an aim turns every kink into heading error, and `turn_factor` reads heading error as a
  reason to slow.

  **Two costs, stated rather than buried.** Response lane discipline reads **16%** over the
  centre line against a baseline that varies 0–9%; inside the check's 20% bar, but worse.
  And the two cars that were circling still travel less far than the fleet minimum did.

  **Nothing in the suite pins this fix, and three attempts to write a check all failed
  vacuously** — the sabotage agent caught every one. The first took the hardest lock over a
  whole journey and caught the standing-start pivot (33.0° of 33.0° available, which is
  only possible at zero speed). Gating at 4 m/s moved the loophole to 4 m/s, because lock
  saturates at low speed. Sampling inside a junction above 6 m/s moved it to 6 m/s, with
  `hardest` (28.9) exceeding `available` (28.7) — proof the two are read a frame apart.
  Worse: **reverting the fix no longer reproduces the fault in the suite's scenario**, the
  corner check reading 8.9 m/s / 5.6m circle sabotaged against 8.8 / 5.5 restored, nothing
  like the documented 2.2° and 12.3m. A check cannot be seen to fail against a fault that
  will not appear. If someone tries a fourth time: assert on the **median** lock across
  junction samples rather than the max, so one saturated frame cannot carry it, and express
  it as a fraction of `available` read on the *same* frame. `probe_corner.gd` is the
  evidence in the meantime.

  **Picked up again, August 2026, and the instrument was the answer rather than a fix.**
  Two play sessions produced 37 records, **21 of them with nothing in front** — so not
  the queueing fault. Three of those read identically: on a road, on the floor, **full
  throttle, zero speed**, `turning round: false`, and a trail that shuffles back and
  forth over five to eight metres. Reading the code against them turns up two real
  structural defects:

  - `_update_reverse_latch` arms on `distance < turn_round_range`, and that distance is
    to the **final destination** while the heading error it is given is to the *steer
    point* a few metres ahead. The three cars were 45.6m, 46.0m and 124.9m from their
    destinations, so the latch was structurally unable to fire — two of them by under a
    metre. The export's own comment believes the distance is to "whatever point is
    currently being aimed at", which it has not been since the bounded-lookahead fix.
  - `_update_escape` counts a car as stuck on `absf(forward_speed) < 0.3`, and a car
    shuffling back and forth is never stationary, so `_stuck_time` resets for ever. The
    black box already knows better — it measures progress toward the aim and says so in
    its own comment — which is the only reason these records exist. **The game detects
    the fault and does nothing about it.**

  **And staging all three came out clean**: `Game/probe_stall.gd` replays each record's
  exact start, heading and destination, and every car arrives — 16.1s, 13.8s and 5.2s,
  the latch never needed. Which is this section's oldest lesson arriving again, so it was
  not fixed on a theory. What every stalled record *did* have was something within 7m,
  and the log recorded neighbours by **range only** — no bearing, and no line at all for
  what the car was in contact with. Three readings that matter enormously (wedged against
  a vehicle, wedged against scenery, or trouble entirely of its own steering) were
  indistinguishable.

  So the instrument was fixed instead: `StuckLog` now prints a bearing per neighbour and
  a `touching:` line off `get_slide_collision_count()`.

  **The first shift through the new instrument settled it, and corrected the diagnosis
  above.** Five records, and every one of them is touching **road mesh and nothing else**
  — `RoadNS_1`, `RoadEW_3`. Not a vehicle, not scenery, not a kerb. Two of the three
  readings the instrument was built to separate are therefore dead: the car is not wedged
  against anything, and the trouble is entirely its own. Bearings back it up — only two
  neighbours anywhere near dead ahead, the rest off to the sides or behind.

  And the second half is a **correction to what is written above**: `_update_escape` is
  *not* failing to arm. Four of the five records carry an escape timer of 0.55-0.85 and a
  speed of -0.5 to -5.3 m/s — the car is reversing under the escape, repeatedly. The
  reason that was misread is that the record printed `turning round: false`, and
  `is_turning_round()` reports only the reverse **latch**; the escape reverses just as
  hard and had no field of its own. The record now prints `escaping:` beside it, and
  `Vehicle.is_escaping()` exists for that reason.

  So the live fault is **not** that recovery never fires. It is that the escape fires,
  backs the car up, the car drives forward on the same failing approach, and it repeats:
  the trails shuffle 7m west and 7m back east, or rock between two points and stop.

  **Then a fifth attempt was built on that and reverted, and it is the most instructive of
  the lot, because the reasoning was wrong three separate times.**

  - *"The latch is gated on distance to the destination, and these cars were 45-153m
    out."* **False.** `move_target` is the current **waypoint**, not the destination —
    the record prints both and they were read across. Those three cars were 14.4m, 12.5m
    and 35.4m from their aim, comfortably inside the 45m gate. The latch was never
    prevented from arming by distance; what stops it is the *heading* condition, because
    the bounded-lookahead steer point sits a few metres ahead and so is nearly always
    within a couple of degrees of the nose.
  - *"Escalate on `_failed_escapes`."* **Cannot fire.** That tally resets whenever the car
    exceeds 0.3 m/s, and a car shuffling seven metres clears it easily — the same
    instantaneous-speed trap the escape itself has, one level up. An escalation built on
    progress instead was written, measured, and came out **byte-for-byte identical** to
    baseline, because waiving a distance gate is irrelevant when the heading condition is
    the one failing.
  - *"Journeys are failing."* **They are not.** `Game/probe_journeys.gd` drives 24 seeded
    cross-district journeys. At a 45s budget it read 17/24 and 13/24, which looked
    damning; at an honest 120s budget it reads **23/24 and 24/24**. The budget was the
    failure. A corner-limited car crossing 260m simply takes longer than 45s, and the
    first cut of that probe was measuring its own patience.

  What survives is the instrument and the metric. `probe_journeys.gd` is kept, and the
  number on it worth watching is **escapes fired** — not arrivals: 55-78 per 24 journeys,
  which is a great deal of shuffling for a fleet that does, in the end, arrive. An A/B of
  the escalation against that metric was mixed (patrol 69 → 55, engine 64 → 78), which is
  not a result, so it was reverted like the four before it.

  **A further seven records, 12 August**, and they sharpen it slightly: all seven touching
  road or pavement and nothing else, all seven with nothing ahead — and **five of the
  seven had no recovery running at all**, neither latched nor escaping. That is the case
  neither mechanism can see: the escape wants near-zero speed and a car circling has
  plenty, while the latch wants a large heading error and the bounded steer point sits a
  couple of degrees off the nose almost by construction. So the car goes four seconds
  without closing on its aim while both safety nets sit quiet, which is a more specific
  target than "it shuffles" and the one to aim any sixth attempt at.

  The honest state: cars **do** get where they are sent; they sometimes shuffle for
  several seconds first, and the black box quite rightly records it. That is a
  slowness-and-ugliness fault, not a never-arrives one, and anything attempted next should
  be measured on escape count with `probe_journeys.gd` before it is believed.

  **The sixth attempt (August 2026) diagnosed the mechanism completely, built a fix that
  wins the fleet metric by half, and reverted it for breaking two guarded behaviours.**
  Everything below is measured; attempt seven starts here, not from the code.

  *The diagnosis, now settled.* All 42 black-box records from real play were batch-parsed
  against the pure-pursuit capture bound — a fixed point at distance L and bearing a is
  reachable only when **L >= 2R sin(a)**, R being `wheelbase / tan(33°)`: 4.44m for the
  patrol car, 5.10m the ambulance, 6.87m the engine (which owns 17 of the 42 records, at
  aim distances of 6-14m — demands its geometry cannot answer). `probe_orbit.gd` then
  staged the states cleanly and a per-frame trace (`PROBE_TRACE=1`) closed it: the shuffle
  is a **kerb-bounded multi-point turn that loses its gains**. The latch reverses until
  the nose is 55° off, releases, and the full-lock forward arc drifts sideways by
  R(1 − cos 55°) — 1.9m on the patrol, 3m on the engine — which does not fit the
  half-carriageway available, so the car stops dead on the kerb face. The blind escape
  then reverses ~4m on a timer (throttle −1 for 1.0s), the forward arc fails identically,
  and the cycle repeats — while **both safety nets are structurally blind to it**: the
  escape wants |speed| < 0.3 and a shuffling car has plenty, the latch wants 115° of error
  to a steer point that sits near the nose by construction. On an **empty** street the
  baseline machinery completes every staged case, including a 20m dead-behind turn; the
  pathology needs traffic or kerb context, which is why five prior staged reproductions
  came out clean.

  *The fix that measured, and why it is not in the tree.* Rebuilding the latch as a real
  shuttle — legs that flip direction on a 0.25s stall, steering that rotates the nose the
  same way in both phases, exit only from a rolling forward leg under 25° — plus
  converting crooked-nose escapes (>30°) into shuttles, took `probe_journeys` from **75
  escapes / 23-of-24 (engine) to 20 / 24-of-24**, patrol similar. It also: put 78 frames
  of one corner leg off the carriageway (deterministic, both runs identical — the
  post-exit drive cuts the kerbless junction mouth); broke the suite's shut-street mount
  check (0 climbs — behind a wall of vehicles the conversion turns queueing stalls into
  weaving); and cost one ambient car its drive-off. Four guards were then measured —
  junction clearance (killed the fix: 109 escapes, the shuffles live near junctions), a
  2.5m road-edge flip on the legs (fixed one corner leg, kept 35/29 escapes), a
  shut-street veto (broke the mount licence a second way), and a contact-list
  discriminator (`touching:` world-vs-vehicle, byte-identical result). Every guard traded
  one guarded behaviour for another. The suite is the arbiter; the tree is baseline and
  green at 804.

  *Attempt seven built exactly that and it shipped, same day.* `Vehicle._begin_turn` /
  `_drive_turn` / `_plan_turn_leg`: each leg of the manoeuvre is planned as a full-lock
  arc walked in half-metre samples against `CityGrid.is_road` and the map bounds before
  a wheel turns, so a leg can never cross a kerbless junction mouth or the boundary --
  which is precisely where the reactive flips went. The latch arms it (115°), a
  crooked-nose escape (>45°, not queueing, not mount/return) converts into it, it owns
  its own exit -- a rolling forward leg inside 20° -- and it abandons on caps (8 legs /
  10s) into a 3s re-entry rest so it can never own a car it cannot help. All four gates
  passed: `probe_orbit` all vehicles all cases 4.6-8.9s with **zero escapes**;
  `probe_corner` 68.4s (baseline 71.4) with **zero frames off the carriageway** and leg
  3's lane depth improved 2.33m -> 0.30m; `probe_journeys` engine **24/24 at 31 escapes
  against 23/24 at 75**, patrol 24/24 at 14; suite green including the shut-street mount
  trio. Two late findings mattered: the conversion must not fire into a shut street
  (`road_is_blocked`) because the mount licence accumulates only under 2 m/s and turn
  legs at 4 m/s starve it -- that one term was the difference between the mount fixture
  timing out and passing -- and an off-road arrival guard written for a plausible
  mechanism measured byte-identical and was removed rather than shipped on a theory.
  The suite check `_test_a_narrow_street_u_turn_completes` carries the full sabotage map
  in its comment, including what it *cannot* see (release quality -- the probes carry
  that) and the redundancy structure of what it can.

  *First contact with real play, same evening.* Five records in one session against a
  comparable-session history of a dozen-plus, and one carried the player's own F3. Three
  of the five show `turning round: true` -- the manoeuvre recorded mid-flight by a black
  box that arms at 4s of no progress, which a legitimate multi-point turn can exceed;
  noise of success, not failure. The F3 one was real: the engine wedged **on the east
  perimeter road, mid-turn** -- a turning body sweeps its half-diagonal (4.7m on the
  engine), and the leg planner's 1m rim margin let legs plan whose samples were legal
  while the rotating hull clipped the boundary wall the samples cannot see. The planner
  now refuses samples within **5m of the rim** (`_plan_turn_leg`, the sweep math is in
  the comment): the flagged case, replayed exactly via `PROBE_AT`/`PROBE_AIM` on
  `probe_orbit.gd`, went from 25.9s and seven escapes to 20.3s and three. **Still ugly,
  and honestly so**: a car pinned lengthwise at a full-height wall cannot rotate, the
  turn rightly refuses to try, and the escapes that free it take ~15s -- traced, the
  remaining time is hull-against-wall physics, not logic. Bounded now, rare
  (rim-adjacent only), and the replay is the fixture if anyone wants the last 15s. An
  arm-side rim gate was built on a theory about rest-cycle thrash, measured
  byte-identical, and reverted the same hour.

  *Instrument notes.* `probe_orbit.gd` is kept; its first cut fired nine escapes against
  an easy target because the aim was **off the map's southern edge** (the boundary wall),
  and a second aim landed inside the block ring — check aims against MAP_HALF and
  `is_road` before believing a leg. Probe legs run sequentially, so any change in one
  leg's duration shifts every later leg's **ambient-traffic phase**; probe_orbit now
  empties Traffic and Crowd first, and any probe that does not must be A/B'd
  same-session, both ways, before a difference is believed. And `probe_mount.gd`'s
  documented 43.9s is stale on the redressed map — baseline now *times out* on that
  fixture while the suite's own pinned fixture stays green, which is one more reason the
  suite, not a probe, is the arbiter.

  **Resolved, August 2026, root and all — see Game/README.md "Corner braking comes from
  the route, not the path".** The whole line of work above was chasing corners in a path
  that structurally cannot contain them: with junction-to-junction waypoints the agent's
  path ends AT the junction, and every angle the planner read out of it was the car's own
  position swinging the vector. The route annotates its aims with exact turn angles now
  (`Vehicle.turn_at_aim` / `turn_here`), the in-path scan is honest (symmetric windows,
  true-vertex start, physics-capped floor), and the suite pins it with a
  measured-both-ways check. Residuals, stated: the patrol's middle probe leg wobbles
  (3.72m lane depth on one run against 2.25 baseline — single-leg phase noise to watch,
  not yet chased); and the engine's journeys escape count read 68 on this build against
  31 on the previous one — that metric has swung 20-109 across builds with identical
  interior behaviour, it is traffic-phase-sensitive, and the one failed journey was a
  box-in by three yielding ambient cars, a traffic-deadlock shape unrelated to corners.
  Watch it across future builds rather than believing any single reading.

  The older advice, still good: go after the stragglers individually rather than by moving
  one constant — the damage-ordering check
  needs the 60m run-up to actually reach speed (measure the speed trace along it; the
  lookahead floor was assumed to be the cause and demonstrably is not, since 9 m/s
  survived every value tried), and the block-centre pair is a genuine conflict between
  that test's expectation and the kerb feature the player asked for.

  The older framing, now superseded: **something downstream is the limit** —
  the steering response, the yaw cap in `_apply_yaw`, or the waypoint capture above, which
  is the most likely candidate precisely because a car that now arrives at a holdable
  speed is a car for which capture might finally work. That combination — all three
  planner fixes *plus* capture-with-dwell — is the one experiment this line of work has
  not run, and it is the obvious next one. Whoever runs it needs to fix the terminal-
  approach regression too: the block-centre test is the tripwire.

  The older question, now answered by the above: **why `limit` bottoms out at 11.23**, given
  `sqrt(through² + 2·decel·travelled)` should approach `through` as the car closes on the
  vertex. Worth checking whether `get_current_navigation_path_index()` advances past the
  corner before the car reaches it — that would explain a limit that never gets close to
  `through`, and it is one print inside the loop in `_corner_speed_limit` to find out.
  Do that before touching any of the tuning constants again.

  **The overlay's first evidence was a false lead, and the overlay's own fault.** Two
  play screenshots showed the cyan route running *backwards* out of the bonnet to a ring
  on a crossing the car had already cleared — the classic 360 signature. It was a drawing
  bug: `NavDebug` chained every waypoint from the car's current position, including ones
  already passed, so a cleared waypoint always had a line running back to the car.
  Cleared waypoints are now dim unconnected rings. `Game/probe_route.gd` swept a car from
  30m before a junction to 10m past it and measured what `lane_route` actually hands
  back: **5 of 41 start positions** get a first waypoint that moves the car away from its
  destination, and the worst is **2.50m** — which is exactly `LANE_OFFSET`, i.e. the
  lane-keeping offset rather than a fault. The route is not the problem.

  That probe also needed its own metric fixed first: measuring "ahead" along the
  *approach axis* condemns every turn, because on a left-hander the first waypoint is
  properly 2.5m back along the incoming street and 9m up the outgoing one. It read 12 of
  41 that way. Progress *toward the destination* is the honest measure.

  Two harness notes. The first version of the corner probe used (1,1)→(1,3), (1,3)→(4,3) and
  (4,3)→(4,1) — **every one of which shares a column or a row**, so all three were
  straight runs with no corner in them, and they measured identically before and after a
  change to the corner planner. And `corner_window` turns out to make no difference at
  all across 6.0 / 4.0 / 2.5 / 1.5, which rules out the sampling window as the reason the
  angle reads shallow.
- **A shut street plus a queue of ambient traffic is still a trap.** Four cars filling a
  carriageway *and* five ambient cars piled up behind leaves the patrol car nowhere to
  reverse to. Arguably correct — that is a gridlock — but if it wants solving, the piece
  missing is the ambient fleet clearing itself faster, not more routing.
- **A car wedged behind two vehicles abreast never gives up on the street.** Measured at
  twenty seconds with nothing written off and 1.5m of ground lost. The give-up timer
  resets on every turn-round — it has to, or a journey that begins by turning round burns
  its give-ups before setting off — and a wedged car escapes about once a second, so the
  tally never builds. Holding it fixes this and breaks that; every cooling rate between
  was tried and none satisfies both, because the two look identical from inside the timer.
  What it needs is a **different signal**: something that can tell "manoeuvring to set
  off" from "flailing against an obstruction", perhaps how far the car has moved over the
  last several seconds rather than whether it is manoeuvring right now.
- **A 180° target is a steering singularity.** With the destination exactly behind, the
  heading error sits on the reverse latch's Schmitt threshold and which way the nose
  swings is floating-point noise. Harmless: the manoeuvre completes either way.

**Unspent, and still worth considering:** having the player's vehicles queue like ambient
traffic instead of swerving round obstacles. Measured at 4× less time trapped in junction
boxes (13.9s → 3.2s across a district tour) at the cost of getting past obstructions (the
staged blockade 20.5s → 37.6s). Held back only because the junction trapping it targets
has not been reported since the three fixes above.

**Do not judge a driving change by `diagnose_driving.gd`'s lane-discipline figure.** It
has read anywhere between 8% and 25% on identical code within a single session. The
suite's own bounded check is the only trustworthy reading, and anything else needs
repeated runs.

### Opening the tutorial still costs ~819ms, and the fix that claimed to remove it did not work

The five-second delay was the character scenes, and that is genuinely fixed (see the
shared animation library in `Game/README.md`). The ~819ms that remains is the vendor
town: 2.4MB of **text** `.tscn`, parsed on the click.

A threaded pre-warm was added and reported as taking it to 0ms. It did not.
`ResourceLoader.load_threaded_request` on that file comes back a **parse error every
time** -- at boot, delayed a second and a half, with the type named, from either scene
-- while the same path loads perfectly synchronously. The 0ms figure was a
resource-cache hit in a probe. Both the pre-warm and its check are gone; see the
working note below.

Two things that would actually work, neither started:

- **Re-save the town binary.** 3.0MB of text parses in 313ms where 1.2MB of binary
  loads in 7ms -- measured on the animation library, same mechanism. The trade: the
  shell *instances* the vendor scene, so the town could no longer be edited and played
  without re-running the processor.
- **Split the load across frames** rather than across threads, if Godot 4.7's text
  loader is the problem: instance the town once at boot into a hidden node and keep it.
  Costs memory instead of time.

### The interface: what the kit has not reached yet

The August 2026 restructure took the panels onto the user's UI kit and floated them into
the corners. Two items from that plan were scoped out at the time and are still open;
both are cosmetic, and neither blocks anything.

- **In-world markers are still drawn by hand.** Selection rings, the move marker and the
  incident markers out in the district are `_draw`/mesh code from phase 1, so the world
  layer and the panel layer no longer look like the same game. The kit ships a reticle
  and a selection bracket. Worth doing as one pass rather than piecemeal — the whole
  point is that they agree with each other.
- **The glyph swap is half done.** `Glyph.gd` still carries drawn fallbacks for symbols
  the kit now supplies as vectors (44 of them). The fallbacks are not dead code — they
  are what renders when a pack icon is missing — so this is a swap of the *preferred*
  source, icon by icon, not a deletion. Cheap, tedious, and easy to do wrong quietly:
  the tell is a tile whose meaning changed because the nearest-named kit icon was not
  the one the drawn version meant.

### Props that block

Street furniture is drawn into `MultiMeshInstance3D` batches with no collision, so units
walk through benches, hydrants and bus stops. They need to become real bodies once a
mechanic uses them — a hydrant an engine connects to, a bench that blocks a stretcher.

The fire service made the hydrant case concrete: an engine's hose currently runs from
the appliance itself, with no water supply behind it. A hydrant a crew must connect to
is the obvious next mechanic, and the one that would justify giving those props bodies.

Worth doing **with** whatever mechanic needs it rather than before: several hundred new
collision bodies for decoration alone would cost a navigation re-bake and buy nothing.

### Freeplay depth

Phase 16 delivered the first round — five call kinds, escalation across the shift,
a persistent best score. What the loop could still take:

- ~~**Calls that need Secure.**~~ **Closed August 2026** by the disorder call: a raised
  cordon contains a crowd that is otherwise recruiting, which is the first thing in the
  game a ring of cones has ever done. The other two ideas are still open and still good —
  a vehicle fire that spreads to a second car unless the road is closed, or an RTC where
  traffic keeps driving through the scene.
- **More set pieces.** The rescue (building fire + casualties) shipped; the shape
  generalises to anything worth two services at once — a collapse inside a cordon,
  an RTC that catches fire.
- **The rest of the mission plan.** August 2026 built the first tranche — fires with
  kinds, car fires that bill, and the gas-leak cylinder with the `Cool` verb. Four
  more were sketched alongside it; two have since shipped:
  - ~~**Public order**~~ — **shipped August 2026.** Suspects recruit bystanders unless
    an officer stands in it or a cordon goes up, sized to the roster by
    `Director.DISORDER_SIZE`. It also closed the "nothing requires a cordon" gap below.
  - ~~**Trapped casualties**~~ — **shipped August 2026.** Pinned under a fallen
    pallet, treatable where they lie, not stretcherable until a fire crew works `Free`
    (`T`) off them. The thing it added that nothing else here had is **sequence**: two
    services, one waiting on the other. See Game/README.md.
  - **Missing persons** — a search *area* rather than a point. Genuinely a new shape
    of call and the most interesting of the three, because nothing in the project
    currently models a job without a fixed position.
  - **Hazmat** — needs assets no pack on disk has. It would be signage and
    improvisation; it should wait for a pack rather than be faked.

  One thing the first tranche established and the rest should inherit: a hazard
  **scales rather than gates** (`Director.BUILDING_SIZE`'s lesson), and anything new
  must touch `Call.describe()`, `Mission._on_resolved`, `RadioLog` and `Civilian`'s
  gather/flee triage or it degrades silently. Also still owed from tranche one: the
  crowd does not yet flee a cylinder that is about to go — it was in the plan, and it
  is the one place the existing panic would do the right thing if simply told.
- **Difficulty beyond the call rate.** QUIET/STEADY/BUSY shipped and multiplies the
  director's intervals. Building fires now scale their own difficulty to the fire crew
  the career owns (`Director.BUILDING_SIZE`) — the first call kind whose *hardness*
  responds to anything. Casualty decline rates, kerbside fire growth and the
  response-bonus window are all still one setting for everyone, and the same
  scale-to-the-roster idea would fit each of them.

### A second station

Dispatch is deliberately one station, on the police forecourt. The map has since
grown to 260m, so this is now a live candidate rather than a someday: a second house
would make the drive out part of the decision. It would need
`Station` to stop being found by "nearest in the group" and start being chosen.

---

## Deliberately not on the list

- ~~**Fire-service models**~~ and ~~**proper paramedic uniforms**~~. **Both closed
  August 2026**, and the route was exactly the one predicted here: the engine's `prefab`
  in `build_vehicles.VEHICLES` (a real Town aerial, phase 21), the crew's `source` in
  `build_character.gd`, and the two portrait entries -- **no mechanic was touched**. What
  the prediction missed is that the crew also needed a third bone map, because the
  character pack ships on its own skeleton.

  **Ladder rescues** were named here as the mechanic that becomes worth building once the
  models land. The models have landed and the ladder already animates, but the mechanic is
  still blocked -- on level design rather than art: a rescue from an upper floor needs
  `CityGrid` to model addressable building floors, and buildings are footprints whose
  interiors `standable()` refuses.
- **Multiplayer co-op** and a **mod editor.** Both were real Emergency 4 features. Both
  roughly double the work.
- **Save/load mid-shift.** A shift is 5–15 minutes and the career itself already
  persists, so saving *inside* one still buys little. Revisit if campaign scenarios
  turn out to run long.

---

**Tutorial follow-ups** (August 2026, from the town migration): the teaching overlay
— step-by-step prompts gated on player actions — is the named extension point on
`TutorialDirector`; the tutorial's lawns are deliberately unwalkable (grass under
every pavement rasterised the person mesh into degenerate edges — see the README's
tutorial section) so any future content must stand on pavements, paths or roads; and
the F2 hint and mid-screen dispatch hints are simply absent in the tutorial (HUD has
no director), which the teaching overlay should replace properly.

## Working notes

**An eighth way: the check still runs, but the world moved and it is now testing
something else** (August 2026, the title card's click check). `_test_the_game_opens_on
_the_title` clicks a car and asserts the click is swallowed by the title card. Adding a
SCENARIOS button made the card one row taller, the click coordinate — derived from a
unit's world position, dead centre of the screen — landed on **PLAY**, and the menu
duly played the game. The check reddened, which was lucky; what it reddened on was four
cascading failures in two other tests, none of them near the cause. The fixture now
picks its target against the card's *actual* rect and pans the camera until a unit
stands clear, so the next button added cannot repeat it. The general shape: a check
whose target is computed from a layout will silently start aiming somewhere else when
the layout changes, and the failure surfaces wherever the consequences land.

**And the specific way a `const` truncates a check**: writing to a nested dictionary of
a GDScript `const` throws "Invalid assignment on read-only value" at runtime, which
abandons the rest of that check silently — six checks in the scenario test stopped
running and only the count showed it. `Dictionary.duplicate(true)` first. This is the
documented "a runtime error skips the rest of the check" trap with a new cause; it cost
one confused suite run to find, and `grep 'SCRIPT ERROR'` found it in one.

**A tenth: the check counts the things, not what the things are doing** (August 2026,
the menu backdrop's crew). Seven characters were placed, on the ground, in the right
spots -- and every one stood in the rig's rest pose, because `_idle` asked for
`Idle_Loop` and the retarget renames it to `Idle`, so `has_animation` said no and the
function returned quietly. The check counted bodies and passed. Kin to the ninth below:
placing a person and animating one are different claims, and only the cheap one was
tested. The check now reads `current_animation` on each of them.

**A ninth way: the check asserts that work was *requested*, not that it succeeded**
(August 2026, the tutorial pre-warm). `_check(_menu._prewarming, "and asks for the
tutorial's town while it is up")` was true, sabotage-proven, and green on every run --
of a feature that failed on every boot. Asking for a background load and *getting* one
are different claims, and only the first was tested. The tell was on stderr the whole
time and nothing reads stderr on a normal run; it surfaced only when a new boot scene
put the errors at the top of an otherwise clean console. Two lessons: an assertion about
an asynchronous operation should read its **result** (`load_threaded_get_status`), and a
performance claim measured in a probe wants re-measuring in the real path -- the probe
that "proved" this one was reading its own cache.

**A seventh way for a check to be worthless: it never visits the fault** (August 2026,
the tutorial's stranded ambulance). The drive-home check is a real drive — buys an
ambulance, orders it to the station from the shout, samples 963 frames — and it stayed
**green** through the entire two-sheet navmesh fault, including the sabotage run that
reproduced it. Nothing was wrong with the assertion: the car it drives starts on the
carriageway, and the strand only happens to a car that has parked beside a kerbside
casualty and snapped onto the pavement sheet. A journey check proves the journey it
takes, and says nothing whatever about the journeys it does not. What caught it was a
*sweep* — every drivable point on the mesh, does it reach the station — which is the
shape to reach for when the fault is "somewhere in this space", not "on this route".

**A fault with no symptom the game can show you** (August 2026, the duplicated
animation library). Every check was green, every character animated correctly, and
eleven scenes were each carrying a private 3 MB copy of the same 43 clips — five
seconds to open the tutorial, two thirds of a second per mission spawn. Nothing in the
suite could have caught it, because nothing was *wrong*: the game was slow, and slow is
not a state an assertion about behaviour ever asks about. It surfaced only when the
delay was treated as a fault and put under a stopwatch — load, instantiate, add, first
frame, each timed separately, then the same run with the resource cache pre-warmed to
attribute what was left. That second run is what made it certain rather than plausible:
5,770 ms → 27 ms with nothing changed but the cache. Performance regressions want the
same discipline as behaviour ones, and the check that now guards it asserts a
*structural* fact (one library instance, and it has a path) rather than a duration —
timings are too machine-dependent to assert on, structure is not.

**Two checks off one measurement pass are not two witnesses.** The sabotage run for the
above reddened both new checks, but they read the same two dictionaries built in a
single loop, so a fault in that loop takes both down together. They do measure distinct
properties — instance identity and resource path — and the sabotage put a real fault in
the assets rather than in the fixture, so both are honest. Worth remembering when a
sabotage report says "2 of 2 red": count the independent *paths to the evidence*, not
the checks.

**A freed object compares equal to null — a check failed on the exact behaviour it
existed to confirm** (August 2026, from the bus-collision wreck check). The assertion
was `wreck != null and not is_instance_valid(wreck)`: once the wreck was correctly
freed, `wreck != null` evaluated **false** (GDScript's `==` treats a freed instance as
equal to null), so the check reddened on success and stayed green on nothing. Two probes
of the feature passed before the assertion was suspected — the feature was never broken.
The pattern that survives: latch a `had_wreck := wreck != null` **before** the free, and
never read `x != null` on a reference that may have been freed since it was taken —
`is_instance_valid` is the only honest question there.

**A fourth way for a check to be worthless: an under-provoked scenario** (August 2026,
from the missing-child recruiter exclusion). The assertion was fine, nothing else
supplied the result, and the quantity was not capped — the *mechanism under test simply
never ran in the check's window*. The staged suspect's recruit clock latches to a full
9 s in `_ready` and the check waited 4 s, so the exclusion being tested was never
reached, and deleting it changed nothing. Kin to the saturated scenario but earlier in
the chain: saturation stops the *measurement* moving, under-provocation stops the
*mechanism* running. The fix is the disorder test's own trick — lower the interval
(`recruit_interval = 0.5`; the code deliberately honours a post-spawn lowering) so the
window actually contains the behaviour. The same incident hid a second fault: a
sabotage cycle that edited the file twice restored from a backup taken *after* its
first deletion, so the exclusion vanished from the tree behind a verified md5 match and
a green suite — green precisely because the check was under-provoked. The agent
brief now requires backups strictly before the first edit of a cycle and diff-verifies
restores against the pre-cycle copy.

**A sixth way: the check draws its subjects from the constant it tests** (August
2026, from the tutorial's flat-furniture check). It enumerated manholes by walking
`TutorialMap.FLAT_FURNITURE`, the same array the rule is written in — so a sabotage
that emptied that array emptied the check's own subject list, and the red came from
its `flat > 0` guard rather than from fourteen solid manholes. A red for the wrong
reason is worse than a green, because it looks like proof. Name the subjects
literally, independent of the thing under test. The tell was the numbers: `0 solid
of 0` where the fault should have read `14 of 14` — which is why a sabotage report
must quote its measurements, not just its verdicts.

**A fifth way for a check to be worthless: the probe point is blocked for a
different reason** (August 2026, from the tutorial's "not through the living rooms"
check). The assertion was fine, the scenario was provoked, the mechanism ran — but
the coordinate chosen to test "grass under a house is not a floor" sat over a
*driveway*, which is excluded ground under a separate rule. So it read as blocked
whatever the burial rule did, and a sabotage that skipped burial entirely left it
green. Kin to the redundant payer: two independent mechanisms produce the same
reading, and the check cannot tell which one it is watching. The fix is a
coordinate the *other* rule does not touch — found by sweeping for samples with a
building collider and a grass tile overhead and nothing else, then picking one that
measurably moves (5.25m short healthy, 0.00m sabotaged). The same cycle found a
`> 100` polygon bound sleeping through a mesh halved to 198 from 386; bounds set
"comfortably above zero" are bounds set nowhere.

**A `>= floor` score assertion can be satisfied by a different payer** (August 2026,
from the shed-load scoring check). `score delta >= 60` stayed green with the whole
Debris scoring arm deleted, because the response bonus alone is 100. Not vacuous, not
over-determined, not saturated — a **redundant payer**: two independent sources feed the
measured quantity and the bound only needs one. The fix is the disturbance test's
pattern: assert exact equality against the deterministic sum (`DEBRIS_POINTS +
RESPONSE_BONUS`), which the sabotage then reddens at 100 ≠ 160.

**"The fire engine keeps getting stuck on junctions as it is not mounting the kerbs"**
— reported from play, 13 August, and the second half of it is wrong in a way worth
keeping. `Game/probe_wedge.gd` drives the appliance round three junction turns and reports
the climb gate's own terms:

- Two of three legs **never arrive** in 45s: 407 and 506 frames under 0.3 m/s, six and ten
  escapes fired. The complaint is real.
- `climb_escapes` is **unreachable**. It needs 2 and peaks at **1** on every leg, because
  an escape moves the car and `_update_escape` zeroes `_failed_escapes` the instant speed
  exceeds 0.3. The stuck-car route into the kerb climb has therefore never once fired.
- **Opening that gate changes nothing.** A no-progress route (the black box's own test,
  which a shuffling car cannot fake) was built and measured **byte-for-byte identical**.
- Because the cars are **not against kerbs**. They are held behind another vehicle for
  **294 of 407** and **326 of 506** of their stuck frames; and where something *is* in
  front, `_climb_kerb`'s third test — clear ground once risen — correctly refuses, because
  the obstruction is two metres tall. It is another car.

So the fix the report asks for is not a fix, it is a **design decision**: should an
appliance on a shout mount the pavement to get past a queue? Real ones do. It is also
exactly the thing `climb_escapes` was tuned to prevent, because gated loosely the climb
put 423 of 2473 frames off the carriageway on a single corner. If it is taken, the gate
should be *being on a shout and held*, not *being stuck* — a different question with a
different answer, and `_blocker` and `_held_time` already exist to ask it.

**The design decision was taken — "yes, on a shout and held up" — and it shipped**, in two
halves, because the first half alone is a trap.

`Game/probe_mount.gd` is the fixture it needed and `probe_wedge.gd` was not: a straight
street clear of a junction, a wall of **three** vehicles abreast, an appliance behind it.
Three, because `_passing_line` finds a way round one every time and two made the result flap
between 0 and 21 mounting frames on a decimetre of spacing. An **appliance**, because a
patrol car is small enough to squeeze through the same wall.

**Going up**, each term forced by a measurement:

- The licence is `road_is_blocked(move_target)` plus crawling, **not** the blocker latch and
  not `_held_time`. `_held_time` only counts frames where no passing line was found at all
  and peaked at 0.15s; the latch peaked at 1.88s against a 2.50s bar, because swinging the
  nose takes the wall out of the 2.4m corridor faster than the timer fills. Signed speed,
  not `absf` — reversing away at 6 m/s is not progress.
- **It is forgotten at half the rate `_cooled` uses.** `road_is_blocked` is a snapshot and it
  flickers as a wedged car shuffles: only 397 of 1409 crawling frames read as blocked, so at
  the double rate the timer peaked at 2.33 against a 2.50 bar and the manoeuvre never came
  due. Being blocked is a property of the street, not of one frame.
- The aim is laid out **along the route, not off the bonnet**; with the nose version it came
  back on-carriageway on both sides every time and no mount ever began.
- `mount_shift` must clear the carriageway *and* `off_road_margin`. Measured by stepping
  outward from a stopped appliance the edge is between 5 and 6 metres, so 5.4 read as road
  and 7.0 works. `standable` is not the test — a road is standable.
- The mount is a **latched manoeuvre with its own clock**, like `_escape_time`. Recomputed
  per frame it cancelled itself by working: turning towards the kerb unlatches the blocker
  that licensed it.
- **`_clear_of_junctions()` is the most important term.** A junction mouth is off the vehicle
  mesh with *no step on it*, so a car mounts onto flat tarmac, off its route. Without it the
  junction leg went 76.7s → unfinished in 150. With it, all three legs are byte-identical to
  baseline.
- `is_avoiding` is **not** a useful term: it neither fixed the junction case nor left the
  shut-street case alone.

**Coming back down** — `_returning` / `_return_line()`, and the half that took the longest to
understand. From up on the pavement the navigation agent's nearest reachable point is the
carriageway the car *just left*, on the **near** side of the obstruction: measured, 555 frames
off the carriageway, 161 of them turning round, driving back into the wall and mounting again.
The agent cannot be asked this question; the car has to be steered forwards, past the
obstruction, and put down. Two things that look right and are not, both measured:

- **Deciding it at the end of the mount.** A mount ends within `mount_arrived` of its spot,
  three metres short of a seven-metre offset — still over a road tile — so the test said
  "already on the carriageway" and the car drifted off immediately afterwards. Coming down is
  a *state of being off the carriageway*, watched for every frame.
- **Capping the recovery speed.** A fire engine has no business doing 35 km/h along a footway,
  but capped at `mount_speed` the cornering factor holds it at 2.69 m/s, the window expires
  with it still up there, restarts, and a 40.1s journey does not finish in sixty seconds.
  Exempting the manoeuvre from the arrival slowdown was tried alongside and moved 2.67 → 2.69.

Measured, appliance, wall of three:

| fixture | without | with |
|---|---|---|
| long journey past the wall | **never arrives in 60s** | **43.9s**, 5 climbs |
| short hop 16m past the wall | 33.3s | 44.3s (47.4s with the recovery switched off) |
| three junction turns | 76.7 / 33.3 / 57.0s | identical to the metre |

The short hop costs time on a fixture where the manoeuvre is not needed; that is the price,
and it is paid against a case that otherwise never finishes at all.

**What the sabotage pass established, which matters for anyone extending the checks.**
Disabling the mount reddens all four assertions with no collateral. Disabling *only* the
recovery reddens exactly one — "steers itself back down" — because the agent does eventually
get the car off the pavement in that fixture; "finishes the journey" is over-determined with
respect to the recovery and only goes red when every route down is removed. A third
assertion, "ending on the carriageway", was written and **deleted as vacuous**: it snapshotted
`CityGrid.is_road()` on whichever frame the loop exited and read true even with the car
stranded 23m short. Bounding the off-road frame count does not discriminate either — a
healthy run spends *more* frames up there (296) than a sabotaged one (201), because the
steered recovery is a deliberate excursion and the broken version mills about.

Both probes are kept. `probe_wedge.gd` distinguishes "wedged on geometry" from "queued behind
traffic"; `probe_mount.gd` is the only fixture here that shuts a street, and takes
`PROBE_UNIT`, `PROBE_SHORT`, `PROBE_WALL`, `PROBE_WALL_SHIFT`, `PROBE_NO_RETURN`,
`PROBE_MOUNT_AFTER` (absurdly high switches the licence off cleanly) and `PROBE_PATIENCE`.

**Specialists: what shipped, and what it left behind.** The doctor is the first
unit that is a specialist *within* a service rather than a service of its own, and the
mechanism (`Person.speciality`) is deliberately narrow — it gates what treatment achieves,
not which verbs appear. One follow-up, and one thing worth knowing about the generators:

- **Running two generators in one shell command hangs.** `build_portraits.gd` chained ahead
  of `godot --headless --path . --import` produced no output at all and sat there until it
  was killed; run alone it finished in under a minute. Both windowed generators were run for
  this increment (`build_vehicles.gd`, then `build_portraits.gd`) and the map deliberately
  was **not** — player vehicles are not instanced in `Playground.tscn` at all, and the only
  vehicle properties baked there belong to ambient traffic, which this did not touch. That
  is measured, not assumed: every scene's checksum changed, but only because Godot randomises
  resource ids on pack.
- **`speciality` does not feed `_build_abilities()` yet**, on purpose: the doctor adds no verb,
  and a hook with no caller gets deleted around here. The **hazmat team** is the specialist
  that will want one — firefighters who can work inside a `Hazard`'s harm radius without
  taking damage, which is the medical-side mirror of the foam/water split and reuses
  `Hazard` and `Person.hurt()` as they stand.

Two further medical ideas were costed and not taken: **treating en route** in the ambulance,
and **a second hospital or bed capacity** — both are new machinery rather than configuration.
The cheap ones that remain are pure config now that `needs_doctor` exists: a cardiac arrest
(savage decline, short fuse), a collapse inside a crowd that physically obstructs the
stretcher run, and a fall from height (casualty plus `trapped`). Three from the same cheap
tier shipped in August 2026 — the bus-scale RTC (`bus_rtc`), the shed load (`shed_load`,
first obstruction call, new two-service `Clear` verb) and the drunk collapse (`drunk`,
first call dispatched on hidden information) — see PROGRESS.md and the README sections.
Two more followed the same month: **weather shifts** (FOG/SNOW states, the SHIFT'S OWN
roll, wet collision weights) and the **missing child** (`missing_child`, the first call
the player searches — unmarked wandering child, marker on the last-seen report). A
future polish candidate recorded from that build: the child wears an adult outfit at 0.7
scale because no child mesh exists; the Town pack's SchoolBoy/SchoolGirl *outfits* could
be retargeted onto the humanoid rig via `Rigs/synty_bone_map.tres` (the Starter
treatment in `setup_retarget.gd`) if the silhouette ever matters more.

**An unexercised path, recorded rather than removed.** `Unit.can_reach()` is the
layer-aware half of the group-move slot validation, and in every scenario staged so far
`CityGrid.standable()` already rejects everything it would — the sabotage agent removed it
alone and nothing in the suite moved. It is kept as defence in depth, because `standable`
is a coarse grid test and the layer question is the honest one, but **no check currently
exercises it on its own**. If a slot ever turns out standable-but-unreachable in play, that
is the scenario this needs.

**A third way for a check to be worthless: a saturated scenario.** August 2026, and it is
the hardest of the three to see. Two containment checks in
`_test_a_disorder_call_grows_until_it_is_contained` asserted that a suspect count did not
grow while an officer stood in it. Both passed with the containment code deleted — and
they were not vacuous (the assertion is fine) and not over-determined (nothing else
supplies the result). The scenario had simply capped the quantity being measured: the
group hit `max_group` during the *previous* phase, after which `_update_recruiting()`
returns at the cap before it ever consults `_is_contained()`. The count could not move
whichever way containment behaved.

The diagnostic that found it was neither of the two usual ones. It was **removing the cap
that pins the measurement while leaving the fault in place** — at which point the group
grew 4 → 8 and the check went red immediately. The repair is headroom plus a guard: the
cap was raised, and both checks now assert `held < max_group` alongside the result, so
they can never again pass for want of room to grow.

Anything picked up from here should follow what the rest of the project does:

- **Two checks aborted partway for months and the suite read green throughout** — found
  August 2026, fixed, and worth keeping because it is the sharpest example of the trap.
  `_test_the_fire_service_fights_fires` threw `Invalid access to property 'active' on a
  previously freed object`: an extinguished fire frees itself, so reading `active` on it
  is an error, and *the error was the success case*. `_test_dispatch_puts_a_unit_on_the_forecourt`
  threw on `get_global_rect()` of a null row, because `_dispatch_row` scanned
  `panel.get_children()` while `DispatchPanel._build_row` parents each row to an inner
  grid — the rows are **grandchildren**, so that helper had returned null *every time it
  was ever called*, and the click-through-the-real-interface path it existed to cover had
  never once been exercised.

  A runtime error inside a check silently abandons the rest of it, so both simply stopped
  short. **647 → 650** on the fix: three assertions had quietly not been running, and one
  of them was the only test of the dispatch panel's click path. Both were then put
  through the sabotage ritual, since a check passing on its first-ever execution has
  earned no trust — `return` at the top of `_on_row_input` reddens the click check alone,
  and zeroing the douse rate in `ExtinguishOrder._work` reddens the hose check plus eight
  siblings that all measure the same quantity.

  The lesson for next time: the count is the only witness, and it is a *weak* one here.
  These two cost three checks out of six hundred, which is invisible drift — nobody
  notices 647 where 650 was due. **Grep the run for `SCRIPT ERROR` from time to time**;
  it is the only signal that separates "all checks passed" from "all checks that still
  run passed".
- **A third specimen of the same trap, August 2026 — and it was found by the count.**
  `_test_a_cylinder_going_off_takes_the_street` read `hazard.active` after the blast, and
  `Incident._finish()` frees the incident, so the check raised on its very first line and
  abandoned the other three. **677 → 673**, reported green. What made it findable this
  time was noticing the *number* had fallen rather than reading the failures, which is
  the habit worth keeping: the four visible FAILs were contamination from an unrelated
  cause, and chasing them first would have wasted the session. Take outcomes off the
  `resolved` signal, into an `Array` box — GDScript lambdas capture ints by value.
- **Two new checks failed to fail, in two different ways.** Both from the same tranche,
  both caught by `godot-check-sabotage`, and they are worth separating because the fixes
  are nothing alike:
  - **Under-provoked scenario.** The CONTROLS-chip check selected one patrol car, whose
    tiles fit one row — so reverting the widening it was written for changed nothing it
    could measure. The assertion was fine. *A scenario that cannot provoke the fault is
    no better than an assertion that cannot see it*, and only the sabotage ritual tells
    them apart. Fixing it (select everything, which is the real worst case because
    `available_abilities()` returns a **union**) immediately exposed a live bug: a mixed
    box-select had been putting the chip under the bar all along.
  - **Two satisfiers, one assertion.** "On the hose the cylinder cools" asserted only
    `heat < before` — and a hazard sheds heat on its own, at exactly the rate that
    satisfied it over the measured window. Stubbing the hose out entirely left it green.
    The fix is not a tighter number but a **staging that removes the other satisfier**:
    leave a fire burning beside the cylinder, so heat can only fall if water is landing
    on it. Prefer that to a tolerance whenever the scenario allows it — a bound has to be
    re-tuned every time a rate moves, a staging does not.
- **A third way to fail to fail: an assertion that is true when the feature is absent.**
  August 2026, from the HUD restructure. `_test_the_score_strip_reads_and_pauses` ended
  `_check(not paused, "and resuming thaws it again")` — and `not paused` is trivially
  true when the button under test never paused anything. The sabotage that gutted
  `ScoreStrip._open()` reddened the pause assertion above it and left this one **green**,
  identically to the healthy run. It now carries the pause result in
  (`_check(froze and not paused, ...)`), so it asserts the *transition* rather than a
  reading taken afterwards.

  Worth separating from the two entries above because the tell is different: this check
  had a scenario that provoked the fault and an assertion that could see it, and it still
  could not fail — because the *post-condition it measured was the default state*. The
  general rule: when a check reads a state after an action, ask what that read returns if
  the action did nothing. If the answer is "the same thing", the check is inert. Pairing
  it with the precondition is usually the whole fix.

  Also from that pass, a note about sabotages rather than checks: two of the three faults
  specified for the panel-overlap invariant **missed their assertion geometrically** —
  widening a bottom-docked panel can never intrude on a central rect, however wide it
  gets, so it went red on three *other* assertions while the target stayed green. A red
  on the wrong signal proves nothing. Read the assertion's actual subject before choosing
  where to break the tree.
- **A fourth way, and the nastiest: green *by contamination*.** August 2026, found by
  the sabotage agent while proving the Escape rebind. `_test_escape_closes_the_shop_before_it_pauses`
  asserts "and left the pause menu alone" — and under the sabotage that broke the guard
  it stayed **green**, while the assertion beside it went red.

  It was not vacuous, and that is what makes it worth recording. A probe in a clean tree
  showed the fault *does* reach it (`screen=PAUSE paused=true`). Inside the suite it
  could not, because the same fault had already left the tree paused several checks
  earlier — so this check's Escape press *resumed* instead of pausing, and
  `not paused and screen != PAUSE` read true. The check was measuring a district the
  fault had already broken, and the wreckage happened to look like health.

  Distinguishing this from a genuinely inert check needs a probe, not a re-read — the
  three earlier specimens above are all visible by inspection, and this one is not. The
  fix is the same shape as the third: **carry the entry state into the verdict**
  (`_check(was_clear and not paused and ...)`), so a contaminated tree reports an honest
  red instead of a false green.

  The general lesson: **a check that runs late in a long suite is only as trustworthy as
  the checks before it.** When a sabotage produces a big cascade, treat every green
  downstream of the first red as unverified rather than as evidence.
- **A new asset needs `--import` before the game can see it, and the failure is silent.**
  August 2026: a cart icon was drawn for the buy button, the SVG sat correctly on disk,
  and the button showed nothing. Icons are loaded behind `ResourceLoader.exists(path)` so
  that a missing glyph costs the *picture* and not the control — which is the right
  behaviour and completely invisible, because the button still worked. The tell is no
  `.import` file beside the asset and nothing in `.godot/imported/`.

  Same family as the `class_name` rule already in CLAUDE.md, but the symptom is the
  opposite: a missing class is a wall of parse errors, a missing texture is *nothing at
  all*. Anything that guards an asset load with `exists()` should have a check asserting
  the asset actually arrived, or the guard hides the bug it was written to survive.
- **Do not assert on a value the player is allowed to change.** August 2026, caught by
  the check itself on its first run. The music bed was reported as too loud, the default
  was lowered, and a check went in asserting the music bus sits well under master — read
  straight off `AudioServer`. It failed at 16.5 dB, because the *settings file* still held
  the previous default and a saved setting rightly overrides a shipped one.

  The check was wrong, not the game. A live bus level is a fact about somebody's save, and
  a player who turns the music up has not broken anything. The fix is to assert the
  **shipped default** by applying it and reading the result back — which happens to be
  the stronger test anyway: sabotaging `set_music_volume()` to do nothing collapses the
  measured gap to 0.0 dB, so the check cannot be satisfied by echoing the constant it
  reads.

  Generalises to every setting: volume, shift length, call pace, time of day, weather.
  Assert the default and the apply path, never the current value.
- **Beware a saved setting shadowing a changed default.** Same incident, the user-facing
  half: lowering `MUSIC_DEFAULT_DB` changed nothing audible, because `settings.cfg`
  already had a `music` key from a previous run. A default only applies to somebody who
  has never had the setting written. Anything shipping a changed default has to decide
  what happens to existing saves and say so, rather than assuming the new number takes.

  Related: `HSlider.step = 0.05` **rounds a default up**. -18 dB is 0.126 linear, which
  the slider stored as 0.15 — so the bed played ~1.5 dB louder than the constant claimed,
  and the constant was not lying, the control was.
- **A sabotage can break a helper the check itself calls.** August 2026, spotted by the
  sabotage agent. Stubbing `ShopPanel.card_button()` to return null reddened
  "it lights the two cards the prompt named ([])" — but the check *builds its expected
  list* by calling `card_button()` too, so the empty result is equally consistent with
  "the spotlight lost its targets" and "the check's own lookup returned null".

  A cousin of the shared-constant trap already recorded above, but it does not announce
  itself as a mismatched number: `[]` is what you would see either way. The tell is
  structural — the check's probe and the code under test share a symbol. The diagnosis is
  the same as for the constant case: redden the behaviour by a different route and see
  whether the check still notices. Here another cycle had already done so, pointing the
  spotlight at the wrong controls with `card_button()` fully intact, which is what
  actually earns that assertion its meaning.
- **An ideal fixture is not a test of a real path.** August 2026, the sharpest example
  this project has produced. `an ambulance drives home from the shout without jamming`
  teleported the car onto the drivable point nearest the shout, zeroed its velocity and
  faced it down +Z before ordering it home — and passed green for months while the black
  box filed eight records about that exact drive. Started at the positions the records
  actually contained, 3 of 12 attempts never arrived.

  The tell is that the fixture *constructs* a state the game cannot reach on its own. Where
  a check has to place something, ask where the game would have put it — and if there is a
  log of where it really ends up, use those coordinates rather than a clean one.
- **A "measured, made no difference" comment is scoped to what it was measured on.** The
  kerb-climb gate carried a comment saying a no-progress route through it had been built
  and measured byte-for-byte identical. True — for cars queued behind other vehicles, which
  is what that investigation had. It read as a closed question and was not: for a car
  wedged on a kerb with nothing in front, the same change was the fix. Record what the
  measurement covered, not just what it concluded.
- **Run the suite before handing a new check to the sabotage agent.** August 2026: a
  winding check went from parse-check straight to `godot-check-sabotage`, and it was
  *already red* on the healthy tree. The agent worked it out — the sabotage appeared to
  *fix* a check — but it burned a full cycle and the report has no vocabulary for
  "already red on arrival". A parse check says the file loads; only a run says the check
  is right. The gate is cheap next to four suite runs.
- **A check on geometry has to read the geometry.** Class, AABB, position and material all
  survive a mesh being wound backwards, and a backwards-wound flat marker is *invisible*
  in play. Godot's front face is clockwise seen from the front, so a triangle facing +Y
  gives a **negative** y from `(v1-v0).cross(v2-v0)` — the opposite of the obvious guess,
  and worth verifying against `SurfaceTool.generate_normals()` or a front-face raycast
  before trusting either polarity.
- **Some guards cannot be checked by their consequences.** August 2026: a fullscreen call
  is guarded against headless runs, and the natural assertion — that the headless viewport
  does not resize — is unfalsifiable, because Godot's headless display server has no window
  and `window_set_mode` is a silent no-op. Removing the guard reddened nothing. The fix was
  to make the guard *report its decision* (`_apply_fullscreen()` returns whether it reached
  the display server) and assert that instead.

  Generalises: when the thing being prevented is invisible in the environment the suite
  runs in, no assertion about the environment can see it. Give the code a way to say what
  it chose.
- **A one-shot config script is a landmine, and `setup_project.gd` is the one here.** Its
  `MAIN_SCENE` constant said `Playground.tscn` for months after the menu became the boot
  scene, so re-running it — which is advertised as safe — silently un-did that. It was
  caught only because the script prints the previous value first. Before running any
  "safe to re-run" configuration script, read its constants against what the project
  currently is, and prefer scripts that print what they are about to overwrite.
- **If the risk is a mis-wired control, press the control.** August 2026: a check named
  "RESET CAREER opens a confirmation" and then called `ask_reset_career()` directly.
  Sabotage pointed the card's button straight at the wipe and the check stayed green — the
  one thing that could break was the one thing never exercised. Calling the method tests
  the method; only `pressed.emit()` on the found button tests the wiring.

  Same family as the ideal-fixture entry above: both are checks that avoid the real path
  and then claim to cover it.
- **An assertion that mixes fixed chrome with variable content needs to know the chrome,
  and usually cannot.** The first structural check on the settings card compared its height
  against "sections stacked minus the tallest" — and failed on a *correct* card, because
  the card's chrome (241px) coincidentally equalled the two smaller sections combined.
  The form that works measures a *relationship the fault changes*: a tabbed card's height
  follows the tab shown; a flattened one's does not. No pixel budget, nothing to re-tune.
- **One unexplained red, August 2026 — keep full suite logs.** A run printed
  `1 check(s) failed of 639` and then went green 18 consecutive times, twice under a
  restored tree in the sabotage agent's own runs. The FAIL line was lost to a `tail`,
  so there is no record of *which* check it was and no reproduction. The denominator
  was right, so nothing was skipped by a runtime error; the fault, if it is one, is a
  check that is timing-sensitive rather than a check that never ran. If the suite ever
  comes back red for no reason, **do not re-run it until the log is saved** — the
  summary line alone is worthless, and losing the FAIL line is what makes this entry a
  note instead of a fix.
- **Re-run the generators after touching them**, and `build_map.gd`, `build_minimap.gd`
  and `build_portraits.gd` need **a window** — headless is the dummy driver and they
  fail silently, writing an empty city or a blank PNG.
- **Every new check must be seen to fail.** Revert the fix, watch it go red, put it
  back. Several checks in this project passed with their fix deleted; two of them
  because the thing they excluded had already been cleared from the map by the time
  they ran. Phase 15 added another specimen: a "calls open apart" check that could
  never fail because the board's own grouping forbids the thing it measured — replaced
  with the constants invariant that can.
- **Measure the fault before fixing it.** Every handling complaint so far was reproduced
  headlessly and quantified first, which twice showed the first diagnosis was wrong and
  once showed a fix doing nothing at all.
- **Freeplay must stay opt-in, and the map must stay quiet.** Most of the suite is
  written against a district with nothing burning on it plus incidents the tests spawn
  themselves. The director does nothing until `begin_shift()`, and any change that
  ships an incident with the map or lets the director start on its own will break
  dozens of checks at once — there are checks for exactly both.
