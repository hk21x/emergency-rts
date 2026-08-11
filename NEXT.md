# What is left to do

Follow-up work, in the order it is worth doing. `PROGRESS.md` is where things *are*;
this is where they are going.

**Everything on the August 2026 roadmap has shipped except one half of one tier.**
Phases 16 (the world reacts), 17 (audio), 18 (game framing) and 19 (the fire
service) are done, as is the career economy — which was phase 20's economy half,
pulled forward. What remains of the roadmap is **20's other half: campaign
scenarios.** Everything else below is a gap rather than a plan: things that are
missing and would each stand alone.

Two of them are worth reading before picking anything: the crowd never repopulates,
and the economy only ever goes up.

---

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

### Campaign scenarios — the last of the roadmap

The freeplay director produces *rolled* shifts. What the game has never had is a
**designed** one: a scripted scenario with its own spawn list, objectives and par
time, picked from the title screen. The phase-5 `Mission` machinery already does
win/lose on a single shout, and the director's placement helpers are reusable for a
scripted timeline, so this is largely authoring rather than building — 3 to 5
scenarios as data. It is also where the fire service earns its keep: a warehouse
alight with people inside is a scene worth designing rather than rolling.

### The crowd: refilled, but still orderly

**Fixed in August 2026** — `CrowdRefill` puts a shopper back on the pavements every thirty
seconds, up to the size the map was built with and no further. See PROGRESS.md.

The two companion pieces it unblocks are still open, and both are cheap now the crowd
can refill:

- **Onlookers becoming casualties** — a spreading fire catching someone who stood
  watching too long. The mechanism already exists; it is the same swap the collapse
  uses, aimed at a civilian who is too close rather than one chosen at random.
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

  Next attempt should keep the interpolating `_steer_point` and go after the three
  stragglers individually rather than by moving one constant — the damage-ordering check
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

- **Calls that need Secure.** The Disturbance uses Apprehend; nothing yet *requires*
  a cordon. A vehicle fire that spreads to a second car unless the road is closed,
  or an RTC where traffic keeps driving through the scene, would make Secure part
  of the score rather than a flourish.
- **More set pieces.** The rescue (building fire + casualties) shipped; the shape
  generalises to anything worth two services at once — a collapse inside a cordon,
  an RTC that catches fire.
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

- **Fire-service *models*.** The service itself shipped in August 2026, but POLYGON City
  has no appliance and no firefighter. The engine is the pack's **van** body repainted
  (phase 21 — it was the patrol car's hull before that, which read as a saloon) and the
  crew are police models in the same palette. A style-matched fire pack would replace
  both without touching a mechanic: the engine's `prefab` in `build_vehicles.VEHICLES`,
  the crew's `source` in `build_character.gd`, and the two portrait entries. Ladder
  rescues are the mechanic that would then become worth building.
- **Proper paramedic uniforms.** Same reason. Paramedics wear police blues and are told
  apart by their service colour everywhere in the interface.
- **Multiplayer co-op** and a **mod editor.** Both were real Emergency 4 features. Both
  roughly double the work.
- **Save/load mid-shift.** A shift is 5–15 minutes and the career itself already
  persists, so saving *inside* one still buys little. Revisit if campaign scenarios
  turn out to run long.

---

## Working notes

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
