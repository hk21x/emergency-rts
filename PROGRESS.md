# Project progress

An Emergency 4–style RTS demo built in Godot 4.6.3 on Synty POLYGON assets.

This is the status document — what exists and what it cost. `NEXT.md` is what is still
to do. `Game/README.md` is the technical reference: how each system works, and the traps
found along the way.

---

## Where things stand

| Phase | Status | What it delivered |
| --- | --- | --- |
| 0. Foundation | **done** | RTS camera, click selection, navmesh pathing, arcade vehicle |
| 1. Unit framework | **done** | Unit / Order / Ability, multi-select, control groups, command bar |
| 2. Personnel | **done** | People on foot, animation, two navmesh layers, boarding vehicles |
| 3. Incidents | **done** | Fire that spreads, casualties that decline, work orders |
| 4. Transport | **done** | Collect → hospital delivery, closing the casualty loop |
| 5. Mission | **done** | Objectives, win/lose, clock |
| 6. Presentation | **done** | Minimap, objectives panel, fire and smoke particles |
| 7. City assets | **done** | Police cars, ambulance and uniformed officers in play |
| 8. City & roads | **done** | 130m district; the roads *are* the vehicle pathfinding graph |
| 9. Civilians | **done** | Crowds on the pavements, traffic on the roads, both reacting |
| 10. Handling & detail | **done** | Corner braking, lane discipline, lightbars, opening doors |
| 11. Interface | **done** | Command panels, rendered unit avatars, incident pills (docked bar until Aug 2026) |
| 12. Calls | **done** | A call board: incidents grouped into jobs with addresses |
| 13. Roles | **done** | Hard specialisation — the "right unit" for the job |
| 14. Dispatch | **done** | A station with a finite roster, and units that go home |
| 15. Freeplay | **done** | A director that opens calls, a score, an end-of-shift debrief |
| 16. The world reacts | **done** | Crime loop, vehicle fires, civilian collapses, traffic pulling over, onlookers |
| 17. Audio | **done** | Siren, engine note, fire crackle, dispatch radio, city bed — all synthesised |
| 18. Game framing | **done** | Title card, pause, persisted settings, restart and quit-to-title |
| 19. Fire service | **done** | A third service: appliance, crew, hose reach, water, building fires |
| 20. Structure | **half** | The career economy shipped; campaign scenarios are still to author |
| 21. Feel & consequence | **part** | Weather, time of day, radio log, debrief — plus the driving faults found from play and fixed |

The fire service is **fully dressed** as of August 2026. The engine is a real appliance —
PolygonTown's fire truck, with a working ladder and its own hose nozzle in the crew's
hands — and the crew are a real firefighter and paramedic from the POLYGON City Characters
pack. The swap cost exactly what this note predicted (the crew's `source` in
`build_character.gd` and two portrait entries) plus one thing it did not: a third bone map,
because the pack ships on its own skeleton.

Explicitly parked: **multiplayer co-op**, a **mod editor**, and **save/load**
(a shift is 5–15 minutes; there is nothing yet worth saving mid-shift).
The first two were real Emergency 4 features; both roughly double the work.

### Since the plan (August 2026 polish)

The phases are done; what has landed on top of them, in order:

- **Lights and siren** — both run automatically from the moment a vehicle is sent
  until it arrives, plus `J`/`K` manual toggles on every vehicle, a recorded siren
  through a spatial speaker, and tiles that show the manual state. The siren went from a
  synthesised two-tone to a real recording in August 2026; the placeholder stayed on
  disk as the fallback, and the swap taught that looping is a per-format property the
  MP3 importer leaves off, which no check for "a sound is loaded" would ever catch.
- **The map ships quiet** — no scripted shout; the district idles until `F2` opens
  a shift and the director starts producing calls.
- **Fires have kinds, and one call can hurt you back** — a fire is now `BIN`,
  `VEHICLE` or `BUILDING`, each with its own plume, rates and spread, instead of four
  call sites poking the same four fields inline. A car fire **bills** any vehicle
  parked in it, straight into the repair economy that already existed, so where you
  leave the appliance costs money. And a new **gas leak** call puts a pressure cylinder
  beside a small fire: it heats while the fire burns, the board counts it down through
  "warming" / "venting" / "about to go", and at the limit it goes — damaging what is
  near, turning bystanders into casualties, and throwing fresh fires. It is beaten two
  ways, hose the cylinder (`Cool`, the twelfth verb) or put the fire out first, and
  choosing between them is the call. The command bar went to **two rows** to hold the
  new tile.
- **Group orders spread and queued ones are visible** — ordering ten units somewhere no
  longer stacks them on one coordinate; slots are laid out per navigation layer, assigned
  nearest-first, and validated against the unit's own mesh before use. And every order in
  a queue now has a marker, where only the one being driven at did.
- **Your own people can be lost** — a blast or a resisting suspect hurts the crew, and a
  firefighter who goes down leaves a casualty on the pavement wearing their own kit. Send
  a paramedic and they come back; do not and the career loses the unit it paid for. They
  still count against the roster while they lie there, so there is no replacing them in
  the meantime.
- **A shift you walk out on still costs you** — abandoning fails the calls you left and
  sweeps outstanding repair damage onto a persisted house account, which then comes off
  the top of future earnings. Quitting a bad shift used to be strictly better than
  finishing it.
- **Arrests are walked in** — Escort moved from the patrol car to the officer, so a
  cuffed suspect is taken by the arm and marched to the car rather than appearing inside
  it from five metres away. The car no longer has to reach them, which means an arrest
  can happen anywhere feet go. And it holds **two** now, not one.
- **A crowd can turn** — a disorder call draws bystanders in for as long as nobody is
  standing in it, so arriving *is* the intervention and arriving late costs you the size
  of the job. It is also the first thing in the game that has ever required a **cordon**:
  a ring of cones contains it as well as an officer does. Sized to the officers owned,
  the same way a building fire is sized to the crew.
- **Someone can be pinned under the load** — a trapped casualty can be treated where
  they lie but cannot be moved until a fire crew cuts them free (`Free`, `T`). It is the
  first call needing two services **in sequence** rather than at once, so turning up in
  the wrong order costs time rather than being a matter of taste.
- **Fires want the right stuff put on them** — each kind names an agent, and the wrong
  one does nothing. A car fire burns fuel, so it costs **foam** from a second tank that
  only the station refills: a hydrant is a water main, and the fourth car fire of a shift
  sends the appliance home. And an **electrical** fire is the first call in the game that
  the fire service cannot answer and the police can, because dry powder is what a patrol
  car actually carries. The board says what each fire wants, so none of it is a memory
  test.
- **You can see the water** — a hose stream now leaves the firefighter and lands on
  what they are fighting, built out of the particle pack's rain streaks since it ships
  no water. It is driven by water actually *delivered*, not by the order running, so an
  officer stood in front of a building fire achieving nothing shows nothing — which is
  the same lesson the mechanic already taught, said out loud for the first time.
- **The district doubled** — 260m, twenty-five varied blocks, two parks, two parking
  lots, four tower families, on deliberately irregular road spacing.
- **The minimap became a control surface** — left-click looks, right-click orders
  the selection, and the view is drawn as the camera's capped ground footprint.
  (The left-click that "already worked" turned out to be silently dead — see the
  pack() lesson below.)
- **Road discipline for everyone** — left turns round an apex on the driver's own
  side of the crossroads instead of chording the oncoming lanes, and pedestrians
  walk the pavement graph, crossing only at the painted zebras.
- **The interface wears the icon pack** — pack icons on every tile and marker with
  the old drawn primitives kept as fallback, keycap icons on a controls card
  sectioned by function behind a visible CONTROLS chip, and a command bar that
  provably cannot grow.
- **The suite runs in ~20 seconds** — `--fixed-fps 60` decouples the headless loop
  from the wall clock; it was ~9 minutes of real-time pacing before.

### Phase 16 — the world reacts (August 2026)

The first tier of the post-plan roadmap: turning the systems the 15 phases built
into visible game variety, with no new asset risk. Everything reuses an existing
seam.

- **The crime loop** — a fifth incident: a `Suspect` causing a Disturbance, worked
  with the police mirror of the casualty journey. `Apprehend` (officers, scores with
  Treat) takes them into custody, `Escort` (scores with Collect) puts them in the
  back, and driving into the station books them in for 75 points. *(Escort moved
  from the patrol car onto the officer's feet in August 2026 — see below.)* No
  timer — an unattended disturbance just stands there while the response bonus
  drains. The call board gained `Kind.CRIME` and a shield mark.
- **Medical calls take a civilian** — the director swaps a crowd member for a
  casualty where they stand, so a collapse is somebody who was just there. Falls
  back to thin air only when nobody qualifies.
- **Vehicle fires** — a car alight against the kerb of a street, wearing a
  script-free wreck prefab that burns away with the fire. Still extinguisher-honest.
- **Traffic pulls over for blues** — a driving response within 16m sends ambient
  traffic to the kerb until it passes. Parked responders are driven around instead;
  a direction-blind version stalled the district against the parked shift.
- **Onlookers** — a body or a suspect draws nearby civilians along the pavement
  graph to a respectful standoff, facing the scene; tiles inside a raised cordon are
  refused; fires still scatter rather than draw. The crowd disperses when the scene
  clears.
- **The shift escalates** — call intervals shrink to 55% across the shift and the
  simultaneous-call cap rises by one past the 65% mark.
- **The best score survives** — `user://records.cfg`, written when beaten, read at
  start; the debrief says `NEW BEST` or `BEST <n>`. Deliberately the project's
  first save-shaped code (phase 18's settings file later joined it).
- **The stretcher run** (play feedback, same month) — collapses happening where
  civilians actually stand broke the old ambulance-side Collect: the vehicle mesh
  is the carriageway, so a casualty deep on the pavement or in a park sat forever
  outside a parked vehicle's reach. Collect moved onto the **paramedic** as
  `StretcherOrder` — fetch the stretcher from the ambulance, wheel it out, lift
  them on, wheel them back aboard — and crime calls were pinned kerbside (with a
  longer Escort reach) so the patrol car could always pull up beside its suspect.
  *(That reach is gone: August 2026 moved Escort onto the officer for exactly the
  reason the stretcher run moved onto the paramedic.)*
  The ambulance still carries and delivers; it just no longer drives at people.

### Phase 18 — game framing (August 2026)

The demo got a front door. Taken ahead of phase 17 (audio) by choice — a title, a
pause and settings are what make it feel like a game the moment it opens.

- **A title card over the living district.** Not a separate scene: an overlay in
  the hand-authored HUD, so the crowds and traffic idle behind the name, the main
  scene stays `Playground.tscn`, and the generated map is untouched. While it is
  up, nothing underneath hears the mouse (a full-rect stop) or the keyboard (the
  menu swallows keys in `_input`) — an F2 that opened a shift under a menu would
  be a shift the player never asked for. `PLAY`, `ENTER` or `SPACE` drop in.
- **Pause on `P`.** One flag — `get_tree().paused` — and everything PAUSABLE
  freezes together: vehicles, fires, casualty decline, the shift clock, the call
  ages. The menu itself runs `PROCESS_MODE_ALWAYS`, which is what lets it keep
  listening. Resume, restart, settings, quit-to-title, quit.
- **Settings that persist** — master volume (the bus, ready for phase 17) and
  shift length (5/10/15 minutes, pushed onto the director) in
  `user://settings.cfg`, the second save-shaped file (the career later made it
  three).
- **Restart and quit-to-title** — both stand the shift down via
  `Director.abandon_shift()`, which switches scoring off *before* freeing the
  scenes so the calls they leave close silently instead of counting as cleared.
  Restart then opens a fresh shift; quit-to-title leaves the district idling
  behind the card.

### The career economy (August 2026)

The economy half of roadmap phase 20, pulled forward on play feedback: the free
starting shift felt wrong once returning units vanished into it. Now nothing is
free and nothing vanishes.

- **The map ships empty.** The generator places no units; a check pins the count
  at zero. A new career opens with **£2,000** — deliberately tight: one patrol
  (£600), one officer (£200), one ambulance (£900) and one paramedic (£250) with
  £50 to spare.
- **Money follows the points, 1:1.** Every positive scoring event — £50 a fire,
  £100 a delivery, £75 an arrest, plus the response bonus at the same 0.25–1.0
  speed weight — pays the same number in pounds into the station's purse. Losses
  cost score only: fining a struggling career into bankruptcy would spiral, and an
  empty purse is already the punishment.
- **Buying is a storefront.** The DISPATCH heading carries the purse and opens
  the **shop** (`ShopPanel`): one card per type with the rendered portrait, the
  price, what the unit is actually for, and a BUY sized for a finger; clicking an
  unowned dispatch row opens it too. (The first pass was per-row chips on the
  bar — play feedback killed them within a day — and *their* first pass, themed
  Buttons, grew the bar to 191px: the third spring of the bar-growth trap, caught
  by the height check again.)
- **The invisible fleet** (play feedback, next morning) — bought units "never
  appeared". They did: behind the station's roof. The dispatch slots sat on the
  building side of the yard, and a pick-ray probe from the opening view showed
  everything at z ≥ +0.5 swallowed by the block — bought, alive, auto-selected,
  invisible. Both slot rows now stand street-side (z −4.2 and −1.4, each depth
  measured pickable before being chosen), and a check dispatches two units and
  demands the ray reach both. The GUI row-click path — the only door the player
  actually has — got its first test in the same pass.
- **Returning units park.** `Station.accept()` stands the unit on a forecourt
  slot (the yard grew to two rows of four) instead of freeing it — it is the
  player's property, not a token. "Available" is derived — owned minus alive on
  the map — so there is no bookkeeping to drift.
- **The career persists** in `user://career.cfg`, the third and last save-shaped
  file; RESET CAREER in settings wipes back to the starter purse.
- **The fire service slots straight in**: a new engine or firefighter later is one
  more `Station.TYPES` row with a price on it.
- The suite now *is* a career: the fixtures buy and dispatch the classic seven
  through the station, which also proved dispatched crew had no portraits (the
  generator used to assign them; `TYPES` carries them now) and that respawn
  anchors must be re-marked after placement (`_ready` runs at the origin).

### More life (August 2026, play feedback)

- **The cars stopped all being blue.** The pack paints every vehicle body off one
  shared atlas palette; the generator now folds parked cars through the Alts
  palettes (each colour is its own batch — the key already included the material,
  so variety cost a handful of draw calls), and the ambient fleet repaints its own
  body surfaces at spawn. Taxis keep their livery. **Paint must not steer**: both
  paint picks first drew from the seeded layout/routing streams and shifted a
  district the tests had proven — a stalled taxi in one case, a car off-road in
  the other. Cosmetic draws now have their own RNG streams, twice.
- **The suspect came to life.** They had been standing in a T-pose: the clip name
  trusted at spawn (`Idle_Talking_Loop`) simply is not on the rig's player, and a
  `has_animation` guard fails *silently* — a check now demands a playing clip.
  Now they pace a few metres about the scene along the pedestrian graph, mouth
  off (`Idle_Talking`, restart-looped like every one-shot), **fight the arrest**
  — the punch clips alternate while an officer's work refreshes the scuffle, no
  order bookkeeping, just heat that decays — and once cuffed they walk back to
  the kerbside spot the call opened on, which is also what keeps them inside the
  escorting patrol car's reach.
- **…and then faced the right way** (play feedback, same day). Two faults, both
  invisible to every existing check because nothing in code reads a model's
  orientation. The pacing was **backwards**: `Person.tscn` yaws its Character
  child 180° and the project's shared `atan2(x, z) + PI` steering assumes that
  yaw is there — `Suspect.tscn` shipped without it. And the swings landed on
  **thin air**: the brawl never turned to face anybody. The suspect now squares
  up to the arresting officer (handed over by `ApprehendOrder` rather than
  guessed by a nearest-officer scan, which picks wrong with two on scene), and
  two checks measure the model's own forward axis — one against travel, one
  against the officer. Sabotaged, they reproduce the report exactly: 354 of 354
  paces moonwalked, 0 of 30 swings on target.

### Solid traffic and a readable board (August 2026, play feedback)

Four faults from one play session, three of them with the same shape: something
that had been *deliberately* left loose turned out to be plainly wrong on screen.

- **Vehicles no longer drive through each other.** Traffic was on its own collision
  layer that nothing masked, so cars slid through one another — measured at **0.16m
  between two centres**. Everything on wheels now collides with everything else, and
  three rules make that affordable: traffic **gives way at junctions** in a strict
  order (nearest goes, ties by instance id — so a cycle of "after you" cannot form),
  it **re-plans when it gets nowhere** (watched as progress, not speed, because a
  wedged car shuffles back and forth forever), and it is **spaced when laid down**
  (two used to spawn 3.9m apart, inside each other for a 5m body — harmless while
  they were ghosts, and the day they were solid the physics engine flung one 600m
  out of the world).
- **Player vehicles drive around, not through.** The autopilot looks for a vehicle
  in the **corridor** it is about to sweep, then takes the overtaking side if the
  line stays on the road and has nobody in it, and otherwise holds station at the
  blocker's speed. A cone was the first attempt and was wrong: it opens with
  distance, so a car parked at the kerb 12m away counted as an obstruction and the
  patrol car crawled past its own forecourt.
- **A burning car stopped breeding.** `Fire._spread()` clones itself with
  `duplicate()`, which copies children — and the wreck was parented to the fire, so
  every spread put another car on the street. It is a sibling now, tied to the
  fire's life through `tree_exited`.
- **The board reads as a bar.** A call used to print one percentage per incident, so
  a fire that had spread six times read as six numbers in a row. Incidents now say
  what they are doing in words ("well alight", "critical"), several are counted
  ("3 fires"), and the number is drawn as a `ProgressStrip` in the call's own colour.

### Phase 19 — the fire service (August 2026)

The marquee gap, closed — in borrowed clothes. The City pack ships no appliance and
no firefighter, so both are the police models folded through the pack's **orange
palette**: the engine is the patrol car's own hull, the crew is
`Character_Male_Police` repainted, and `build_portraits.gd` learned to shoot palette
variants so the shop does not sell an orange engine off a blue photograph. Swapping
in a real appliance later is one line — the `prefab` in `build_vehicles.VEHICLES`.
Everything underneath is real:

- **A third service.** `Service.FIRE` had been in the enum since the interface phase
  and finally decides something. A firefighter offers **one verb** — Extinguish — and
  nothing else: no treating, no arrests, no cordons. The engine seats four and is
  what the hose runs from.
- **Extinguish became one verb with three rates.** A firefighter within 18m of an
  appliance works at full rate; away from it they drop to 35%, what they can carry;
  police keep 45%, the extinguisher a patrol car actually carries. Parking the engine
  at the scene *is* the job, which is what makes an appliance more than a bus.
- **Building fires**, at last. A `Fire` with `needs_hose` yields to nothing but a
  crew on a hose — an officer can stand in front of one all day and the intensity
  will not move. They start well alight and grow faster than a bin.
- **The old ban became a career gate.** The director has always refused to open a
  call the roster cannot answer; with no fire service to buy, that meant no building
  fires ever. Now it asks the *career*: the `building` kind enters the draw only once
  the station owns both an engine and a firefighter, because either alone is no use.
- **The dispatch block went to two columns.** Six types stacked in one made the bar
  185px tall and swallowed the CONTROLS chip — the fourth outing for this project's
  most reliable trap, caught by the same height check as the other three.

### Rescues, water and a soundscape (August 2026)

Three tiers taken together, each of which the fire service had just made possible or
obvious.

- **The set piece.** A `rescue` call is a building alight with casualties out in
  front of it: an engine and a crew to fight it, a paramedic and an ambulance for the
  people, all at once and all while it spreads. It is the first call the district
  produces that no single service can finish. Nothing new was needed to *hold* it —
  the board has grouped incidents at one scene into one call since phase 12 and its
  RESCUE kind has been derivable ever since; what was missing was anything that
  deliberately composed one.
- **Water.** The appliance carries a tank, drawn down by the crew working off its
  hose and refilled beside a **hydrant** or back at the station — and only while
  parked, so it is a decision about where to stop rather than a number that fills
  itself. Running dry is a real failure, not a slower one: a building grows faster
  than a crew with only what they carry can knock it down, so a dry engine has to be
  moved. The hydrants were already drawn into the street-furniture batches; they are
  now *nodes* at the same spots, which is the first piece of scenery in the project
  to earn a mechanic. The portrait shows the tank as a bar, blue while filling.
- **A soundscape**, synthesised rather than bought. `build_audio.gd` writes four
  16-bit WAVs sample by sample: a diesel idle pitched by road speed, a fire crackle
  scaled by intensity, a two-tone dispatch chirp on every call the board opens, and a
  low city bed under all of it. Every looping sound is an exact whole number of
  cycles of its own fundamental, because a buffer that ends mid-cycle clicks once per
  loop — at an engine's loop length, that is a rattle. Drop a recording over any of
  them and nothing else changes.
- Audio needed checks more than most things, because it fails **silently**: a missing
  file, an unimported one and a player nobody called `play()` on are indistinguishable
  from the code and all equally quiet. The suite asserts each stream is loaded,
  attached and running, and that the two that respond to the world — engine pitch,
  crackle volume — actually move.

### Dressed figures and a call rate (August 2026, play feedback)

- **The people in an incident come out of the crowd's wardrobe.** A suspect and a
  casualty shipped wearing the Starter pack's grey-blue mannequin — a placeholder
  standing in a city full of dressed pedestrians. Both now wear one of the seven
  civilian outfits, and when a collapse *takes* a shopper the body wears what that
  shopper was wearing: the director hands the outfit over before the incident enters
  the tree, because it dresses itself in `_ready`.
- **How often the district calls is a setting.** QUIET / STEADY / BUSY multiply the
  director's intervals (×2.0, ×1.35, ×1.0); BUSY is the pace the game shipped with,
  and STEADY is the new default, because the first thing said after a full shift was
  that the calls came too fast. The suite pins `pace = 1.0` in its fixtures — tests
  set their own intervals and must not inherit a player's setting.
- **The corner-to-corner drive is measured, not merely timed.** It had twice been the
  thing that broke on unrelated changes, because its 3,600-frame budget sat barely
  above the ~3,700 the drive actually takes. It now counts frames and reports them
  ("in 3708 of 6000 frames"), so the next slowdown is legible instead of mysterious.
- Two checks had to be strengthened after sabotage showed they proved nothing: the
  outfit hand-over passed while comparing against *the set of outfits the crowd
  owns* (with seven outfits across sixty people, every one is in there), and had to
  follow the specific shopper who vanished; and the dressing check had been
  registered after the crowd was cleared, where it silently skipped.

### Phase 21 — feel and consequence (August 2026, in progress)

The tier aimed at what a player *feels* rather than at what the game can do. Two stages
in, plus a run of driving faults that play-testing turned up and that took longer than
the stages did. **Those are resolved**: the three reported faults — a 360-degree loop on
setting off, units touring the map instead of driving to where they were sent, and orders
landing outside the district — are each fixed and each confirmed by a play session that
produced no records at all, the first clean one of the investigation.

The method mattered more than any of the fixes. All three were found by the **black box**
(`Game/StuckLog.gd`) reading real play, and none of them by a staged test: every headless
staging of "a unit gets trapped" came out clean, because none of them were traps. Three
fixes built on staged evidence in the same period — a flush kerb, a steering clamp, a
bevelled kerb — were measured, found wanting and reverted. The order to work in is read
the log, then write the probe.

- **A district whose reference could be trusted again.** Several sections of these
  documents still described the pre-fire-service game and contradicted the phase
  table at the top of this file — "audio, of which there is none at all" survived two
  months past phase 17. Fixed, along with a throwaway probe that had outlived its
  investigation.
- **The appliance became an appliance.** It had been the patrol car's own hull in a
  different paint: a saloon that the player was told was a fire engine. It is now the
  pack's **van** body — 30cm wider, 26cm taller, on a longer wheelbase — which reads
  as an appliance at RTS zoom, and which ships **rear doors** as separate meshes, so
  the crew disembark through doors that swing. The generator derives collision, ring,
  wheelbase and wheel radius from the hull's own AABB, so the only hand-measured value
  was the beacon cluster, re-measured off the van's roof rather than inherited.
- **…and it took two colour bugs down with it.** *An alt palette is a texture atlas,
  not a colour*: a mesh's UVs decide which swatch of it they land on, so one palette
  paints two meshes two different colours. `04_A` is genuinely orange on the patrol
  car, which is why phase 19 chose it — on the van it averages a flat charcoal, so the
  first build of this swap shipped a **black fire engine**, and on the crew mesh it
  averages olive, which meant the firefighters had been quietly **green** since the
  day they shipped. Nobody had looked. `02_A` is the warmest of the twelve on both
  bodies, and the appliance and the people who ride it now share one palette. The
  check that covers it samples each body's *own* UVs and asserts red leads both other
  channels — which is what tells warm from olive as well as from grey, and it
  reproduces both faults exactly when the old palettes are put back.
- **The station says what it is.** The forecourt houses all three services and now
  carries the pack's `Sign_FireDepartment` fascia beside the police one, laid out on
  the boards' measured widths rather than by eye.
- **The street has lighting, and it ships off.** 101 lamp standards were already drawn
  into the kerbside batches; their heads are now remembered the way the hydrants are,
  and the map writes an `OmniLight3D` under each. The container ships hidden — the
  same "quiet until asked" rule the director follows, since a hundred omnis at noon
  washes the pavements out — and there is a check that it does.
- The title card's subtitle had gone stale on both counts it made: the roster stopped
  being a fixed issue when the career made it something bought, and the five minutes
  became a setting.
- **The district works an hour.** DAY / DUSK / NIGHT, in settings beside shift length
  and call rate. `Daylight.gd` owns one value and derives everything from it: the sun's
  elevation and colour, the fill, the ambient, the fog, the exposure, the procedural
  sky's own four colours, the 101 street lamps, and a pair of headlamps on every
  vehicle. Dusk is the one to play — a low western sun, long shadows, the lamps already
  on and the street still perfectly readable.
- **Day is not a preset.** It is the baseline *captured from the scene on ready*, so
  the shipped map at DAY is the map as generated and every check ever written against
  it still describes what it sees. A round trip out to night and back has to restore it
  exactly, and there is a check that says so — without it, a lighting tweak could
  silently move the ground under three hundred unrelated assertions.
- **Headlamps are fitted by a watcher**, not by the station: `Daylight` hooks
  `node_added` the way `Mission` and `CallBoard` do, so a patrol car bought at midnight
  turns up with its lights on and nothing in the buying path had to learn about the
  hour. Their position comes off each vehicle's own collision box, so the van-bodied
  appliance gets them at its width and the hatchback at its.
- Two things the first build got wrong and looking at it caught: the procedural sky
  stayed **noon blue** over a black city, which read as broken rather than as night;
  and its ground half is pure white at the horizon, which put a strip of daylight
  under the skyline. Both are in the presets now.

**Play feedback, same day:**

- **The hose became a multiplier rather than the ceiling.** A firefighter on the hose
  worked at exactly the fire's own `douse_per_second`, and everyone else at a fraction
  of it — so a **building fire was eleven seconds a node**, and buildings spread, which
  made a real building call a minute of standing still holding a hose. `HOSE_RATE` is
  now 1.8, measured: 11.0s → **3.8s** a node, with a kerbside fire at 0.9s. Off-hose
  (0.35) and police (0.45) are untouched on purpose — the ask was about the *engine
  being there*, and the gap it makes went from 2.9× to 5.1×.
- **Water is charged per unit knocked down, not per second.** Per-second was the same
  thing only while the hose ran at the fire's own rate; the moment that moved, a faster
  crew started putting fires out for *less* water, which is backwards. `WATER_PER_DOUSE`
  is calibrated to what the old rate worked out to, so the tank economy is unchanged and
  stays unchanged the next time a rate is retuned.
- **Nothing said where to take an arrest.** The loop has always worked — drive the
  patrol car into the station yard and they are booked in automatically, scored and
  tallied, with a check covering it end to end — but the interface never said so. A
  suspect in the back read "aboard, en route" (to *where?*), the portrait's stats line
  mentioned casualties and not suspects at all, and a car holding one said "Standing
  by". Now both incident states name their destination, the stats line counts custody,
  and an idle vehicle with someone in the back says which yard to drive to.
- **The suite was inheriting the player's settings.** `GameMenu._ready()` loads the real
  `settings.cfg` before the fixtures can repoint the path, so a session left at dusk
  made the whole suite run at dusk with the street lights on. Caught by the check that
  noon is not lit by streetlight — written that morning, red by the afternoon, on a
  cause nobody predicted. The fixtures pin the hour now, exactly as they already pinned
  the call rate.

**"Fires are still too difficult to put out" — and the answer was none of the obvious
ones.** Four measurements, each ruling something out:

| what was tried | result at a 40-second response |
| --- | --- |
| the tank, 20× bigger | **still burning after 180s** — it ended every run above half |
| the hose rate, more than doubled (1.8 → 4.0) | **still burning after 180s** |
| two firefighters | still burning |
| three firefighters | still burning |
| **four firefighters** | **cleared in 19.7 seconds** |

A building fire spreads while the crew drive to it: at a 40-second response it is six
nodes on arrival and pinned at the eight-node cap, and one worker can only ever be at
one node. It is a **cliff, not a curve**, and it sits exactly at the appliance's own
four seats — the number the whole thing was designed around.

So the fault was never a rate. The first fix was to make the **gate** honest — a
building fire needs four, so demand four before offering one. It worked, and it was
immediately the wrong answer: a career with one or two firefighters would never see the
most interesting call in the game until it had saved up for four of the same unit.

**The fix that survived is to size the fire to the crew instead of withholding it.**
`Director.BUILDING_SIZE` scales the two things that actually decide a building fire —
how many places it can reach, and how often it tries — and `_size_to_crew()` applies it
to the plain building call and the rescue alike:

| firefighters owned | nodes | spreads every | measured |
| --- | --- | --- | --- |
| 1 | 2 | 15s | cleared in 13.9s |
| 2 | 4 | 12s | cleared in 13.7s |
| 3 | 6 | 10s | cleared in 15.6s |
| 4+ | 8 | 8s | cleared in 19.7s |

Every rung was played out headlessly at a 40-second response and every one is winnable
by the crew it was sized for. The fight stays about the same *length* while the scene
visibly grows, so hiring a firefighter changes what the district looks like rather than
unlocking a door. Past four it stops growing: the appliance seats four, and a fire that
outran a full crew would just be the unwinnable scene again in a bigger hat. The gate is
back to an engine and one firefighter.

This is also the first thing in the project to answer NEXT.md's standing complaint that
**difficulty is one setting for everyone** — the call rate could be tuned, but how hard
a given call was could not.

The 20× tank stayed: it was asked for, it is harmless, and it retires a second-order
annoyance (a spread call used to want two and a half tankfuls). But it was not the
wall, and saying so mattered more than shipping it quietly.

- **Weather, and it is not a filter over the screen.** CLEAR / RAIN, beside the hour.
  Rain thickens and cools the air on top of whatever the hour set — the two settings
  compose, so every hour has a wet version without six more rows in the preset table —
  and drops fall from a 40m box that follows the camera's ground focus.
  **The mechanical half is one number.** `Vehicle.grip_scale` multiplies both grip
  terms, and the autopilot already plans corner entry from
  `sqrt(max_lateral_accel * grip_scale * radius)` and caps yaw by the same term, so
  0.72 grip lengthens braking distances and lowers apex speeds for the player's units
  *and* the ambient fleet with no branch anywhere asking whether it is raining. Rain is
  a property of the road, not a case in the controller. Measured: the same junction
  taken at **8.9 m/s dry, 7.2 m/s wet**.
  0.5 was tried first and was wrong — junctions are 10m across and the corner planner
  is already near the limit of what a car can hold, so ordinary turns started missing
  their apex and re-routing, which reads as a broken car rather than as weather.
- **The rain's first build put glass rods over the city.** The drop box was 60m across
  and centred on a focus point ~25m from the lens, so drops spawned *between the camera
  and the district* — and a 1m streak a metre from the near plane is a bar standing over
  the whole skyline. Narrower box, smaller and fainter drops, and
  `BILLBOARD_PARTICLES` rather than `BILLBOARD_ENABLED` so a drop stays a falling
  streak instead of turning end-on. Only looking at it finds this.

**A vacuous check, found by the weather work.** `_test_vehicles_slow_for_corners`
measured the car's speed at its closest approach to a hardcoded junction at (-20, 20) —
and the route does not go near it. The car heads *east* first; its closest approach is
**38 metres**, reached at the very end while parking at 0.2 m/s. So the check sampled a
stationary car and passed `radius < 9.0` trivially. It was presumably real when written
and quietly stopped being so when the district doubled to 260m and every junction moved;
nothing pointed at the coordinate to say it had gone stale. It now finds the apex by
**peak yaw rate** — wherever the turn is, that is where the car turns hardest, and that
cannot go stale — and reports 8.9 m/s at a 5.6m radius, which matches the 9.5 recorded
when the corner-braking work first shipped. A new guard asserts the car was *actually
cornering* when sampled; under the old measurement that guard reads 0.0 m/s while its
sibling stays green, which is the whole fault in two lines.

- **A radio log**, bottom-left above the controls chip: the last four things that
  happened, fading out. The district is 260m and the camera sees about a fifth of it, so
  the call list — which shows *state*, and has to be read — leaves the player polling.
  This is the other half: **events, as they happen**. A job opening, a crew reaching one,
  a job finishing, and nothing else. Deliberately no per-unit narration and no per-service
  audio blips: a log that announced every order would be scrolling noise inside a minute,
  and a readout nobody reads costs the same screen corner while teaching the player to
  ignore it. Passive like the board — it hooks `call_opened` / `call_changed`,
  `Station.booked_in`, the director's shift signals, and watches `node_added` for
  incidents resolving. Nothing on the map knows it exists.
- **…and its headline check was vacuous**, caught by the sabotage agent rather than by
  review. The check meant to prove a crew announces its arrival *once* compared the log's
  child count before and after 120 idle frames — but `say()` trims to four lines, so the
  number it measured was pinned by the very system under test. Under a real flood the log
  read `ON SCENE | ON SCENE | ON SCENE | ON SCENE` and the check printed **ok**. A flood
  and silence are indistinguishable once the log is full. It counts lines *by content*
  now — `4 of 4` under the flood, `1 of 2` green — and the moving denominator is what
  proves the measurement is real. This is the project's second specimen of a check
  measuring something the system it tested forbade anyway, and the first one found by a
  machine.

- **A debrief worth reading.** The end of a shift used to be one run-on line of eight
  facts joined by interpuncts, in the same label the "press F2" hint uses. It is a card
  now — score and best, earned, calls cleared, **average response**, casualties, fires,
  arrests — with the rows that are only interesting when non-zero drawn faint, so a
  clean shift does not announce the nothing it lost. `Mission.summary()` survives as the
  one-line form a scripted shout still uses.
  The average response cost nothing to add: the call has recorded the age at which it
  first turned `ON_SCENE` since the response bonus was written, and the bonus is paid
  off exactly that figure. The shift was using it and throwing it away.
- **Two more vacuous checks, both caught by the sabotage agent rather than by review.**
  The debrief's average-response check asserted the mean sat "between" the two waits it
  averaged — but the scenario made one of them a **0.1-second** arrival, so a total that
  kept only the last call moved the mean by 0.05s and a sum that never divided landed
  inside the range's slack. It passed against both faults its own comment named. The
  scenario now uses two substantial waits (2s and 6s) and asserts the arithmetic mean
  itself; the same two sabotages now read 3.1 and 8.2 against an expected 4.1.
  That is the distinction worth keeping: a check can be sound and still be **under-
  provoked by its scenario**, which is repaired in the setup rather than in the
  assertion. The agent's instructions now say to compare the sabotaged run's numbers
  against the healthy run's — if they barely moved, the fault never reached the
  measurement.

- **A shift could hang for ever, and had been.** Time running out deliberately does not
  end a shift -- you finish what you started -- but that assumed every open call *can*
  be finished. A career with a paramedic and no ambulance treats a casualty to stable
  and then owns nothing that can collect them, so the call stays open indefinitely and
  the district never stands down. Measured: a four-second shift still running forty
  seconds later. The symptom was silent and had been visible the whole time in the save
  files -- **five played sessions in a row, money earned in every one, and `records.cfg`
  never written**, because not one of them ever reached a debrief. `Director` now has an
  `overrun_grace` (90s): past it, whatever is still on the board closes as failed and
  the shift ends. Generous enough that it only ever fires on a job that was not going to
  finish.

### Phase 20 finished: campaign scenarios (August 2026)

The last item on the roadmap, and the entry in NEXT.md had it right -- it was mostly
authoring. Three designed shifts (`Game/Scenarios.gd`) picked from a SCENARIOS card on
the title, each a timeline of call kinds against a par time, played by a
`ScenarioDirector` the menu creates at runtime and adds to the running district.

Almost none of it is new machinery. `Director.open_kind()` already placed all sixteen
call kinds sensibly, so no scenario knows where a junction is. `Mission` already ran
the scripted win rule and already scored a shout in freeplay's currency -- necessary
here, because a scenario runs with `scoring` off and `Mission.score` is zero
throughout. `Mission.more_to_come`, written for the tutorial's staged shout, is what
keeps a scenario from being won between its waves. The debrief modal, built the same
week, is what says the result; scenarios added one row to it, par as a margin.

The runner is created at runtime rather than shipped in the scene, because
`Playground.tscn` is generated and adding a node to it means editing `build_map.gd`
and regenerating with a window. It finds Mission and Director among its siblings by
type -- neither is in a group, and a runtime node cannot be handed an exported path.

### The interface onto the user's UI kit, then off the docked bar (August 2026)

Two moves, in that order, and the second only made sense once the first had landed.

**The kit.** The user supplied `ui-kit/` — 210 vectors, design tokens, nine-slice
margins and a reference theme — and the chrome stopped being styleboxes and became art.
`Palette.gd` took the kit's tokens to the byte, `build_theme.gd` bakes the frames into
`StyleBoxTexture`s, and the type is the kit's pairing (Rajdhani display, Barlow body),
which is most of why it now reads as the reference rather than as stock Godot. One
contrast guard had to be re-pointed rather than deleted: the kit separates surfaces with
a stroke and a gradient instead of a fill step, so the check now makes each pair **name
its separator**.

**The restructure.** The shape had not changed since phase 1 — one edge-to-edge bar
across the bottom. The user's reference layout has no bar at all, so the four blocks were
floated into corners with the city visible between them, and a main menu, a menu backdrop
scene (dusk, rain, a petrol station on fire) and an objective bar in the top-left corner
came with it.

Three things are worth carrying forward:

- **It was an anchors job, on purpose.** `HUD.gd` resolves fourteen nodes with `$` and
  the suite resolves thirty-odd path strings, so nothing was reparented and nothing was
  renamed — `Root/Bar` and `Root/Bar/Row` survive as transparent full-rect `Control`s
  with no stylebox, purely so forty paths stayed valid. Exploration said the risk was
  coupling rather than layout, and it was right.
- **Six checks describing a docked bar were replaced by one invariant that is
  stronger.** Each of the six named the neighbours it compared, so a rename made them
  pass vacuously. The replacement enumerates the panels by path — a rename fails loudly —
  and asserts no two overlap, all are on screen, the middle 40% is the city's, and no
  rect moves with the selection. All four have been seen to fail.
- **A sabotage pass found an assertion that could not fail.** "Resuming thaws the
  district" read `not paused`, which is trivially true when the pause button never
  paused anything — it stayed green through the sabotage that reddened the pause
  assertion beside it. It carries the pause result in now, so it asserts the
  *transition*. That is the second inert check this project has shipped and the second
  the ritual caught; the count would never have shown it, because it ran fine.

The one genuinely new control is `ScoreStrip`, top-right: score, fleet count, and buttons
for pause and settings. Until it existed the pause menu was reachable by pressing `P` and
by no other means, which is a menu only for someone who read the controls card.

**Then three things off the back of the first windowed pass**, all August 2026:

- **The radio log is hidden.** It read as out of place over the city. Hidden rather than
  deleted, the same way `PortraitBlock` was — it keeps composing its lines out of sight,
  so unhiding it is one word, and everything it announced is also on the call board.
- **Game speed: 1x, 1.5x, 2x**, as a button group beside pause. `Engine.time_scale`, so
  physics, timers and animation scale together and the shift clock runs fast when the
  shift does. Normal speed gets a button of its own even though only the faster two were
  asked for — two buttons that turn something on need a third that turns it off, or the
  way back is "press the lit one again", which has to be explained. The trap is that
  `Engine.time_scale` is **global and outlives a scene change**, so `quit_to_title`
  resets it or the main menu's backdrop runs at double speed.
- **The bottom edge slimmed and the corner emptied.** Command tiles came down 54 → 48
  and the block 560 → 500 wide; the dispatch rows moved into the left column under the
  roster and the bottom-right corner became a single buy icon. Two things fell out of
  that. The dispatch rows went from two columns to one — in a docked bar height was the
  scarce dimension and width was free, and in a 180px column it is exactly the reverse.
  And the **call board moved to the right-hand edge**, because the left column could no
  longer hold roster *and* dispatch *and* a board, and hiding the radio log had just
  emptied that side of the screen.

  Sized by **probe, not arithmetic**. The first cut was laid out by hand and put the
  dispatch block through three neighbours at once; a throwaway script that printed every
  panel's rect and content minimum gave the real numbers (roster 305, dispatch 200,
  commands 141 for the fattest selection) and the layout fell out in one pass. The
  specific trap: bottom-anchored offsets make the height the *difference* between them,
  so `-145..-22` reads like 145 and is 123 — the content minimum quietly won and the
  command block breathed with every selection change.
- **The Patrol/Ambulance list went, and dispatch moved onto the roster.** The block
  listing what the station holds was removed; a unit sitting in the house now shows as a
  dimmed chip at the end of the roster, and clicking it sends that unit out. This closed
  a gap between what `Roster.gd` had always *claimed* — "pale avatars are standing by,
  solid ones are working" — and what it could show, since a unit in the station is not in
  the scene tree at all. The purse moved to the top bar, and the corner cart became the
  only door to the shop. `Station.dispatch()` had no other caller in the interface, so
  moving the verb was not optional; asking first is what stopped it being deleted.
- **The roster groups by service, one line each.** It was a single wrapping flow, so a
  patrol car and an ambulance shared a row and the next ambulance began a new one — a
  shape that changed every time a unit was bought, which reads as no arrangement at all.
  Police on one line, medical the next, fire the next; a service with more units than the
  column is wide wraps within its own row and never mixes. Grouping made the panel
  *shorter* as well as wider (300×238 against 180×305), because three tight rows beat
  three ragged ones.
- **Icon-only buttons were drawing their glyph off-centre.** Godot left-aligns a
  `Button`'s icon even when there is no text for it to sit beside, and **both** alignments
  have to be set — the horizontal one alone leaves it riding high. Fixed on the cart, the
  pause and settings buttons, and the map zoom buttons.
- **Pause moved from `P` to `Esc`**, which freed `P`. The cost of that rebind is that
  `Esc` already meant cancel twice over — it disarms an armed ability and closes the
  shop — so there are now three claimants on one key and `GameMenu._input` runs *before*
  both of the others. `_escape_is_spoken_for()` is the arbiter, and the ordering is the
  ordinary one for a cancel key: unwind the innermost thing first. Sabotaging that guard
  reddens about 150 checks, because a district that pauses when the player meant "cancel"
  stays paused for everything after it.

### Real audio: UI clicks and a music bed (August 2026)

The first sounds in this project that were not synthesised. Both CC0, both curated rather
than copied wholesale, both credited in `Game/Audio/CREDITS.txt`:
**Kenney's UI Audio** (3 of its 50 sounds) for the click and rollover, and
**"Calm Ambient 3 (Lifewave 2k)" by The Cynic Project** for the bed.

Three things that were more interesting than the download:

- **The clicks find their own controls.** A `Click.attach()` helper would have needed
  calling in nine files, several of which build controls at runtime — so it is a passive
  watcher on `SceneTree.node_added` instead, the shape CLAUDE.md already asks new systems
  to keep. The narrow definition of "interactive" is the load-bearing part: a `Button`, or
  a `Control` that stops the mouse *and* has a `gui_input` listener. Without that second
  clause every panel that blocks click-through would have clicked.
- **One bus was no longer enough.** Master was the only bus and the settings slider drove
  it, which is fine until a bed plays under the whole shift — then the only way to quieten
  the music is to quieten the sirens, and the sirens are information. `AudioBuses.ensure()`
  adds Music and UI in code; master stays "the whole game", music becomes balance.
- **The bed is a mono WAV, and that is a deliberate loss.** `Soundscape._player()` casts
  to `AudioStreamWAV`, which is both why an OGG in that folder is silent rather than an
  error, and the only path whose loop points are sample-exact. MP3 loops carry the
  encoder's padding as a gap you would hear every three minutes. No vorbis encoder was
  available on the machine (the installed ffmpeg is broken — missing `libx265`), so the
  320kbps stereo original became 16-bit mono at 22050 Hz rather than a 16 MB stereo WAV.

### The tutorial points at things (August 2026)

Two changes to the proving shout, both from play feedback.

**The fire moved**, from (-25, 25) to (0, 35). The two jobs had been 60m apart on the same
street, which read as one incident happening twice; they are now 74m apart in different
parts of town, and the drive out is something to watch rather than a repeat. The spot came
from the same reachability sweep as the original — walkable to the centimetre, 6m off the
carriageway, 54m from the station — and the sweep taught something the first one had not:
**both navigation meshes live on the world's default map**, told apart by
`navigation_layers` rather than by map, so `map_get_closest_point` answers off the union of
the two and every pavement point reports as being on the road as well. The first sweep
returned zero candidates for exactly that reason. `region_get_closest_point` is the call
that can tell a kerb from a carriageway.

**And it points at the control it is talking about.** The prompt has always named the next
step — "buy an Ambulance and a Paramedic" — which is thin help when the storefront holds
eight cards a new player has never seen. A `Spotlight` node now pulses whichever control
the words mean: the cart button while anything is unbought, the two named cards once the
shop is open, the roster's standby chips once they are bought and still parked. Nothing
glows during the parts of the lesson that are about the world rather than the interface,
because a glowing panel would be pointing the wrong way at "right-click the casualty".

The design point worth keeping: **the words and the glow are one reading, not two.**
`_lesson()` works out what is missing once and records it; the prompt and the spotlight are
two renderings of that. Computing it twice is how a tutorial ends up telling you to buy an
ambulance while pointing at the fire engine — and the sabotage pass proved the checks catch
exactly that, since swapping the spotlight's branches left both prompt-text checks green
and reddened only the three that assert *which* control is lit.

### Three new bodies and a helicopter (August 2026)

The Heist pack landed and brought a SWAT van, a helicopter and a SWAT officer on **the
same rig the existing characters use** — drop-ins. Built in one windowed generator run,
`build_vehicles` -> `build_map`, because regenerating one leaves the map loading old values
silently.

- **Police van** — 2.47 x 2.41 x 6.09, six cells, £800, **zero new code**. `DISORDER_SIZE`
  runs to eight suspects at one kerb and a patrol car holds two.
- **Recovery truck** — built, awaiting the `Wreck` incident that gives it a job.
- **Air support** — 2.53 x 3.82 x 10.90, £1,800, and the first unit that never touches the
  road network.

**There is no air pathfinding, and that is the finding rather than a shortcut.** A
navigation mesh exists to route *around* obstacles; at cruise height there are none, so an
air mesh would be a second navigation system whose every query returned the straight line
`Aircraft` already flies. The real work in flight turned out to be the **vertical states**
and **where you may put it down**.

`Aircraft` is a sibling of `Vehicle`, not a subclass: `Unit`'s movement contract is five
methods and a helicopter satisfies all five without inheriting 2,400 lines of steering,
kerbs, reversing and lane discipline that mean nothing in the air. The generator already
took a per-vehicle `script`, so the seam existed; what it needed was a `drives` split, since
assigning `cells` or `tank_capacity` to a node without them is an error rather than a no-op.

**Landing is `CityGrid.standable()`** — roads, parks and the pavement ring — so a
helicopter can never be set down on a roof or in a living room, and the rule cannot drift
from the one the crowd walks on.

**Three checks of mine were wrong before the code was.** Two waits were short enough to fail
on their own arithmetic (a 24m climb at 7 m/s takes 3.4s before it travels at all). And the
landing assertion, named "not overhead", tested only the aircraft's *self-reported phase* —
sabotage showed a helicopter that jumps to GROUNDED without descending passes it while the
message prints `y 24.45`. The first repair then measured against the datum captured
*immediately before landing*, which is cruise height, so `y < datum + 1` was still trivially
true and the broken descent still passed. It measures against the ground it took off from
now, and reddens at `y 24.45 against ground 0.45`.

That is the same lesson as the tank and the crowd, in a third costume: **an assertion has to
be evaluated in a state where only the thing it names can satisfy it** — and a datum read at
the wrong moment is as good as no datum.

### The helicopter landed every time you told it to go somewhere (August 2026)

Shipped, played, and reported by the user in one sentence: *"we want it to hover by default
once taken off, as opposed to constantly land."*

`LandAbility.score()` returned **12**, and `MoveAbility` scores **0** because Move is the
ladder's floor. So Land beat Move on every right-click — and since the only ground it will
land on is `standable()` ground, which is the only ground you would ever send it to, there
was no click anywhere on the map that made a helicopter fly and hold. Flying somewhere was
unreachable through the interface while being fully implemented underneath.

The reasoning in the original comment was not silly — *"a right-click on open ground with a
helicopter selected means put down there, which is the only thing it could sensibly mean"* —
it was just wrong about what a helicopter is for. A verb whose target is **ground** cannot be
resolved from a plain right-click without swallowing Move, because ground is what Move
targets. `SecureAbility` had already met this and answered it: decline every right-click,
override `can_target`, and let the player arm it deliberately. Land is armed-only now, and
the hover fell out with no other change.

**The suite had a helicopter landing check and it could not have caught this**, which is the
part worth keeping. It called `chopper.land_at(ROAD)` directly — the method, not the verb —
so it proved the descent and the landing rule while never once asking what a right-click
resolves to. A check that reaches past the interface tests the engine and vouches for the
game. The new pair goes through `Unit.resolve()`, and is deliberately two-sided: Move is
chosen **and** `LandAbility.can_target()` still accepts that exact point, so a landing verb
that had simply broken cannot pass it.

Then sabotage found half the pair was blind anyway. `so it is still in the air after carrying
that out` waited 120 ticks — 2 seconds — and from 60m out at cruise height the aircraft needs
~1.8s to cross and 3.4s to descend, so it was airborne at the 2s mark whichever verb it
chose. It passed with the bug fully present, for arithmetic reasons. **Third time in one
function.** Waits in this project are not padding; they are part of the assertion, and the
number has to be derived from the speeds rather than picked.

### It pivoted like a sprite (August 2026)

Reported the same way, one sentence: *"the helicopter needs to gradually rotate in the sky,
rather than immediately turn to the point it's going."* `face_towards()` wrote the bearing
straight into `global_rotation.y`, so ordering it somewhere behind it turned the aircraft
through 180 degrees inside a single frame and then slid it there, already pointed. Turning
that into a **rate** is most of what makes the thing look airborne.

`face_towards()` itself had to stay instant -- it is [Unit]'s one-argument contract, and
[WorkOrder] and the stretcher orders call it expecting the unit to be looking the right way
on the next frame. The easing lives beside it in `_turn_towards()`, which cruise calls and
nothing else does.

**It still translates straight at the destination, and that is the important design
decision.** Flying along the heading would look better and would open the door to a circling
limit cycle any time the turn rate could not keep up with the speed -- a fault this project
has already paid to learn once, in a wedged car. Instead the heading eases while the
movement stays a straight line, so arrival is unconditional; the aircraft merely crabs for
the two seconds the nose takes. A speed floor (`SIDEWAYS_SPEED`, 0.3) stops it flying
backwards at full tilt during the swing, and sabotage confirmed the floor earns its place:
with the turn disabled entirely the aircraft still crossed the district and landed, nose
180 degrees wrong, with every distance figure unchanged.

**The check that guarded it was half a check.** `< 0.2 rad in 2 frames` asserts the nose does
not come round *too fast* -- and an aircraft that never turns satisfies that for nothing. The
sabotage agent noticed, and the measurement was already on the page: with `turn_speed` set to
zero it printed `0.00 rad in 2 frames` and stayed green. It is a band now, `> 0.01 and < 0.2`,
which is a statement about turning rather than about not snapping. Worth keeping as a shape:
**a check written against one failure mode tends to come out one-sided**, because the fault
you are picturing only ever pushes the number one way.

The rotors, by contrast, were only ever cosmetic: `_update_rotors()` spools with
`is_airborne()` rather than with speed, because a helicopter holding station has its blades
at full song and one on the pad has them stopped. Their check reads the blades **by node
path** so that a regeneration renaming the part reddens a check instead of quietly leaving
the discs still — and proving the parked half needed its own inverted sabotage (`wanted :=
1.0`), because a rotor that never turns satisfies "still while parked" for free.

### Water from the main (August 2026)

`Game/Hydrant.gd` with `nearest()`, the finite tank, `refill_per_second` and
`hydrant_reach` all existed — but the hose ran from the appliance, so a hydrant was a
refuelling stop. `ConnectAbility` (`P`) and `ConnectOrder` make it a supply: connected, the
tank stops draining and the crew fight off the main.

**What it changes is where you park.** The hose reaches 18m from the appliance and a
hydrant holds it at 9m, so an engine can be near the fire, near the water, or at a spot
serving both — and only the third fights a big fire without a pause to refill. Building
fires are sized to the crew you own, so the pause is the thing that loses them.

The connection **outlives the order**: `ConnectOrder` finishes the moment the line is on,
leaving state on the appliance, so the crew can be sent elsewhere while the engine stands
and supplies them. It breaks by driving away, re-derived every frame rather than trusted —
nothing announces that a vehicle has moved.

Two implementation notes worth keeping. It targets a **point**, not a thing: the hydrant
the player sees is drawn into the street-furniture MultiMesh and has no collider, so there
is nothing to click. And `ConnectOrder` is a `WorkOrder` on a *vehicle*, which is safe
because `_apply_action` guards its animation on `unit as Person` — an appliance just skips
the clip.

**This is the third vacuous assertion this session, and the worst of them.** "It never runs
dry, whatever the tank says" was written with a *full* tank — and `has_water()` is
`water > 0.0 or is_on_main()`, so the first term satisfied it and the branch it was named
for was never reached. Deleting `or is_on_main()` outright left **the entire suite green**.
The repair was in the scenario, not the assertion: empty the tank, then assert it still has
water on the main and none once away from both. With that, the same deletion reddens.

The pattern across all three: **an assertion that names a branch has to be run in the state
where only that branch can satisfy it.** A full tank, a calm crowd, a single critical
casualty — each let a check pass on the wrong term.

### Triage: the board says who is dying (August 2026)

`bus_rtc` puts three to five casualties at one junction against an ambulance that carries
two stretchers. The decision that call is built around is **who rides first** — and for the
whole life of the call the board said "4 casualties" and nothing else.

`Casualty.severity()` is a derived tier — STABLE, UNKNOWN, SERIOUS, CRITICAL — off state
that already existed: `health`, `is_stable`, `needs_doctor`, `needs_assessment`, and
whether they are already carried or aboard. **Never stored**, because a stored copy is a
second truth to keep in step. The order is a dispatcher's: anyone already on their way is
off the list whatever their health says; an unassessed casualty is *unknown* rather than
assumed well, because the drunk call exists to punish assuming; and `needs_doctor` is
critical however healthy they look, because a paramedic cannot fix them at all — they can
only hold them, and holding is not treating. The call row now reads
`3 casualties, 2 critical`.

**The sabotage found the assertion carrying the whole thing on one casualty.** The row
check was a bare `contains("critical")`. Dropping the `needs_doctor` term took the critical
count from 2 to 1 — a real under-count, the exact fault the tier exists to prevent — and
the assertion never moved, because one critical is enough to put the word on the row. It
asserts `"2 critical"` now. The general shape is one this project keeps re-learning: **a
check on a rendered string should assert the number, not the noun**, because the noun
survives almost any error in the count.

### Panic, bounded (August 2026)

The crowd fled fires "orderly to a fault" — along the pedestrian graph, crossing at the
zebras even at a run, filing away down the single best line like a queue. Panic changes
that, and the interesting part is the constraint rather than the feature.

**The bound is that panic never leaves the graph.** It changes *how* they move — running
rather than walking, scattering rather than filing — and never *where* they may go. That
was not a compromise reached to satisfy a check; `Civilian._flee_from` already carried the
argument in a comment, and it is right: a shopper who sprints into the carriageway has
swapped one incident for another, and **traffic cannot see pedestrians**, so a panicking
civilian in the road is run over by a car that never brakes. Making them scatter into the
road would need traffic to model pedestrians first, which is a separate feature.

So panic is a widened tie-break, not a different rule. Calm, the walk takes whichever legal
hop puts most distance between them and the trouble; frightened, the jitter is comparable
to a tile, so a near-best hop often wins and the crowd comes apart. Both choose *among
legal moves*. `Person.hurry` forces the run gait, because a graph hop is under
`run_distance` and a fleeing civilian would otherwise walk away from a fire.

Panic is a **reading of the distance**, not a state with a timer, so it cannot leak — step
far enough away and it passes.

Also owed and now paid: **the crowd flees a cylinder about to go.** It had fled fires since
phase 16 and stood placidly beside a hazard at 0.9 heat the whole time — the one place the
existing behaviour would have done the right thing if simply told.

**The sabotage pass corrected two things I had believed.** First, the offside assertion was
*inert on its own*: gated on `is_panicking`, it counts zero samples and passes by default
when nobody panics — the "post-condition is the default state" trap again. It asserts the
sample count now. Second, and worth recording because it was written in a comment as
reassurance: **the 7,200-sample legality sweep does not witness panic at all.** It runs with
nothing burning, so nobody panics and the branch is never entered; under a sabotage that
sent panicking civilians into the road it did not move, while this check reported 21 frames
offside and the flee-legality check 165. An unweakened check is not the same as a covering
one.

### Health on the roster (August 2026)

A thin bar under each roster chip, and two rules that make it worth having rather than
decorative.

**Only people.** `health` is a [Person] field; a vehicle's damage is a `repair_bill` in
pounds, settled when it books in. A bar under a patrol car would be a readout with nothing
behind it, so the vehicle chips never draw one — and the check asserts the vehicle's bar
stays hidden *while a person's is showing*, which a "does the bar exist" check would sail
straight past.

**Only while hurt.** A full bar under every chip is a row of green noise that teaches the
eye to skip the exact place a warning will appear. It hides at full health, the same rule
the top bar's stat blocks follow.

The honest test of whether it was worth building at all: **before fire harmed units it
would have been dead UI.** `health` moved only when a gas cylinder went off, so a bar would
have sat at 100% for entire careers. It became a live quantity the player can act on one
change ago, which is why it earns its place now and would not have then.

### Fire became dangerous (August 2026)

The most common call in the game could not hurt you. `Hazard._hurt_people()` has always
carried a complete, tested chain — crew take harm and go down, civilians convert to
casualties wearing what they were wearing — and it fired only when a gas cylinder went off,
the rarest kind in the table. `Fire._singe()` is that chain pointed at fire.

**The number that matters is 3.2, and it is chosen against `ExtinguishOrder.REACH` (5.0),
not picked for feel.** A unit working a fire closes to REACH and stands there, so a
firefighter on the hose is 1.8m outside the harm radius and never singed; one the player
walked past the fire, or parked a crew on top of, is inside it. Fire does not punish
fighting it — it punishes standing in it. That preserves the design decision that predates
the harm: `ExtinguishOrder` holds a firefighter at work range *precisely* so the fire
service stays playable, and a radius at or above REACH would make every building fire a war
of attrition against your own crew.

The check asserts the property rather than the number: it stands one firefighter at exactly
REACH and one at 1m, and requires the first to be untouched and the second hurt. Sabotage
widening the radius to 8.0 reddens it at 0.71 health, measured at 5.0m.

Onlookers catch too, but **only above `spread_threshold`** — below it a bin fire is
something people stand near; above it the fire is out of hand, and the crowd flees fires
perfectly well, so anyone still inside was caught rather than careless.

Two things the pass taught:

- **The first onlooker check could not fail for the right reason.** It asserted the shopper
  had vanished and that the incident tally had risen — but a civilian can vanish for
  reasons unrelated to fire, and the tally counts the fire itself, so a conversion and an
  unrelated resolution cancel out. It counts *casualties within 4m of the fire* now.
- **A widened radius surfaced a latent fragility in an unrelated check.** The crowd-flee
  test guarded its sampling loop with `is_instance_valid` but not the two assertions after
  it, so a civilian converted mid-check would raise — which does not fail a check, it
  abandons the rest of it and drops those assertions from the count silently. It cannot
  happen at the shipped radius; the inconsistency was worth closing regardless.

### A real fire crew, and a third rig (August 2026)

The last asset gap in the game, closed. The firefighter and the paramedic had been
repainted police for the project's whole life — the City pack ships police and nothing
else — and both `build_character.gd` and `Game/README.md` carried apologetic notes saying
so. The POLYGON City Characters pack arrived with `SK_Character_FireFighter` and
`SK_Character_Paramedic` in their own kit.

**The route was the one the docs predicted** — the crew's `source` in
`build_character.gd`, two portrait entries, no mechanic touched — **plus one thing they did
not predict.** The pack sits on a *third* skeleton: mostly Unreal-mannequin naming, but
with `Pelvis`, `UpperArm_L`, `Hand_L`, `Thigh_L` and `Foot_L` capitalised where the
mannequin has them lowercase, `head` lowercase where the mannequin has `Head`, Synty's
merged finger chains rather than the mannequin's five, and **no `Root` at all** — it starts
at `Pelvis`, and the `_ik_*` bones are IK helpers, not a character root.

Close enough to the existing mannequin map to look reusable, and far enough that it is not:
bone names are matched exactly and case-sensitively. So `setup_retarget.gd` gained a third
map, `CITY_CHARACTERS`, renaming the rig onto the same `SkeletonProfileHumanoid` the Starter
characters and the animation library already share. After that, one shared
`AnimationLibrary` drives all three rigs — the suite's own check reports **1 distinct
instance across 11 character scenes**.

Two decisions worth keeping:

- **The import targets are built by scanning the pack directory**, not by listing nineteen
  paths. The failure mode for a missed character is not an error: it imports under its own
  bone names and then *stands still*, playing nothing, while every "is it loaded" check
  passes.
- **`strings` on an FBX was not good enough to write the map from.** It found `Foot_L` and
  missed `Pelvis` entirely, which pointed at the wrong conclusion — that the pack was
  unrelated to anything already mapped. Loading the scene in Godot and printing
  `Skeleton3D.get_bone_name()` gave the real 55-bone list, and the map fell out of it in one
  pass.

The paint-warmth check needed no re-pointing: it guards the real turnout kit now instead of
the repaint trick, and passes at **+0.18** where the repaint managed +0.08. `ALT_FIRE` in
`build_portraits.gd` is gone — a real fire kit needs no palette fold.

Still asset-blocked after this: K9 (no dog mesh anywhere), water rescue (no hull, no water),
hazmat (no suits). Ladder rescue is *no longer* asset-blocked — the models and the animated
ladder both exist — but it is blocked on level design instead: `CityGrid` models buildings
as footprints whose interiors `standable()` refuses, so there is no upper floor to rescue
from.

### The settings card became sections (August 2026)

It had grown one row at a time to **~770px against a 900px viewport** — one more setting
would have reached the edge and two would have run off it. Overflow there is silent and
total: `_card()` centres the panel with no clipping, so an over-tall card draws off *both*
edges and the rows past them stop being clickable, exactly as the shop did at 964. And
nothing measured it. A settings card running off the bottom would have shipped green.

Three sections behind a tab strip — SOUND, DISPLAY, THE SHIFT — so **the card is as tall
as the tallest section rather than the sum of all of them**: 557 against 900, with room
for roughly 28 settings. `screen` stays `SETTINGS` throughout, so `_switch`, Escape,
`_settings_from` and the pause rule were untouched. Tabs are ordinary toggle buttons
wearing the kit's button art; a `TabContainer` would have been the one unthemed stock
control in the game, which is the defect the slider work was written to fix.

**RESET CAREER now asks.** It was a `DangerButton` directly above BACK with no
confirmation — one misclick from dissolving a fleet. It gets the one new screen that earns
its complexity, because Escape has to mean *no*: CANCEL is primary and first, RESET is
danger and second, so the affirming press is deliberately not where the finger already is.

The tidy underneath: `_slider()` and `_choice_row()` replaced ~115 lines of copy-paste, so
each of the pending settings is now a line rather than a block; the card panels are named
so a check can find them; the pause rule came out of `_switch` into `_should_pause()`.

**What the sabotage pass taught, and it is the interesting part.** Flattening the tabs back
into one column left the card at **812px — still inside 900**, so the fit checks stayed
green and only the structural check saw it. That check took two attempts: the first
compared the card's height against the sections stacked minus the tallest, and *failed on a
correct card*, because the card's fixed chrome (241px of banner, tabs and buttons) happened
to equal the two smaller sections combined. Any assertion mixing chrome with content needs
to know the chrome, and a check cannot. The honest form needs none of it: **a tabbed card's
height follows the tab shown, and a flattened one's does not** — 302 to 557 healthy, 812 to
812 flattened.

And one check could not fail at all: "RESET CAREER opens a confirmation" called
`ask_reset_career()` directly, so pointing the card's button straight at the wipe left it
green. The whole risk was a mis-wired button and the button was the one thing never
pressed. It emits on the real button now, and reddens.

### Sound-effects volume, fullscreen, and the game's own icon (August 2026)

**A third audio bus.** Music got its own bus a session earlier and everything else stayed
on Master, which meant the only way to quieten the sirens was to quieten the music along
with them -- precisely the balance the music slider had just been added to let you set.
Sirens, engines, the fire's crackle, the city bed and the dispatch radio are on an `Sfx`
bus now, with a slider of their own. The check asserts *per player* that nothing was left
behind, because "most of them" is the failure mode: a siren still on Master is a siren the
slider cannot reach, and nothing on screen would say so.

**A display setting**, which the game simply did not have -- there was no way to go
fullscreen from inside it. Guarded on there being a screen at all, since the suite and
every generator run headless.

That guard produced the more interesting result. The obvious check -- that the headless
viewport does not resize -- **cannot fail**: Godot's headless display server has no window
(`get_window_list()` is empty, `screen_get_size()` is zero) and `window_set_mode` is a
silent no-op there, neither warning nor resizing. Sabotage removed the guard entirely and
nothing went red. `_apply_fullscreen()` now *returns whether it reached the display
server*, and the check asserts the guard's decision rather than its invisible
consequences.

**The launcher icon** was the Synty vendor logo -- wrong identity, and a vendor asset
pressed into service as the game's own. It is the user's icon now, set through
`setup_project.gd` like every other project setting.

Running that script turned up a quiet regression it had been carrying for months: its
`MAIN_SCENE` constant still said `Playground.tscn`, correct when written and stale from
the moment the menu became its own scene. Re-running it put the game back to booting
straight into the district. It only surfaced because the script prints the previous value
before overwriting it -- which is now the reason it prints it. Both the boot scene and the
icon are pinned by checks.

`config/name` is deliberately still `Polygon_Starter`: it decides the `user://` folder, so
renaming it orphans the saved career, the records and the settings. That is a migration,
not a rename.

### The in-world markers meet the kit (August 2026)

The last thing in the game still drawn the way phase 1 drew it: a `TorusMesh` ring under
each selected unit and another where it was told to go. Both are geometry built at load
now — a corner **bracket** for selection, a **reticle** for the destination — in one
`Markers.gd`.

**Built at runtime rather than in the scenes**, which is the change that matters. The ring
existed six times over (`build_vehicles.gd` plus four hand-authored crew scenes) and the
marker twice more (`build_map.gd`, `build_tutorial.gd`), so changing how selection *looks*
meant eight edits and two windowed regenerations of baked scenes. `Unit` and
`RTSController` swap the placeholder meshes at load, so the shape is now one function and
the scenes never need touching. The bracket is sized off each unit's **collision** shape
rather than its visual AABB — a Synty prefab's AABB includes the light bar.

**The sabotage found a hole nothing else could have.** Reversing the triangle winding makes
a marker face the ground: invisible in play, and byte-identical in every reading the suite
was taking — class, size, position, colour all survive it, and `Markers._mesh` fills the
normal array with `Vector3.UP` regardless. Three sabotage cycles reddened nothing. The
answer was to read the vertex array back and derive the facing from the winding itself.

And then that check shipped **inverted**, green on a broken mesh and red on a correct one,
because Godot's front face is wound *clockwise* seen from the front — so a triangle facing
+Y gives a negative cross-product y. It was caught immediately, by the sabotage agent
noticing the tree was already red before it touched anything. The real error was mine and
upstream of the polarity: I went from a parse check straight to sabotage without running
the suite, so a red check reached the agent at all.

### Driving: a wedged car could retry the same failed manoeuvre for ever (August 2026)

Eight black-box records across several sessions, all the tutorial ambulance driving home,
all `no progress for 4s` with **nothing in front of it** and the mesh reporting the ground
as drivable. The suite's own drive-home check passed throughout.

The measurement is the whole story. A probe drove the round trip and found nothing; the
suite's staging — teleport the ambulance onto the drivable point nearest the shout, zero
its velocity, face it down +Z — is an *ideal* start, and an ideal start never fails.
Started instead at the positions the black box had actually recorded, **3 of 12 never got
home**, with zero stalls: moving the entire time and never arriving.

A trace said what "moving but not arriving" meant: it drove to within 15m of the station,
stopped dead against `SM_Env_Sidewalk_Corner_01`, reversed 7.5m, drove forward into the
same corner, reversed again — a clean limit cycle, ~3s a period, for as long as anyone
watched. The path was fine and went nowhere near the corner; the car had drifted off it
and the mesh (baked at agent radius 1.0, deliberately, because 1.5 leaves this town with
two drivable points) let it come right up to the kerb.

**The fix is not in the bake.** `Vehicle` already has a kerb climb for exactly this, gated
on `_failed_escapes >= climb_escapes` — and that gate was unreachable, because an escape
*moves* the car and movement forgave the tally. The code even said so in a comment, from an
earlier investigation that had built a no-progress route through the gate and measured it
"byte-for-byte identical" — correctly, because in *that* case the cars were queued behind
other vehicles, not wedged on kerbs. The tutorial finally produced the case that
investigation lacked. `_update_escape` now forgives the tally on **progress** rather than
motion: a car easing through a bend clears 12m at once and never accumulates, a car
swinging through the same 7.5m never does. 12 of 12 recorded starts now get home.

Two lessons worth more than the fix. **An ideal fixture is not a test of a real path** —
the check that guarded this drive used a staging no player can produce, and it stayed green
for months. And **a comment saying "this was measured and made no difference" is scoped to
the case it was measured on**; this one was right about queues and wrong about kerbs, and
it read like a closed question.

### The rotors were doing everything in the wrong order (August 2026)

Reported in one sentence, as these keep being: *"it takes off before the propellers spin"*,
and the same again for landing. Both were true, and both came from the same decision --
rotor speed was driven off **altitude**, which is a plausible-sounding rule that is wrong at
each end of a flight. Nothing was turning as the aircraft lifted, so it appeared to be
raised by something other than its rotors; and the blades wound *down* through the descent,
so it landed under stopped discs.

The fix is one line -- `wanted = 0.0 if phase == GROUNDED else 1.0` -- because a helicopter
turns its rotors at full speed whenever it is doing anything at all, and stops them only
when parked. **Altitude was a proxy for "is it flying", and the proxy disagreed with the
thing at exactly the two moments anybody watches.**

The take-off delay is a new `Phase.SPOOLING`: told to go, a grounded aircraft sits still for
four seconds winding up, and enters CLIMBING on the frame the blades reach full speed. It
lives in the phase machine rather than in a timer inside `take_off()` because **three
separate call sites** put an aircraft into the air -- the verb, a right-click, and a landing
order given while grounded -- and a timer in one of them is a rule the other two do not know
about. They all go through `_leave_ground()` now.

An unplanned gain worth recording: air support acquired a **cost in seconds** that no road
unit pays. The helicopter was strictly better than driving for any distance; four seconds on
the pad is a real reason to send a car to something close, which is the kind of balance you
cannot get from a price alone.

**Two stale comments were the residue.** The check that samples the spool still described an
altitude ramp and quoted the old 1.4s spool, and it stayed green throughout -- a comment
cannot fail. It was caught by a sabotage agent *reading* it, which is the only mechanism
this project has for that class of rot. The check's own message had the same problem and was
reworded: it said "full song at cruise height" against a reading taken "low down", when the
two samples now differ because one is mid-spool and not because one is higher.

### The shop became a requisition modal (August 2026)

The storefront was replaced with a supplied UI kit -- a themed modal with category tabs and
a **cart**: pick several units, then confirm once. The old shop charged per click.

**Matching the old class's four public names is what made it safe.** [RequisitionPanel]
keeps `station`, `open_shop`, `close_shop` and `card_button`, and its own `visible` still
means "the shop is open", because three unrelated places reach for those: [HUD] wires the
buy button, [GameMenu] asks before claiming `Esc`, and [TutorialDirector] pulses a named
card. The swap touched **one line of `HUD.tscn`** and four type annotations.

The kit's scene is instanced at runtime rather than merged into `HUD.tscn`. It is 400 files
of theme, fonts and art, and a hand-merged copy would be a second thing to keep in step with
any future version of it.

**Three faults, each instructive.**

*Dropping `_input` broke the pause chain, and two checks went green over it.* The old panel
closed itself on `Esc`; the new one left input to the modal. So the shop never closed,
`_escape_is_spoken_for()` saw it open for the rest of the session, and `Esc` could never
reach pause again. Three checks reddened -- and `Escape again resumes` and `and the car
drives on` **passed vacuously**, because "not paused" and "the car moved" are both true when
`Esc` does nothing and the district was never frozen. The feared 150-check cascade did not
happen only because the guard broke the *opposite* way: nothing paused, rather than
everything staying paused.

*Two guards silently skipped nineteen assertions.* The suite still cast the node `as
ShopPanel`, which now yields null, so both shop checks hit `_check(false, ...)` and
`return`. The count fell 1087 → 1069 and only **four** FAILs appeared. That is the
documented silent-truncation mode arriving by a different road: not a runtime error, just an
early return. The check count was the only witness.

*A check that could only ever have passed by accident.* Told the cards must all fit on
screen, five of thirteen failed -- correctly, because the catalogue is a `ScrollContainer`
and the rest is below the fold by design. The assertion had been inherited from a fixed-row
layout where it meant something. It now asks the question the original bug was actually
about -- nothing escapes **sideways**, where no scrollbar can rescue it -- plus that the
scroller reaches the bottom.

*And a check that measured against a ruler made of the thing it was measuring.* The
overflow assertion compared each card to its own `ScrollContainer` parent -- which has no
fixed width and stretches to whatever the cards demand. Sabotage forcing every card 900px
wide blew the catalogue out to 1822px inside a 1600px modal and dragged seven of thirteen
cards clean off it; the check reported **`0 of 13`**. The fault was total and the number did
not move at all, because **the reference frame moved with the fault**. That is a distinct
failure from the ones already in this file: not a second satisfier, not under-provocation,
and not fixable by provoking harder -- the comparison was self-referential, so no fault could
ever register. Measured against the panel, which is viewport-sized and fixed, the same
sabotage now reads `7 of 13` and names them.

Worth generalising: **an assertion needs a ruler that the fault cannot bend.** A parent
container sized by its children is not a ruler.

**One weakness is left in, and named rather than hidden.** Pushed mouse input reaches the
tabs and the DEPLOY button but was measured not to reach a card inside the scroller, so the
cart is driven through `UnitCard`'s own `pressed` signal -- the path a real press takes, and
everything downstream of the button is genuinely exercised. What is *not* proven is that a
click lands on a card. The corner button and DEPLOY are still clicked for real. Saying so in
the check's comment is the alternative to quietly asserting something weaker.

**The cards came out unreadable, and the cause was one unset enum.** Reported from play
with a screenshot: "POLICE '", "RECOVERY 1", "AMBULA", prices clipped mid-figure. A
[TextureRect] defaults to `EXPAND_KEEP_SIZE`, so its minimum size is the *texture's* size
and `custom_minimum_size` is only a floor. The kit was drawn against 24x24 icons; this game
feeds it **192x192 rendered portraits**, so every 72px portrait panel became 192px inside a
340px card and left about 48px for the text. `EXPAND_IGNORE_SIZE` restored the whole layout.

Worth keeping as a general point about adopting someone else's UI: **the kit was correct and
the data was correct, and they were incompatible in a way neither could state.** Nothing was
misconfigured; a size assumption baked into the art it was designed for simply did not hold
for ours.

Two smaller things fell out, both of them my fixes rather than the kit's faults. Clipping the
description label evened up a ragged grid -- two cards were 155-159px against the others'
138, because a label's minimum width pushes its card out -- but then genuinely cut two
descriptions off; autowrapping to two lines fixes both, since an autowrapped label's minimum
width is its longest *word*. And trimming each blurb to its first sentence kept lines short
until the recovery truck came out reading **"Seats 2."** and nothing else -- its informative
half is the second sentence. Wrapping removed the need for the rule that had to guess which
half mattered.

**And then the same enum a third time, in the cart.** Reported with a screenshot: three
units in the order and the dialog had stretched to the height of the screen. `OrderRow`
builds its own [TextureRect] for the unit's picture, with the same unset `expand_mode`, so
each row was about 192px instead of 52 and the modal sizes itself around its contents. The
order list is wrapped in a [ScrollContainer] at runtime as well, so a long order cannot
resize the dialog either.

Three instances of one mistake, in three files, none of which could see the others. The
lesson is not "remember `expand_mode`" -- it is that **an assumption about art dimensions is
invisible in the code that depends on it**, and adopting a UI built for different assets
means every place the art is measured is a candidate.

The check that pins it asserts the panel's whole `size`, not its height, and sabotage showed
why that mattered by accident: with the row fix removed but the scroller still in place, the
modal grew **sideways** instead -- 1060 to 1221 wide, height unchanged. A height-only
assertion would have gone green on the very fault it was written for.

The £350 deployment fee the kit ships with is set to **zero**. Switching front ends is no
reason to start charging the player money; it is one line if the fee is ever wanted as a
mechanic.

### A cell nobody asked for, found by a new shop UI (August 2026)

A purchase-modal UI kit arrived to replace the storefront. Before wiring it up, the
catalogue had to be mapped onto its card model -- and the very first dump printed **"1
cells" beside a tow truck**.

`build_vehicles` read `root.cells = int(config.get("cells", 1))`, so a catalogue row that
simply did not mention cells got one. The ambulance, the fire engine and the recovery truck
each carried a phantom cell. And **the scene files looked correct by saying nothing**: a
`.tscn` stores only properties that differ from the script's default, and `Vehicle.cells`
defaults to 1, so the absence of a line *was* the bug. Two were inert because
[LoadSuspectAbility] gates on POLICE service; the recovery truck is police, so a prisoner
could be loaded into a tow truck.

**It survived because every arrest check uses a patrol car or a van** -- the two units that
declare their own cell counts and were therefore always right. A default is only exercised
by the cases that say nothing, and those are exactly the cases nobody writes a check for.
The new check asserts a table rather than a rule, because both directions matter: a van
that quietly loses its six cells is as wrong as a truck that gains one.

Worth noting *how* it was found. Nothing in the suite was looking for this, and nothing
would have. It surfaced because a new consumer had to read numbers the old one never read
-- which is an argument for building the adapter early when replacing a UI, rather than
last.

### Backgrounding a sabotage agent raced the Stop gate (August 2026)

The suite came back red mid-turn with `truck has 1, wants 0` -- the phantom-cell fault,
caught in flight, because a `godot-check-sabotage` cycle was running in the background with
`cells = 1` deliberately injected. CLAUDE.md already forbade exactly this and every cycle
that turn had been run synchronously. The rule was broken by **resuming** an agent with
`SendMessage`, which has no synchronous form and always launches in the background.

The note has been widened: the hazard is any path that *starts* the agent, not the
`run_in_background` flag. Reading it as being about the flag is what made an explicit,
already-documented trap invisible.

### Two more units, and a repaint that was accepted and ignored (August 2026)

The **Interceptor** (the Heist pack's second police body, the quickest car on the road) and
**Air Rescue** (the fire service's first flying unit) went in together, in one windowed
generator run. Neither needed new machinery. What they needed was a livery, and finding it
took a correction.

**I said the rescue livery did not exist. It did.** I searched filenames for `rescue`, found
nothing, eyeballed two of the sixteen Heist atlases, saw they matched, and concluded the
pack shipped one helicopter skin. The player produced the Synty store shot: four
helicopters, the fourth red and yellow with RESCUE on the tail. The livery is
`PolygonHeist_04_A.png`, which carries RESCUE in red on amber exactly where `01_A` carries
POLICE in white on blue -- the *fourth* colourway of an atlas, not a file with the word in
its name. **The lesson is about the search, not the pack**: a filename grep and two spot
checks felt like a survey and covered an eighth of the evidence. What settled it in the end
was a twenty-line script that diffed every atlas against `01_A` and printed the average
colour of the label block. Sixteen numbers, and `04_A` at rgb(223,133,21) was the answer at
a glance.

**Then the repaint did nothing, twice.** `_copy_materials` decided what to repaint by asking
whether the material path contained `"PolygonCity_01_A"` -- the City pack's body material and
nothing else -- so a Heist vehicle declaring a `palette` was accepted, ignored, and built
identical to the unpainted one, with no warning. Fixing that in `build_vehicles.gd` left the
shop card still showing a police machine beside a label reading Air Rescue, because
`build_portraits.gd` carries **its own copy of the same guard** and had the same fault. The
only thing that caught the second one was looking at the rendered PNG.

The fix in both is `path.ends_with("_01_A_mat.tres")` rather than `"_01_A" in path`, because
Heist ships `PolygonHeist_01_A_Glass_mat` beside the body material and the over-broad version
paints the cockpit with the bodywork atlas. The check is three-sided for exactly that reason:
the livery is on the rescue machine, *absent* on the police one, and the glass is untouched.

Two things generalise. **A config value that is read, accepted and silently discarded is the
worst shape of bug this project keeps producing** -- the missing `siren` key, the un-repointed
`StuckLog`, and now this, all of which looked correct in the source and wrong only on screen.
And **a duplicated guard gets fixed once**: the two generators had the same line for the same
reason and no test tied them together.

Also caught by the suite rather than by eye: the two new portrait PNGs shipped without
`.import` companions and loaded as null, so the shop showed `2 missing of 13`. That trap is
documented and still cost a run -- **a new asset needs `--import` before it exists**.

### A unit was built, painted, and unreachable (August 2026)

Asked by the player, in five words: *"How do I get a recovery truck"*. You could not. The
truck had a generated scene, a portrait, a measured lightbar and a place in
`build_vehicles.gd` -- and no row in `Station.TYPES`, so nothing in the game could reach any
of it. It had been built one session earlier and discussed as though it were in the game,
including by me, twice.

**Every check that touched vehicles walked the catalogue**, so none of them could see a unit
that was not in the catalogue. That is the whole shape of the fault: the suite was thorough
in one direction and blind in the other, and thoroughness in one direction reads exactly like
coverage. `_test_every_emergency_vehicle_is_purchasable` walks scenes → catalogue instead,
filtering on `service != NONE` so civilian traffic stays correctly unsellable. Deleting the
truck's row again reproduces the original bug on demand: `stranded: TowTruck.tscn`.

Worth pairing with the lightbar check written the same week, which walks catalogue → scenes.
Neither direction subsumes the other, and the pair is what makes "the fleet is complete" a
claim rather than a hope.

### A check that could flap on a busy machine (August 2026)

Found by a sabotage pass as collateral it correctly argued was *not* collateral: a UI audio
check reddened during a cycle that changed a folder path in a catalogue test, which cannot
reach it. `rollover2.ogg` runs 0.0573s; the check waited two frames -- 0.0333s of
*simulated* time -- before reading `playing`. The audio server plays in real time whatever
`--fixed-fps` says, so a pair of heavy frames finishes the sample and the check reads false
with nothing wrong.

The fix is not a longer wait but no wait: `emit()` calls the handler synchronously, so
`playing` is true the instant it returns and the frames bought nothing. **A margin is not a
fix when the two quantities are measured on different clocks** -- simulated frames against
real-time audio -- because no margin is safe, only larger. The suite is the arbiter here, and
an arbiter that flaps is worse than one that is wrong in a fixed direction.

### The black box had been recording the test suite (August 2026)

The count of records in `user://stuck-log.txt` jumped between sessions in a way nobody could
tie to play -- 144 one session and 0 the next, then 57, then 95, always `Ambulance 2`, always
the tutorial ambulance driving to the station. It was carried as an open defect for months
and read as evidence of a second driving fault behind the one that was fixed.

It was the suite. `_run` repoints the district's [StuckLog] before a single check goes off,
and the comment there is emphatic about why -- *"every suite run had been appending its
fixtures into `user://stuck-log.txt` ... and one of them was diagnosed as a live bug."* That
repoint reaches one scene. `_test_the_tutorial_town_boots` instantiates **Tutorial.tscn**,
a second scene, carrying its own recorder that kept the default path. So the fixture's
drive was filed into the player's black box under a name indistinguishable from play, and
the record count tracked how often the suite had been run.

**The same trap, in the same file, caught twice and fixed once.** The tutorial test pins
`station.career_path == "user://tutorial-career.cfg"` twenty lines below the bug: the career
trap was remembered for this scene and the black-box one was not. What generalises is not
"be careful" but the shape -- **anything a fixture writes to `user://` has to be repointed
per scene, not per suite**, and the only reliable enforcement is a check that asserts it,
which now sits beside the repoint.

Proven the honest way. Sabotage pointed the fixture back at the real log, and the file grew
by exactly one record reading `--- Ambulance 2: no progress for 4s ---` -- the historical
signature, reproduced on demand. A healthy run leaves the file untouched, so the growth is
attributable to the fault alone. (The player's log was backed up first and restored
byte-identical; a sabotage that writes to real user data is a backed-up artefact like any
other, which the procedure now says.)

The August escape fix above stands on its own evidence and is not withdrawn -- it was
measured by a probe against recorded start positions, 9 of 12 getting home before and 12 of
12 after. What is withdrawn is the belief that a *second*, unfixed fault was still filing
records. There was no second fault. There was a test writing in the player's diary.

### Two checks that looked sound and were not (August 2026)

Both came out of one sabotage pass, and neither is a Godot lesson.

**A guard coupled to the fault it guards.** The new lightbar check walks the catalogue,
sorts vehicles into `lit` and `dark`, and asserts `dark` is empty. Its companion asserted
`lit.size() >= 5`, to stop an empty catalogue passing vacuously. But `lit` and `dark`
partition one set, so darkening a single vehicle dropped `lit` to 4 and reddened the guard
too -- **a guard that cannot survive its partner's fault is not a guard**. Counting
`lit.size() + dark.size()` decouples them, and sabotage confirmed both halves: darken a
vehicle and only the partner reddens; make the catalogue unloadable and only the guard does.

**Two satisfiers, one assertion.** `the rotors are still winding up low down` sampled the
main rotor half a second after take-off and asserted the rate was low, to prove rotor speed
follows altitude. Delete the altitude ramp entirely and it stayed green. The fault was fully
present and the number *moved* -- 0.032 rad to 0.206 -- but the bound was 0.3, because at
0.5s `rotor_spool` (1.4s) still capped the value whatever it was aiming at. **The check was
named for the ramp and measuring the spool.** Sampling at 1.5s, past spool completion,
leaves altitude as the only thing that can hold the reading down: 0.284 rad healthy against
1.467 with the ramp gone.

That last one is worth separating from vacuity, because it looks like it and is not. A
vacuous check cannot see the fault at all; this one saw it, reported a six-fold change, and
passed anyway because something else was independently sufficient. **The tell is that the
number moved and the verdict did not** -- which is only visible if the check prints its
measurement, and is invisible in a bare boolean.

### Driving: the tutorial's ambulance was stranded on a sheet of pavement (August 2026)

Six black-box records across three play sessions, all the same car leaving the same
shout, none of them explained by anything within 14m of it. The last one carried the
word that cracked it: `reachable: false`, while sat on a road collider.

The tutorial's vehicle navmesh was baked from roads *and* pavements with the pavements
lifted half a metre, so the kerbs would carve the carriageway -- a fix that worked, and
whose leftovers nobody had questioned. The raised tops stayed in the mesh as a second
sheet, dismissed in a comment as "islands no car on the road can reach -- the same
harmless shape as a roof". An ambulance sent to a kerbside casualty parks beside one,
snaps onto it, and then has no route home at all. Measured: four connected components,
two of them map-spanning and interleaved, and 457 of 685 drivable points unable to
reach the station. The bake now discards the lifted polygons after carving with them
(695 -> 117 polygons, one component, 0 of 1001 points stranded).

The lesson is in NEXT.md's working notes: the suite's real drive-home check stayed
**green** throughout, sabotage included. It drives one route, faithfully, and the fault
was never on it. Faults that live in a space want a sweep, not a journey.

### Driving: a car could be lost through the floor (August 2026)

Play feedback about pathfinding, vehicle collisions and pedestrians led to
[Game/diagnose_driving.gd](Game/diagnose_driving.gd) -- a keepable dev utility that
tours a car across the district, drives it at a staged blockade, and samples the whole
map throughout. What it found was not what the complaint described, which is the third
time on this project that measuring first changed the answer.

- **Routine pathfinding is fine.** Six of six legs between real junctions arrived, 4.0s
  to 20.4s, top speed 25.8 m/s, zero interpenetration frames, 93% of ambient traffic
  moving. The first run of the diagnostic reported two failures and they were *the
  diagnostic's fault* -- its waypoints were round numbers that landed inside city
  blocks, where there is no navigation mesh. It asks `CityGrid` for junction centres now.
- **Driving into parked vehicles pushed the car through the road.** Measured at
  **y = -58,356**, which is precisely free-fall for the sixty seconds it was watched.
  Two CharacterBody3Ds have no solver between them: on a deep overlap `move_and_slide`
  depenetrates along the shortest exit axis, and downward through the floor is sometimes
  shortest. Nothing recovered it, and nothing noticed -- the stuck escape only armed on
  a *stationary* car, and a falling one is moving. The same sink was quietly happening in
  the suite's own fixtures, where seven units park in a tight grid at the station.
- **The fix is a net, not a cure.** `Vehicle._keep_on_the_map()` snaps a vehicle that
  ends up below the world onto the nearest navigation point, and the stuck escape now
  arms on being off the floor as well as on standing still. The blockade leg went from
  *failed, 60s, y = -58,356* to **arrived in 10.6s**.
- Restoring to a **remembered** position was the first attempt and was worse than the
  bug: it teleported a fire engine across the district into an unrelated scene and broke
  four checks. The navigation mesh already knows where a car may legally stand, and
  asking it cannot move the car further than it has already fallen.
- Three of the four checks covering this were vacuous when first written, and the
  sabotage agent found all three: one measured *flat* distance, so a car in free-fall
  directly beneath its start scored a perfect 0.0m; one asserted only that the wheels
  were turning, and passed with the car sixty-seven metres underground. Both now carry
  the vertical term their names imply.

**The pile-up, and it was the pull-over all along** (play feedback, same day). The report
was "the car reverses, drives back the same way, hits the same car, never resolves", and a
minute later a photograph of four ambient cars jammed at angles across both lanes. Neither
staged scenario reproduced it until the rig was made faithful -- the first jam test parked
the player's car with its lights on and *cleared its orders*, and `is_responding()` reads
the current order, so no traffic ever pulled over and the test watched a district going
about its business.

With a responder actually driving the street, the cause was unambiguous and monotonic:

| t | 10s | 20s | 40s | 60s | 70s |
| --- | --- | --- | --- | --- | --- |
| pulled over | 1 | 3 | 5 | 6 | **7** |
| still moving | 21 | 18 | 17 | 16 | **16** |

Cars tucked to the kerb and **never came back**. The release depended only on the
responder getting far away, and a player working the same streets with the lightbar on is
never far enough -- so every car it passed tucked in and stayed, and once they are solid
the next arrival tucked into an already-tucked car and stopped at an angle across the
lane. `pull_over_max` (7s) and a cooldown end the manoeuvre regardless: a responder is
passing, not parking. Measured again after, the count rises and clears instead of
climbing, and the moving count holds at ~20.

Two checks now pin the two independent ways out of a tuck -- distance and timeout -- and
each excludes the other, which took three passes to get right. The first version of the
timeout check read "after 0s": the test's responder reached its target, stopped
navigating, stopped counting as a responder, and the tuck ended on *distance* while the
check claimed to measure the cap. The second version's sibling bound was inert for a
subtler reason -- it timed from after the release, so it read 0.0s whichever branch fired.
Both were found by the sabotage agent, neither by reading the code.

**Responses drove on the wrong side of the road** (play feedback, same day). Lane
discipline had existed since phase 10 -- but only for a vehicle *going home*. Anything on
a shout was left to the navigation mesh, which covers the **full width** of every street,
so the car tracked the middle and swung across the centre line on every bend. Measured on
a response: **37% of samples over the line, up to 3.9m into the oncoming lane** -- a whole
car on the wrong side, and worse than the 18% the mesh gives a slower vehicle, because a
responder carries more speed into every swing.

The routing moved out of `ReturnOrder` and into **`CityGrid.lane_route`**, where the
layout already lives, and `MoveOrder` now uses it too: being on a shout is a reason to go
faster, not a reason to drive on the wrong side. Responses measure **9%** after, and the
drive home -- now sharing the same code -- improved from 6% to **0%**.

Journeys under `LANE_ROUTE_MIN` (40m) still go straight there. Routing every order round
the lattice was the first attempt and broke four checks: an 8m right-click aimed at a
junction twenty metres away, which is not tidier driving but a detour, and a right-click
that quietly aims somewhere else is worse than a wide turn.

One check had to be re-staged rather than fixed: the interpenetration test parked a taxi
on the **centre line** and drove a car at it, and the car now correctly passes 2.4m to its
right. The car was not wrong; the staging was. It parks the taxi in the driving lane now.

**The U-turn band, closed** (same day, immediately after). A turn with the target 25m
behind swung **27 metres off a 10m street** and took longer than the same turn at 45m.
It sat in a band too far for the motion model to turn round in and too near to be lane
routed, so it did neither. Measured across the range, on a cleared street:

| target behind | 10m | 25m | 45m | 80m |
| --- | --- | --- | --- | --- |
| before | 2.5m | **27.1m** | 2.7m | 2.5m |
| after | 2.5m | **3.4m** | 2.6m | 2.5m |

The fix is **two** trigger distances rather than one, because the latch is asked its
question against whatever point is currently being aimed at: strict for a waypoint on a
route, generous (45m) for a straight drive at a destination. One number could not serve
both, and both single-number attempts were measured and rejected -- raising it to 40
armed the latch at nearly every waypoint transition and cars stopped arriving at all,
and dropping the route threshold to 18m made every turn worse.

Getting the *meaning* of "final" right mattered as much as the number. The first version
gave the wide trigger to the last leg of a routed journey, and the latch re-armed on the
approach: line-keeping went from 9% over the centre line straight back to 36%. It means
"there is no route, this is a straight drive at the destination".

Two things that had to be widened along the way: `navigate_to` gained an optional
argument on `Unit` and `Person` as well as `Vehicle`, because orders hold a `Unit`; and
ambient traffic explicitly keeps the strict trigger, since its legs are waypoints in all
but name and a taxi three-point-turning mid-street is not what the district wants. (That
argument was called `final` at first and is now `may_turn_round`, which is what it
actually controls — the rename came when a third caller needed it, below.)

**The last two deferred driving faults, taken** (August 2026). Both were in NEXT.md
because neither loses a unit. Both were staged before being fixed, because neither of
the existing diagnostic passes actually provoked them.

*A car that gives up.* The ambient fleet has re-planned on lack of **progress** since
phase 12 and the player's cars never got the same timer. Six seconds of closing on
nothing writes that street off — `CityGrid.route` takes a `shut` set of edges and plans
round them — and the car goes another way. Staging it took three attempts: one car
angled across a lane turns out to be passable, three spaced across it are shovable, and
only four filling the full 10m width leave no answer but another street. Measured on
that: **failed 60s, 18.7m short → arrived in 40.1s**.

Two things the measurement taught that the fix would have been wrong without. The
existing "one car in the road" pass had been starting the car *facing away* from the
blocker for its whole life, so every reading of it was a U-turn plus an obstruction —
and the give-up timer duly fired mid-three-point-turn, writing off a street the car had
not finished setting off down. Hence `Vehicle.is_turning_round()`, and hence the pass
now faces the right way. And the first fix left the car with a perfectly good route
round the block and **0.6m travelled in 60 seconds**: nose against the wall, it needed
to swing round, and the reverse latch only arms for a nearby target. So a re-plan grants
the wide turn-round range for exactly one aim — which is why the flag is now called
`may_turn_round`.

*Someone on foot who cannot get past a car.* People mask layer 1, which is what the
player's vehicles sit on; no vehicle masks people at all. So nothing moves out of
anybody's way and a walker simply stops: staged with a car between an officer and where
they were sent, **1,716 of the next 1,747 frames stationary**, never arriving. Now a
person who has been getting nowhere for half a second has their intent swung to run
*along* whatever is in the way, and `move_and_slide` does the rest — **arrived in 9.3s,
31 frames held up**.

Not fixed by taking vehicles out of the person mask: walking through a parked car is
worse than stopping at one. And the obstruction is found with a **ray query, not this
frame's slide collisions** — a person walked flat into the side of a car has `velocity`
zeroed and a slide-collision list containing two entries, both of them the road they are
standing on. Whatever the engine does with a contact that stops motion outright, it is
not something to build on.

The crowd gets the same sidestep and not the same freedom: `Civilian._may_step_to`
refuses any step off the pavement graph, because an officer may cut across a road to get
past something and a passer-by doing that is walking down the middle of the carriageway.

The sabotage agent earned its keep again, and the lesson is the same one twice. The
first version of the pedestrian check parked a car from `Game/Traffic` — layer 64, which
an officer does not mask — so the officer walked clean through it and the check passed
**with the entire sidestep deleted**. A zero reading and an obstacle that was never
there look identical from the outside, so the check now asserts the contact happened
before asserting it was got past. A companion check was deleted outright in the same
pass: "and it did not shove them out of the way" cannot come out any way but zero while
vehicle collision works, and it stayed zero in a run where the car spent a full minute
pushing at the wall.

**The kerb, made climbable** (August 2026). The ask was for cars that prefer roads but
can use a path when they have to. It took three attempts, and the first two are as
instructive as the one that shipped.

*Cars are never off the navigation mesh.* Zero off-mesh frames across all six tour legs,
so the "overrun at a junction leaves the mesh" premise was simply not what happens. What
happens is congestion: the car arrives at 25 m/s, meets four ambient cars in the junction
box, and shuffles inside a 5m square for the better part of a minute.

*A 7cm kerb is a vertical wall to a vehicle.* `move_and_slide` has no step-up and the
vehicle collider is a box, so a car driven at a kerb stops dead 2.8m short and
oscillates. A person's collider is a **capsule** and its rounded base rides the same step
without noticing — which is why the crowd has always crossed roads happily and nobody had
noticed.

**Making the pavement flush was tried twice and reverted twice.** Every measure of
getting somewhere improved, and it took the district's lane discipline with it: the
vertical face had been holding cars in lane for free, so without it a response spent 24%
of itself over the centre line and 9% off the carriageway, U-turns went two to five times
wider, and cars cut across pavements into the crowd. Two replacements were built and
measured — a steering clamp, and splitting the vehicle mesh into a road layer and a verge
layer switched on how long the car had been stuck. Both failed, and the second failed
instructively: with a flush kerb the car drifts off the road anyway, and a road-only path
then insists it cannot be there, so the agent fights it.

**What shipped is a bevel.** `_kerb_ramp` puts a wedge along each pavement's road-facing
edge — 7cm over 45cm, a 9° slope, far under `floor_max_angle` — on `LAYER_WORLD` alone so
both navigation bakes ignore it. It changes what a car *can* do without changing where it
is *sent*: the pavement stays out of the vehicle mesh, so a car can climb a kerb and is
never routed over one.

It needs one companion, because the kerb had been doing a second job: it was the only
thing that brought a strayed car back. Bevel it alone and a car that climbs one keeps
going — one ended a leg stranded against the map boundary **138m short of its target**,
with ambient contacts up from 143 frames to 999. `Vehicle._back_to_the_road` replaces the
steering aim with the nearest drivable ground once the car is more than a metre off the
mesh, measured against the mesh rather than the street grid so the station apron still
counts as somewhere to be. A manoeuvre gets three times the slack for three seconds
afterwards: correcting a car between the reverses of a three-point turn put a 45m U-turn
**47m off a 10m street**.

The result, against the figures before any of this:

| | before | after |
| --- | --- | --- |
| worst stall on a tour leg | 7.6s | **2.2s** |
| junction 4,1 | 18.1s | **6.9s** |
| junction 1,4 | 26.5s | **9.4s** |
| one car in the road | 23.4s, 3 escape cycles | **7.6s, one** |
| the blockade | 27.8s, shoved a blocker aside | **20.5s, shoved none** |
| over the centre line | 8% | **9%** |
| off the carriageway | 0% | **0%** |

U-turns are the one thing worse: 6-8m wide against 2.5-3.6m, and the 45m case takes 26s
against 8s, because a manoeuvre that used to be contained by a wall now uses the kerb.
That is the price of the wedge being climbable at all, and it is in NEXT.md.

Two things about the harness are worth more than the feature. **This simulation is
chaotic**: adding a five-second wait to one check moved every later test enough to redden
an unrelated one, and the same leg that arrives in 18s under one harness fails to arrive
in 60 under another that differs only in what it prints. Single-run comparisons are
worthless. And a **sabotage agent died mid-run twice**, leaving its sabotage in the tree
*and* a map regenerated from it — the first thing to do after one dies is check the
working copy, not the report.

**The black box** (August 2026). A unit trapped at a crossroads was reported from play
three times, and three separate headless stagings of it came out clean — including one
that walled a carriageway with four cars, which the patrol car simply drove round. Every
handling fault in this project's history has been misdiagnosed on the first guess, and
the ones that survive are precisely the ones a staged test cannot reproduce. So
`StuckLog.gd` stops trying to reproduce them: it records the real thing, from play.

It arms itself when one of the player's vehicles stops closing on what it is aiming at,
and **F3** forces a record for anything that looks wrong but is technically moving. Each
block names the position, the speed, what the autopilot thought it was doing, the state
of its route, whether it is inside a junction box, and everything within 14m of it.
Progress rather than speed, because a car shuffling under the escape manoeuvre is never
stationary and never arriving.

Its own check took four stagings, and the first three failing is the point: a wall of
four cars, a short order with no route to give up on, and a long one were all escaped by
the car within seconds. What the check does now is hold a vehicle still under orders and
assert it gets written down — testing the instrument rather than the game, which is the
honest thing for an instrument to be tested on.

The first records it produced already carry a finding: two of the player's own vehicles
sitting **0.0m apart** on the station forecourt.

**The minimap could send a unit off the map** (August 2026) — found by the black box on
its first session, which is the whole reason it exists.

A patrol car was recorded aiming at **z = 402 on a 260m map**, 270m outside the district,
with a twenty-waypoint route that took it along the bottom edge and up the right-hand
side. From the player's chair it looked like clicking *right* and watching the car go
*left* and then tour the perimeter, and three separate headless stagings of "a unit gets
trapped" had come out clean because the fault was never a trap at all.

`Minimap._to_world` is linear and was unclamped, and `_gui_input` does not promise a
position inside the control -- a drag keeps delivering events wherever the pointer has
got to. A right-click read as 384px down a 190px card converts to a destination a quarter
of a kilometre outside the city. Nothing then fails loudly: the navigation agent clamps
an unreachable target to the nearest point it *can* path to, which may be the far side of
the district, so the unit sets off in the wrong direction with no sign anything is wrong.

Fixed at both ends. The conversion clamps to the **district** rather than to the card --
the card frames 132m against a 130m half-width, so even its own corners stand for ground
a unit cannot be sent to -- and a right-click whose position is outside the card's rect
is refused rather than relocated, because that is an order the player never gave.
`RTSController.order_at_point` guards the funnel itself: it is the one place a bare world
point becomes an order without a raycast having proved it is somewhere real.

Both guards were seen to fail, and the sabotaged conversion produced destinations at
**528 and -396** -- the same magnitude as the 402 the recorder caught, which is the
mechanism confirmed rather than inferred.

**And the correction that followed.** The off-map destination above was **the suite's
own fixture**, not a fault in play. `StuckLog` defaults to `user://stuck-log.txt` and the
check that exercises it only redirected the path partway through the run, so every suite
run had been appending its fixtures into the player's log -- including the pull-over
check's deliberate `navigate_to(post + direction * 400.0)`, "somewhere it can never
reach", which is exactly the record that got diagnosed as a live bug. The redirect now
happens in the fixtures before a single check runs, and a check asserts the recorder is
not pointed at the player's log.

The minimap clamp stands on its own -- an out-of-rect click really did convert to an
off-map destination, and both guards were seen to fail -- but it was not the reported
fault, and saying so was wrong. The lesson is narrower than "check your instruments":
**an instrument that shares a file with the thing it observes will eventually be read as
evidence of it.**

Two more things were tried against the real reports and backed out. Starting a lane route
from the junction *ahead* of a car rather than the nearest one -- which is genuinely what
makes a unit set off away from where it was sent -- shortens routes (four waypoints to
two) and costs the lane discipline the approach leg was quietly providing: 9% over the
centre line became 21%, and the staged blockade stopped arriving. And a `navigate_to`
guard that clamps any off-map destination is kept, since nothing in play should ever ask
for one.

**A real fire appliance, and the fire itself** (August 2026). Two Synty packs arrived --
POLYGON Town and a particle pack -- and closed the oldest gap in the project. The
appliance had been the City pack's **van in orange paint**, and before that the patrol
car's hull; it is now a POLYGON Town aerial at **3.11 x 2.84 x 8.82**, 76% longer than
the van. `Fire.tscn`'s hand-built cone-and-quads became the pack's fire and smoke.

**The swap was gated on a measurement, not on looks.** Turn radius is
`wheelbase / tan(steer)`, and the appliance's wheelbase is 4.46 against a patrol car's
2.88 -- the longest body on the map, in a district where wide cornering is the
known-worst behaviour. `probe_corner.gd` grew a `PROBE_UNIT` switch and drove both round
the same three junctions before any cosmetic work: the appliance completed all three in
**74.2s against the patrol car's 76.4s**, reaching full lock and reversing at two apexes.
Had it not got round, the honest outcome was to stop.

Three things the swap broke that nothing caught, all found by review rather than by the
suite, and all now pinned:

- **The crew dismounted *inside* the truck.** `dismount_back` was a fixed 3.2 measured on
  a 5m van; the appliance's tail is 4.4m back. It is derived from the hull now (5.50 on
  the appliance) and a check reads the number. Nothing would ever have caught it: a
  vehicle is a `CharacterBody3D`, so it is absent from the baked navigation the dismount
  point snaps to, and four firefighters simply appeared in the bodywork.
- **Every other portrait shrank 37%.** `_shoot_group` frames a group on its largest
  member so the relative sizes stay honest -- which held while the biggest vehicle was a
  5.2m car. The 9m appliance took the patrol car from filling 82% of its card to 52%.
  The frame is now capped just above the *second* largest and the appliance overhangs.
- **The paint check lost its subject quietly.** It samples a body's albedo at its own UVs
  and asks whether red leads; that is the right question for a *repainted* placeholder
  and the wrong one for a purpose-built asset. The appliance's red-and-white livery
  averages +0.03, under the bar, while a yellow taxi reads warmer than either. The check
  now covers the firefighter alone -- a real turnout kit since August 2026, passing at +0.18
  where the repaint it replaced managed +0.08
  -- and the appliance is pinned by what it *is*: wheelbase, bulk, and a ladder no other
  body in any pack has.

The appliance lost the van's rear doors, which no code needed -- `open_doors()` already
no-ops without them. It gained an **animated ladder** in their place, raised while its
hose is being worked and lowered when the crew stop. The ask expires rather than being
cancelled, so nothing has to remember to put it away.

**The cone went too, a session later** -- on play feedback: "the fire is great, but remove
the orange cone now that the fire is in place". It had been the readable silhouette at RTS
zoom while the flame was two hand-built quad emitters, and against the pack's fire it was a
flat orange lozenge sitting inside one. `FX_Fire_Large_01` replaced the medium in the same
pass, so a fire is now one big plume and nothing else. Removing it surfaced a real bug: the
scale was being applied to *every* emitter, and scale is inherited, so the embers were
running at 2.4 x 2.4. Scale goes on the two roots now, `amount_ratio` on all four.

**The ritual caught a vacuous check, which is what it is for.** "Every emitter thins with
it" took its emitter list from `_particles` -- the same list the code under test iterates
-- so it read "N of N" and could not fail for the fault it named. Deleting the
sub-emitter collection entirely left it green at `(2 of 2)`. Counting off the scene tree
instead splits the numerator from the denominator, and the same sabotage now reads
`(2 of 4)`.

Ruled out after review: the Town characters use a different skeleton (`Ankle_L`,
`Clavicle_L`) from the City pack's humanoid rig, so they would not animate -- a
retargeting project, not an asset swap. The pack's rain was left alone; the current rain
encodes a hard-won fix recorded above.

**The kerb, climbable on request** (August 2026). Third attempt, and the first that
shipped working. The two before it changed the *ground* — a flush pavement, then a bevel
— and lost lane containment because world geometry is unconditional. This one is a manual
step-up on the vehicle (`Vehicle._climb_kerb`, run after `move_and_slide`), which is the
loophole in the "no middle setting" rule recorded below: it binds a slope, not a body.

The gate is the whole feature, and the first version of it was wrong in both directions.
Gated on *being stuck*, it fired on corners — junction 1,3 went 12.9s → **41.2s**, 423 of
2473 frames off the carriageway, 3.3m off the mesh, which is the bevel's own 30.6s / 328 /
4.9m returning — and fired nowhere the player wanted, because a car is never routed over a
kerb, queues 7m short of a blockade, threads a lone obstruction without touching the
verge, and steers away from a kerb it is aimed at. Gated on *the player having asked* it
does the job: an off-layer destination sets `_off_road_target`, which keeps the order
alive past `is_navigation_finished()` and licenses the lift. Right-click a pavement and
the car climbs onto it (order completes, ends on the pavement 2.0m from target, four
climbs) where before it never left the road; the corner is identical to the metre with
climbing on and off.

Three harness lessons, each of which produced a wrong answer first. **Two conditions in
one process measured the process** — whichever ran second failed, and reversing the order
reversed which, with the climb firing zero times in the run that supposedly damned it.
**A landing check written with `map_get_closest_point` was vacuous**, that call having no
layer filter on a shared map; caught only because adding it moved nothing. And **a climb
counter captured by a lambda always read zero** — GDScript lambdas capture by value — a
check that failed reporting `0 climbs, rose 0.22m`, where 0.22 is exactly `climb_height`
and so was the thing that gave it away.

**The bevel, removed** (August 2026). It was shipped to stop cars wedging against kerbs,
a fault found in a probe. It caused one found in *play*, twice reported: cars grinding
along pavements. The black box named the place -- three records across three sessions put
a car off the carriageway within a couple of metres of the same corner -- and probing that
corner settled it.

| the turn into junction 1,3 | with the bevel | without |
| --- | --- | --- |
| time | 30.6s | **17.1s** |
| frames off the carriageway | 328 of 1836 | **0** |
| furthest off the drivable mesh | 4.9m | **0.4m** |

The vertical kerb had been containing cars through corners, and that turns out to matter
more than letting a wedged one climb out. There is no middle setting: a kinematic body
climbs any slope under `floor_max_angle` at any speed, so a kerb is either climbable or it
is not -- steepening the bevel past 45 degrees just makes it a wall again. The recovery
written to go with it (`_back_to_the_road`) was not enough on its own and went with it.

Kept from the same stretch, all of it independent of the bevel: the black box, the
minimap clamp, the `navigate_to` off-map guard, and the fix that stopped the suite writing
its fixtures into the player's log.

**The give-up timer was blaming the road** (August 2026). Found from play, by the black
box, once its records carried a **trail** — twenty positions at half-second intervals.
Every earlier record was a snapshot, and a snapshot cannot tell a car that stopped where
it stood from one that wandered off its route and stopped there.

The trail showed a patrol car with a destination 200m **east** doing this:

    (-58,26) x9  ->  (-60,22) -> (-65,17) -> (-71,18) -> (-78,17) -> (-83,12) -> (-78,3)

Four and a half seconds stationary a metre onto the pavement, then **twenty-five metres
of reversing** at `speed -9.0` with the escape manoeuvre firing. The give-up timer then
concluded the street was shut, wrote off two of them, and replanned: twenty waypoints
ending at the far **west** edge of the map. That is the erratic touring, and its cause was
never a blockage at all -- every record that wrote a street off also said
`holding behind: nothing` with nothing within 14m.

So [MoveOrder] now asks whether anything is actually there before it writes a street off.
Two details matter and both were measured. The question has to be asked with a **longer
and wider** reach than the passing check uses -- that one answers "can I pass this?"
within a manoeuvre's distance, and from 15m back it called a carriageway walled with four
cars clear. And it has to be asked along the way the car is **trying to go**, not the way
it is pointing: a car reversed out by its own escape faces back down the street, so a test
against its bonnet reports a clear road however solid the wall ahead, and the shut-street
case stopped being solvable at all.

With the gate in, the staged shut street is *faster* than without it -- 38.9s against
49.1s -- because a car that stops writing off streets it is not blocked on keeps the
routes it needs.

**And the 360-degree loop** (August 2026). Reported as "the direction is right but the
car immediately turns left and does a 360 degree loop before heading right", and the black
box's trail showed exactly that: bound for x = +126, the car went from (-58,26) west to
(-74,17) and then away south to (-83,0).

The lattice route starts at the **nearest** junction, and nearest is often *behind*. Two
thirds of the way along a street, the corner already passed is closer than the one ahead,
so the route sends the car back to it -- and from there the next waypoint is 48m the other
way, which is far beyond the range the reverse latch will three-point-turn for. Unable to
turn on the spot and unwilling to reverse, the car drives a circle. Measured from the
recorded start, across four headings:

| | first waypoint | went west | turned through | to make 40m east |
| --- | --- | --- | --- | --- |
| before | (-74.0, 17.5) | 16-25m | **255-523 deg** | 8.3-15.8s |
| after | (-26.0, 22.5) | 0m from three of four | 16-195 deg | 2.8-6.9s |

The fix drops the approach waypoint when the car is **already past** that junction along
the first leg. Deliberately narrower than the obvious version: redirecting the whole
search to the junction ahead was tried two sessions earlier and reverted, because the
approach leg quietly provides lane discipline and losing it took a response from 9% over
the centre line to 21%. Dropping one waypoint in one case does not.

Worth recording about the harness rather than the game: the lane-discipline figure in
`diagnose_driving.gd` has read anywhere between 8% and 25% across this session's runs on
identical code. It is far too noisy to judge a change by, and the suite's own bounded
check is the only trustworthy reading.

**Stage 7 — damage and repairs** (August 2026). The career only ever went *up* before
this: calls paid, and nothing took anything back, so funds accumulated and the shop ran
out of things to want. Repairs are the sink, chosen over the alternatives (a per-shift
wage bill, units lost outright) because it is the one that charges for **how the player
plays** rather than for time passing.

Damage is **money and nothing else.** A dented patrol car steers, brakes and answers
exactly as it did new. Taking a unit off the board for a scrape punishes the same mistake
twice — once when it happens and again for the ten minutes afterwards — and this district
has already shown how easily a car ends up in something it did not choose.

- **Accrued on impact**, measured as the speed lost *into* the surface: the component of
  the pre-slide velocity along the contact normal. A glancing scrape down a wall costs
  little, meeting something head-on costs a lot. Measured through the suite, £132 at
  9 m/s against £300 at 12. The floor is 3 m/s so kerbs and parking shuffles are free,
  and a per-frame cap stops one deep-overlap artefact emptying the purse.
- **Settled when a unit is booked in**, which makes the bill a decision rather than a
  tax: a damaged car keeps working, so the player chooses between keeping it out on the
  shout and bringing it home to pay for it.
- **The purse can be emptied but not overdrawn.** What it cannot cover stays on the
  vehicle as outstanding. A career that cannot afford its repairs should feel poor, not
  stop working — the same reason damage never removes a unit.
- **Visible before it lands.** The dispatch heading carries the fleet's outstanding
  damage beside the funds, and the debrief reports the shift's repairs directly under
  what it earned: a shift can be busy, well scored, and still cost more than it brought
  in if it was driven badly.

**The crowd comes back** (August 2026). The nearest thing on NEXT.md to an outright
defect, and invisible in a short session: every medical call takes a shopper
**permanently** — the body on the pavement is the person who was standing there, which is
the whole point of taking one rather than spawning a stranger — and nothing replaced them.
A long career quietly emptied the district, and once it was empty the call had nobody left
to take and fell back to conjuring a casualty from thin air, which is exactly what taking
a civilian exists to avoid.

`CrowdRefill` tops the pavements back up, one shopper every thirty seconds, and **only to
the size the map was built with** — so on a district nothing has happened to, it does
nothing at all. It reads both the size and the outfits off the map at startup rather than
being configured, so the district decides how many people it holds. Arrivals are placed
out of shot and clear of anything happening: somebody appearing in view is worse than a
slightly thinner pavement, so an arrival that cannot be placed discreetly simply waits for
the next one.

Two things it taught, both of which cost a run to find:

- **A packed scene may not remember where its children came from.** The generator instances
  the crowd into `Playground.tscn`, and `scene_file_path` does not survive that reliably —
  so the outfits came back empty and nothing could be instanced. It asks the district
  directly when the crowd cannot say what it is made of.
- **A stored countdown ignores a changed interval.** Setting the arrival gap to a twentieth
  of a second left the next arrival half a minute away, because `_due` was already counting
  down from the old one. Exactly the trap `StuckLog`'s cooldown fell into a week earlier,
  found the same way and fixed the same way.

**Fires inside buildings, and a right-click that turns the crew out** (August 2026), both
reported from play.

`Fire._spread` placed its child five metres away at a golden angle with **no check on what
it landed on**. A fire against a block's frontage spread straight into the building
footprint — unreachable, undousable, and burning until the call failed. It now tries
several angles and takes the first that a crew could reach.

The interesting part is the fix that did not work. It was written first against
`CityGrid.walkable`, which sounds like the right question and is not: `walkable` is the
**pedestrian graph's** predicate and means only "not in the middle of the road", so it
answers yes for a building's footprint. Every spread the guard was meant to reject sailed
through it, and the check reported green — the fix was inert and looked shipped. What
caught it was the *check* refusing to fail under sabotage. `CityGrid.standable` is the
predicate that was actually wanted: carriageway, pavement ring, or park lawn, but never
inside a building.

The second was a smaller change with a real hole behind it. Right-clicking a vehicle with
crew aboard now turns them out — `UnloadAbility` scores against its own vehicle, and the
controller stops excluding a crewed vehicle from the picking ray so the click can land on
it. That exposed the hole: `_handle_order` only ever *issued an order*, and an **instant**
ability has none to issue, so an instant that won a right-click silently did nothing. Any
instant ability added since would have had the same problem.

**Nothing opens inside a property, and Return delivers** (August 2026), both from play.

Casualties were appearing inside buildings. The rescue set piece placed its two at **fixed
offsets** from the fire — pavement on a frontage facing one way, the inside of the
building on a frontage facing the other. The offset now keeps its distance and sweeps its
direction until the ground is real, and the *general* rule went into `Director._clear`,
which every picker already funnels through: a scene nobody can walk to is a call that
cannot be answered, and it burns or bleeds until it fails. With the gate removed, **8 of
60** placements land indoors.

**Return became contextual** rather than gaining a neighbour. A unit carrying a casualty
goes to the hospital, one carrying a suspect to the custody door, an empty one home — the
unit works out which, since both deliveries already happen automatically on arrival and
what was missing was any way to say "take them in" without knowing where the right door
is. It is one tile because the command bar holds exactly **seven** before the
`PanelContainer` grows and silently swallows the CONTROLS chip above it; an eighth took it
from 148px to 176px, which is the fifth time this project has been caught by that.

**Police can turn traffic** (August 2026). Ambient traffic queued behind one of the
player's vehicles already waits and, after five seconds of no progress, takes another
street. What it did not do was read a **cordon** — the cones are visual by design, so a
car drove into a closed scene and sat there waiting for something that was never going to
move. The crowd had respected cordons since phase 16; the traffic never had.

An officer closing a street is now an instruction the traffic obeys. A raised cordon
within a third of a block turns an approaching car **back the way it came** — deliberately
not [method TrafficCar._reroute], which refuses to double back: that is right when a street
is merely busy and wrong when it is closed, because the only way out of a closure is the
way in. The motion model does the turn itself, and a `TrafficCar` keeps the strict reverse
trigger, so it is a three-point turn inside the width of the street rather than a sweep
across it.

The notice distance was measured rather than guessed. At 26m a car decided in time and
then three-point-turned *into* the cones, ending 2.7m from the middle of a 6m ring; at 34m
it has room to slow first and turns 13.7m clear.

Two things the check taught, both about the harness. A **runtime error inside a test
silently skips the rest of it** — `cordon.raise()` does not exist, and the suite reported
green with three of four assertions never run; only the check *count* gave it away, which
is why the count is quoted everywhere. And an assertion on a single distance is the wrong
instrument for something that moves: the car can pass the cones, turn, and be back inside
one sampling window, which reads as driving into the closure. It samples the whole window
and asks for the closest approach.

**Units get on with it** (August 2026). A firefighter standing beside a fire should be
putting it out and a paramedic beside a casualty should be treating them; waiting to be
told twice is not realism, it is bookkeeping. An idle unit now starts work on a suitable
incident within 14m of it.

Almost none of this is new machinery. The **scoring ladder already answers "what would
this unit do to this target"**, including the hard capability gating, so auto-engage is a
scan, a resolve, and an issue. What it adds is one opt-in — `Ability.auto_engages` —
because the ladder says what a unit *would* do, not what it should do unasked: working on
an incident is what a crew standing over it is for, while cordoning a street or getting
into a vehicle is the player's call.

Two gates make it safe rather than presumptuous, and both were seen to fail:

- **Only when idle.** With the `has_orders()` guard removed, a unit sent past a fire
  abandoned its order and started fighting it, and six other checks fell with it — which
  is the right amount of collateral for "orders stop meaning anything".
- **Only what the unit can finish.** `ExtinguishAbility` scores against any fire, and the
  *order* is what discovers a building needs a hose — fine when the player chooses it and
  learns, bad when an idle officer chooses it and locks itself into futile work. So a fire
  that needs a hose auto-engages for the fire service only.

Three of the four checks written for it were vacuous first, each in a different way, and
all three were caught by sabotage rather than by review: a string comparison against
`describe()` that could never be equal, a "wrong unit" case using a fire an officer can
legitimately fight, and an "under orders" case staged thirty metres away — out of range,
so the guard was never asked.

**Getting past other traffic** (August 2026). Reported as units stuck behind other cars
on the road, and the cause was not the passing logic at all.

**Traffic got almost no warning.** Every order counts as an emergency, so a unit under
orders *is* a responder and traffic *does* pull over — but only once the responder was
within a flat **16m**, which at 25 m/s is two thirds of a second. The car began tucking
when the response was already on top of it, never cleared the lane, and the pass was spent
crawling behind it. Notice is time, not distance: it is now two seconds of closing speed,
so fifty metres at full pelt and sixteen for a responder crawling. It also has to be
*coming this way* — at 16m the direction hardly mattered, at fifty it decides whether half
a street tucks for a response that has already gone by.

**And nothing could see a crawl.** The give-up timer watches for *no progress*, and a car
doing 3 m/s behind a taxi with a 25 m/s ceiling is making progress, so it reset every frame
and a journey could spend its whole length at somebody else's speed. `Vehicle.held_up_for`
counts time spent held below cruise by a vehicle it cannot pass, and four seconds of it now
writes the street off. Held cools rather than resets, because a held car is a stopped car,
a stopped car trips the escape manoeuvre, and for those frames there is no blocker in the
corridor.

Measured across a district tour, with the rest of the driving work held constant:

| | before | after |
| --- | --- | --- |
| held up behind other vehicles | 3.0s | **1.7s** |
| the worst leg | 13.7s | **10.4s** |
| its worst stall | 4.4s | **0.7s** |

**One thing found and deliberately not fixed.** Writing the check turned up a car wedged
behind two vehicles abreast that sits there for twenty seconds and never gives up: it
escapes roughly once a second, and the give-up timer resets on every manoeuvre, so the
tally never builds. Holding the tally fixes that and breaks the opposite case — a journey
that *begins* with a turn-round burns its give-ups before setting off, which is the fault
the reset was added for. Every cooling rate between the two was tried; none satisfies both,
because from inside that timer the two situations are indistinguishable. It wants a
different signal rather than a better number, and it is in NEXT.md rather than papered
over.

A vehicle on a shout now **takes the pavement to get past a shut street** — reported from
play as an engine stuck at junctions, and the report's diagnosis was wrong in a way worth
keeping. The cars were not against kerbs at all: they were queued behind traffic for 64-72%
of their stuck frames, and the stuck-car route into the kerb climb had never fired once in
the project's history, because an escape moves the car and movement zeroes the tally it
needs. Softening that gate measured byte-for-byte identical. What was actually missing was a
different question — *is the street shut and am I on a shout* — and the answer to it is a
manoeuvre rather than a looser rule.

It comes in two halves and the second is not optional: going up strands the car, because
from the pavement the navigation agent's nearest reachable point is the carriageway it just
left, on the near side of the obstruction. Left there it drove back into the wall and
mounted again — 555 frames off the carriageway, a 33.3s journey unfinished in sixty seconds.
`_returning` steers it forwards past the obstruction and puts it down. Measured on a wall of
three: a journey that never finished in 60s now takes 43.9s, and all three junction turns are
byte-identical to baseline, which is the point — a kerb runs along a street, and a junction
mouth is off the navigation mesh with no step on it, so mounting there is pure harm. Two
probes and `Game/README.md` carry the eight measurements that shaped it, including the three
plausible signals and the two plausible recovery designs that were built and thrown away.

The medical service gained its **first specialist**, and with it the first dispatch decision
it has ever had. Medical is the highest-weight call category in the game and had the least
variety in it: every casualty declined at the same rate and the player performed a sequence —
treat, lift, drive, deliver — with no question about who went where. A doctor changes that
without adding a single new verb. A casualty marked `needs_doctor` is beyond a paramedic, who
can **hold them** indefinitely but never stabilise them; only the doctor closes the gap, and
a career owning one doctor and three paramedics has to answer where the doctor goes while the
paramedics buy the time. The director gates those calls on owning a doctor, exactly as it
gates building fires on owning an engine — a casualty nobody can finish is a broken call, not
a hard one.

The enabling change underneath is small and was the point of doing this first: `Unit.service`
is identity, so it could never express a specialist *within* a service, and inventing a
fourth emergency service for a doctor would have been a lie carried through the palette, the
roster and the call routing. Capability is now service plus `Person.speciality`.

Adding it exposed a latent fault that no specialist could have avoided: `Station.type_of()`
identified units by `(service, vehicle)`, exact only while each service had one kind of
person. Writing off a doctor decremented the *paramedic* count, and the dispatch panel offered
paramedics that did not exist. Units now carry the id they were bought as. Two of this
increment's checks were themselves wrong when first written — one inverted, passing under the
bug and failing once fixed, and one inert — and the sabotage pass is what found both.

The doctor also got a car — the patrol hull in orange — because a specialist on foot arrives
after the call has resolved itself. It carries no stretcher on purpose: a response car that
could also run the patient to hospital would quietly replace the ambulance and dissolve the
bottleneck the doctor exists to be.

The shop is now grouped by service, because eight buyable types in a single row ran off the
screen and the two rightmost were unbuyable. It is derived from the catalogue's own `service`
key, so the next unit files itself.

Ambient traffic no longer tries to pull over off the edge of the world — spotted as a warning
during a play session, fixed by working the kerb point out before committing to the manoeuvre
and declining it when there is no district left to tuck into. The suite's own fixture had been
firing the same warning on every run for a destination it deliberately never reached; that is
gone too, because a diagnostic that cries wolf every run is worse than no diagnostic.

The starting purse went from £2,000 to £3,200 when the doctor arrived. The old figure bought
the four-unit starter crew and left £50 — a specialist nobody can afford until several shifts
in is one most players never meet, and medical is the service a career is most likely to open
with. It still buys one of everything essential and nothing spare: £3,050 of the £3,200.

The district got dressed. It was reported as looking bland and reusing the same assets, and
the count was the sharper version of that: the generator named 22 of the 174 props the pack
ships, all buildings being fine at 51 of 75. Kerbside furniture is now drawn from a table
keyed on the block's kind — shops put out a hotdog stand, flats put out bins and bags, the
service yards put out cones and pallets — and the district places 45 distinct props. Terrace
heights vary per block too, so twenty-one terraces stand at eight silhouettes instead of
three. The two blocks with a forecourt are held at kit height, because raising the station
wall hid every unit parked on its own apron from the opening camera.

**The driving shuffle is fixed** — the fault the black box spent a year recording, five
attempts bounced off, and the file finally carried as "wants a different signal". The
diagnosis came from reading all 42 real-play records against the turning geometry rather
than staging guesses: aims demanding turns tighter than the vehicle's radius, a latch
releasing into arcs that did not fit the street, and a blind escape recycling the failure.
The fix is a bounded multi-point turn whose every leg is sampled against the road surface
before it is driven. Fleet measure: the engine went from 23-of-24 arrivals with 75
escape manoeuvres to **24-of-24 with 31**; corners unchanged to slightly better, with
zero frames off the carriageway. A first, reactive version of the same idea won the same
fleet numbers and was thrown away for walking out of kerbless junction mouths — the
difference between the two is that the shipped legs *ask* where the road ends instead of
finding out by collision.

**Junction overshoot on the fast cars is fixed at the root.** Two F3s from play showed the
doctor car sweeping 90° turns at 16 m/s; the cause was architectural — the corner planner
read corners off the agent's path, and that path *ends at the junction*, so the turn onto
the next street was invisible until 7m out. The route now annotates each aim with its exact
turn angle from the lattice, the cap holds while the car is in the box, and the in-path
scan is honest at last. Doctor-car lane intrusion fell to a seventh on the best leg, the
ambulance's 60s corner-probe timeout became 22.9s, and both flagged geometries replay
clean. The braking is visible in play: response cars now shed speed on the approach and
take the box near walking-the-turn speed.

Money-damage was rescaled to a tenth across the board — impact rate and cap, fire scorch,
cylinder blast — after play showed a shift's ordinary contact outbilling what the shift
paid: the repair sink read as a fine for driving rather than a cost for crashing. The
mechanics are untouched (a hard knock still costs ten times a scrape, the cylinder still
bills what parks beside it); only the scale moved.

**Three call kinds from the asset shelf** (August 2026), all configuration over existing
machinery rather than new systems. The **bus collision** is the RTC at triage size: a
Town-pack bus on its side and three to five gentled casualties (scaled to the medical
roster, `DISORDER_SIZE`-style), so an ambulance with two stretchers is finally asked *who
rides first*. The **shed load** is the first call whose patient is the road — a `Debris`
incident that shuts the street to ambient traffic (raised coneless cordon), to physics (a
deliberate `Blocker` solid, the one strip-collision exception) and to the player's own
routing (`road_is_blocked` scans the debris group), cleared by a new two-service `Clear`
verb on officers and firefighters alike. The **drunk collapse** is the first call
dispatched on genuinely incomplete information: a 50/50 seeded roll hidden behind
"unresponsive — cause unknown" until a paramedic's assessment either leaves an ordinary
patient or stands a suspect up swinging in the casualty's own clothes — the same call
flipping MEDICAL → CRIME on the board via the prune-time kind re-read that ripple added.
The sabotage pass earned its keep twice here: it caught a `>= 60` score bound the
response bonus satisfied on its own (tightened to equality), and proved the swap's
frame-wait is margin while the add-before-retire *ordering* is the load-bearing part —
and surfaced a latent crash in `Call._recentre` (adopt reading a freed incident) that is
now guarded.

**Weather became the shift's** (August 2026). The CLEAR/RAIN pair grew into four states
— FOG (grip 0.88, a thick air treatment; caution, not a surface) and SNOW (grip 0.62,
its own slow-flake particles from the same parameterised builder as the rain) — plus a
fifth settings button, **SHIFT'S OWN**, under which the director rolls the sky from its
seeded stream at `begin_shift`, so every shift has its own weather and a reproduced
seed is rained on identically. Wet weather is also a dispatch fact now: the rtc and
bus_rtc rows carry a `wet_weight` the picker swaps in whenever `Daylight.is_wet()`,
so a rainy shift fills the board with collisions. The sabotage pass measured one
premise wrong — a fog *floor* shipped beside the multipliers on the belief the noon
baseline was near-zero fog; it is 0.0035, the floor never once bound at any hour, and
it was removed as dead code the same day.

**The missing child** (August 2026). The first call the player *searches*: the board's
marker stands on a last-seen anchor (a parent, police-blue ring) and never moves, while
the child — a scaled-down `Civilian` subclass strolling the walk graph on a 32m tether,
45–90m from the report — wears no marker at all. The find is physical (any person with
a service within 6m), and it is the *middle* of the job: the child attaches to their
finder and walks at heel, climbs into a police car brought within reach (an ambulance
is refused — a child is driven home in a patrol car, not stretchered), and the call
closes only when that car pulls up back at the parent, +90 on the reunion. The escort
needed no new verbs: the child cannot be clicked, so following whoever found them *is*
the escort. The child is deliberately not an `Incident` (the marker must not chase the
answer) and is excluded by class from the three systems that consume civilians — the
medical-call picker, the disturbance recruiter and the blast converter — because any of
them taking the child frees the body the report is scanning for. No child-sized mesh
exists in any Synty pack (the "SchoolBoy" is a uniform on the standard adult rig), so
the child is an ordinary outfit at 0.7 scale: at RTS distance, small is young.

**The tutorial town** (August 2026) — phase 20's second half begins. The user
hand-authored a Synty town as the tutorial level; the game migrated onto it without
touching the district: a processor (`build_tutorial.gd`) wraps the vendor scene in a
thin shell, stamps road/pavement layers by prefab family, and bakes both navmeshes
headlessly; a `lattice_fits` flag on CityGrid switches the eight machinery sites off
whose answers are lies on a foreign map (tables untouched — the suite's ~200 pins
undisturbed), restored automatically when the scene exits; and a two-incident scripted
shout rides Mission's original pre-freeplay win path, which now ends in the modal
debrief card rather than a banner. Entry is a TUTORIAL button on the title card, with
its own career file reset on every entry. The
build was measurement all the way down: the navigation map syncs asynchronously
(~30 frames — every early query answered confidently and wrongly), the town's 5m
streets needed a narrower bake radius than the district's 10m ones, driveways baked
as marooned two-polygon islands, and the grass-under-everything tiling gave the
person mesh degenerate edges until lawns stopped being pavement. Teaching prompts are
the named follow-up on TutorialDirector.

**The tutorial town became a place** (August 2026). Three passes from play: the
gardens and the gaps between houses now walk (one geometric rule — ground is ground
only where nothing is on top of it — after two naive readings failed measurably, one
stacking surfaces until the navigation map answered nothing, one confining walkers to
the pavements); two dozen civilians stroll it, placed from the person mesh's own
vertices and wandering by mesh rather than by the district's pedestrian lattice; and
the scripted shout opens **a job at a time**, which needed a `more_to_come` gate
because the scripted win rule reads a clear map as a job done. The minimap also
became a real aerial photograph of the town, baked by riding a normal game boot —
the windowed `--script` path aborts inside the engine's allocator, three runs from
three, with a native crash report to show for it.

**The tutorial drives, and teaches** (August 2026). Play filed four black-box records
in one session and the harness reproduced every one: the town's 16.5cm kerbs overlap
its road tiles, so the drivable mesh claimed ground a kerb face stood in and an
ambulance jammed against a sidewalk corner fifteen metres from home, for ever. The
vehicle bake now carves on lifted kerbs (the real 8.5cm of proudness is invisible
under a 25cm rasterisation cell) and the route that never finished takes 12s with no
escapes. A manhole that sat exactly where the casualty lay is flat now too, and both
shouts moved kerbside off the carriageway. On top of that the tutorial teaches: a
prompt line read off the world state rather than scripted, so it survives a player
doing things in their own order. The sabotage pass was the making of this one — it
proved the driving fix and the manhole rule had **no witness at all** until a
behavioural drive check and a direct assertion were added, and then caught that the
new manhole check drew its subjects from the very constant it tested.

**1089 automated checks**, all passing. Run them with any Godot 4.6+ binary
(`--fixed-fps 60` decouples the loop from the wall clock — ~20s instead of ~9min):

    godot --headless --fixed-fps 60 --path . --script res://Game/smoke_test.gd

---

## What plays today

A **260m city district**: twenty-five blocks of varied size — shops, apartments, four
office-tower families, two parks, two parking lots and a City Hall — on a grid of
two-lane streets with deliberately irregular spacing, with pavements, crossings and
kerbside furniture, and a police station and hospital diagonally opposite one another.
**60 pedestrians** walk the pavements (and the park lawns) and **22 civilian cars**
drive the streets, keeping right.

The session opens on a **title card** over the idling district — `PLAY` drops you
in, `P` pauses, and settings choose the shift length. The map ships **empty of
units**: a career starts with **£2,000 and nothing else**, buys its first vehicles
and staff from the DISPATCH block, and earns the rest by working calls — every task
pays what it scores, weighted by response speed, and the purse and fleet persist
between sessions. The district stays **quiet** until `F2` starts a freeplay shift
and the director begins producing calls, which you work end to end from an
Emergency 4–style command bar — and *which* unit you send matters, because none of
them can do another's job:

1. Vehicles roll out of the station forecourt, **lightbars flashing**, and keep to the
   roads — braking for junctions rather than swinging wide through them. The bar and
   the **siren** also have manual switches on the command bar — `J` and
   `K` — so a parked unit can light up a scene or run silent
2. A **paramedic** crosses on foot, using the pavements, and treats the casualty — they
   stabilise but are **not** saved. An officer sent instead just walks over and stands
   there
3. The paramedic fetches a **stretcher** from the ambulance — which waits at the
   kerb, rear doors swinging open — wheels it to the casualty and wheels them aboard
4. Driving into the hospital forecourt delivers them
5. An officer puts the fire out before it spreads -- police carry an extinguisher;
   paramedics cannot fight a fire at all
6. A **Disturbance** runs the same loop in police colours: an officer apprehends the
   suspect, a patrol car collects them, and driving into the station books them in
7. The call clears from the board — points for the job, more for a fast response.
   Lose the casualty and it is the **score** that takes the hit, not the shift

A shift is **five, ten or fifteen minutes** of such calls (the length is a setting) —
a civilian collapsing on the pavement (the crowd is one lighter for it), kerbside,
vehicle and building fires, disturbances, road traffic collisions at the crossroads,
and rescues that need two services at once — arriving faster and up to one deeper as
the clock runs down, with an end-of-shift debrief: score, calls cleared and failed,
delivered and lost, arrests — and the **best score**, banked to disk between
sessions. Meanwhile the district takes part: traffic pulls over for a passing
response, and a body draws onlookers along the pavements to stand and watch.

Right-click meaning comes from a scoring ladder rather than any branching in the
controller: **Free 32 → Treat/Apprehend 30 → Cool 28 → Collect/Escort 25 →
Extinguish 20 → Board 10 → Move 0**. Adding a verb is a new `Ability` and nothing else — it gets a command
tile, a hotkey and a right-click meaning without a line changing anywhere else.

Every unit, vehicle, character and the map itself is **generated** by a build script
from the shipped prefabs — `build_map.gd`, `build_vehicles.gd`, `build_character.gd`,
`build_civilians.gd`. Nothing in `Assets/Synty/` is modified.

---

## The district

Generated from the City pack's modular kit — a **52×52 grid of 5m tiles** (doubled
from 26 in August 2026), cut into a **5×5 of blocks** by two-tile roads whose spacing
is **deliberately irregular**: the band tables in `CityGrid.gd` put blocks at 30m in
one place and 50m in another, so the district reads as a city that grew rather than
a grid that was stamped. A test asserts the spans vary; the tables are the single
source the roads, blocks, junctions, addresses, traffic and crowd all derive from.

Twenty-five blocks: terraces of shops and apartments, four office-tower families
(the original square one, a 23m **round** drum with a cylindrical collider, the
octagon, and the old brick office), City Hall on the small centre block, the police
station and hospital diagonally opposite — plus the kinds that are not buildings at
all: two **public parks** (grass, a path cross, trees, benches; walkable, strolled
by the crowd, and a place the freeplay director can open a collapse) and two
**parking lots** with cars batched into the stalls.

The station and hospital still sit diagonally opposite so a casualty run is a real
drive — now ~130m of it. Both give up one side of their block to a drivable
**forecourt**, which is where their vehicles park.

Two traps the doubling surfaced, both caught by measuring first: the grass/path kit
uses the **opposite corner origin** to the road kit (x[-5,0], not x[0,5] — a blind
`_kit_transform` would have offset every lawn a tile), and the parked-car prefabs
live in a folder the generator had never needed to index, so the first build laid
out both lots with every stall silently empty.

### Roads *are* the pathfinding

The headline of the phase, and the reason it is only a couple of hundred lines: there
is **no road graph to maintain**. The vehicle navigation mesh is baked from road
surfaces and nothing else, so the street plan *is* the graph a car paths on. Order one
into the middle of a block and it drives to the nearest street, because there is no
mesh anywhere else for it to stand on.

Two collision layers carry it — 16 for road surface, 32 for pavement — and each mesh's
`geometry_collision_mask` picks what it can see. People get a second mesh baked from
**both**, at a 0.4m agent radius against the vehicles' 1.5m, so they use the pavements,
fit through gaps no car could, and cross wherever they like -- a freedom the player's
crews use and the civilians deliberately do not. The 7cm kerb modelled into
the sidewalk meshes falls inside `agent_max_climb`, which is what joins road and
pavement into one continuous surface.

The minimap reads the same road slabs to draw its street plan, so it cannot disagree
with where cars can actually go.

## The population

7 civilian outfits and 6 civilian car bodies, generated the same way the player's units
are. Both AI classes **extend the player's own**: a civilian walks exactly as an officer
does, a taxi drives exactly as a patrol car does. Neither reimplements locomotion —
what they add is a driver, and what they lack is a player.

They navigate by `CityGrid.gd`, the same layout table `build_map.gd` builds from, so a
civilian's idea of where the pavement is comes from the constants that put the pavement
there. Pedestrians walk a pedestrian graph -- along the sidewalk ring, across only at
the painted zebras, and fleeing follows the same rules -- while traffic drives junction
to junction on lane points offset to the right of the centre line, which is what the
road kit's double yellow is asking for.

The interesting constraints turned out to be about *not* interfering:

- **They must not block a click.** Own collision layers, excluded from the picking ray.
  Marking them unselectable is not enough — the ray still stops on them, so a shopper
  between the camera and an officer makes that officer unclickable.
- **They must not gridlock.** Traffic stops for the player; the player drives through
  traffic. Mutual collision deadlocks the moment a patrol car noses into a queue, and
  being unable to reach a shout because a taxi is in the way is the worse failure.

## Handling and detail

Three rounds of play feedback, each traced to a measurable cause rather than tuned by
feel:

| Complaint | Cause | Result |
| --- | --- | --- |
| Traffic piling up at junctions | Two cars meeting each held the other in its yield cone; both stopped forever | 6 of 9 cars were permanently stalled → 9 of 9 moving |
| Traffic swinging into oncoming lanes | Aiming only at the far end of a street, a car leaving a turn wide corrected over 30m | 16 of 181 samples over the centre line → **0 of 170** |
| Player vehicles "struggle around corners" | Speed was only cut once the car was *already* turning, so it arrived at full speed | Apex speed 17.8 → **9.5 m/s**, journey time unchanged |
| Traffic crossing the yellow line turning left | The junction-to-junction scheme had no waypoint *inside* the junction, so a left turn chorded across the oncoming halves of both streets | An apex waypoint on the driver's own quadrant; a staged left turn now stays wholly east of the exit street's centre line |

The last one is worth stating in physical terms, because it is not a tuning number:
grip caps the tightest circle a car can hold at `v² / max_lateral_accel`. At 26 m/s
that is **47m, and a junction is 10m across** — the turn was not possible, so the car
overshot and got re-routed the long way round. The autopilot now looks along the
navigation path, works out what each corner can be taken at from the car's own
geometry, and brakes early enough to arrive at that speed.

## Dispatch

**One station**, on the police forecourt, stocking all six types — patrol car,
ambulance, fire engine, officer, paramedic, firefighter. Emergency 4 has a house per
service; this map has one yard with everything parked on it, and splitting the roster
across the hospital would have bought a longer walk and nothing else. The hospital
stays what it already was — where casualties are delivered.

As shipped in phase 14 the roster was a fixed issue — 4 patrol cars, 3 ambulances,
6 of each crew, with the starting shift counting against it. **The career economy
(below) replaced the issue with ownership**: the fleet is whatever has been bought,
`available` is what is owned minus what is standing on the map, and prices are the
new cap. The two lessons that phase left stand unchanged:

Types are **derived, not declared**. A unit's service plus whether it is a vehicle names
which of the six it is, so any two units of a type look identical to the station
without either carrying a tag.

Two things it turned up:

- Spawn slots have to be **checked**, not assumed. The forecourt already holds seven
  units; two dispatched in the same breath were handed the same spot and shoved each
  other across the yard.
- The dispatch rows started as pills and made the bar **190px instead of 148**, because
  a `PanelContainer` grows to fit its contents and the bar grew with it — quietly
  clipping the controls card underneath. They are a flat list now. **The command
  tiles repeated the lesson in August 2026**: a seventh verb wrapped the tile row,
  the bar grew to 176px, and the CONTROLS chip above it silently stopped being
  clickable. The command block is now sized for the fattest selection in one row,
  and a check pins the bar's height with the ambulance selected.

### A unit going home drives it properly

Returning is not a shout, so a recalled vehicle **runs dark, holds the limit and keeps
to its own lane**. An order now says whether it is a response; the vehicle reads that for
its lightbar and its speed ceiling, because a vehicle has no way of knowing on its own
whether it is going to something or coming back from it.

Lane discipline needed routing rather than a flag. The navigation mesh covers the full
width of every road, so a car left to it drives down the **middle** and cuts the corners
off junctions. A returning vehicle is routed junction to junction instead, two waypoints
per street offset to the right — the same scheme the ambient traffic drives, and they now
share the constants.

| | Samples over the centre line |
| --- | --- |
| Left to the navigation mesh | 154 of 858 — **18%** |
| Routed in lane | 48 of 791 — **6%** |

The residual 6% is turn arcs, which reach past the junction box. They are counted
deliberately: excluding them made the check pass whether or not the route was in lane at
all, which is the more useful thing to know. A second check asserts the **waypoints**
directly, because sampling a drive can only ever say "mostly".

## Roles

The phase that makes "send the right unit" mean anything. Until now every officer offered
both Treat *and* Extinguish, so the choice of unit never mattered.

The table below is where it stands now, with phase 19's fire service in it:

| Service | Verbs |
| --- | --- |
| **Police** — officers, patrol cars | Move, Apprehend, Escort, Extinguish, Secure, Board, Stop — all on the officer; a car carries two prisoners |
| **Medical** — paramedics, the ambulance | Move, Treat, Collect (the stretcher run), Board, Stop; the ambulance carries and delivers |
| **Fire** — firefighters, the engine | Move, Extinguish, Cool, Free, Board, Stop; the engine carries the crew, the hose and a foam tank |

Gating is **hard**: an officer is not offered Treat at all, so right-clicking a casualty
with one selected produces a **Move** order. Sending the wrong unit is a wasted trip
rather than a slower one.

It needed no new machinery, which is the payoff from phase 0's scoring ladder. An ability
that is simply not in a unit's list can never win a right-click and never gets a command
tile. `Unit.service` was already there from the interface work — this is that same field
finally deciding something. The forecourt crew changed from four officers to two and two,
because a shift of four officers could not finish the shout it starts with.

**Secure** is the one verb that must be armed. It applies to any patch of ground, so left
to score it would swallow Move and an officer could never be sent anywhere without
cordoning it off. `Ability.can_target()` is the seam: it defaults to what `score()` says,
and Secure overrides it to accept only a deliberately armed click.

The cordon has **no collision**. A ring of bollards across the road would trap the
ambulance the officer put it there to make room for — keeping the public out is a
decision the crowd makes, and civilians now check cordons before fires.

**The paramedics wear police uniforms**, and that is the pack's gap rather than a choice:
POLYGON City ships police characters and nothing else. What makes them paramedics is their
service — medical green on the avatar, the selection ring and the map dot, and being the
only unit on the map that can treat anybody. No amount of code fixes the jacket.

## Calls

The phase that turns a body on a map into a **job**. An incident is a thing on fire; a
call is the shout — a kind, a street address, an age, and whether anyone has reached it.

Grouping is the whole point. One fire left alone becomes eight, and eight rows on a
board would be eight jobs when it is plainly still one. Incidents within 14m of each
other are one call, so a spreading fire stays a single line — and a casualty beside it
silently upgrades that line from **Fire** to **Fire, casualty reported**, because kind
and position are re-read from whatever the call holds rather than declared once.

Addresses come out of the grid for free. Four road bands per axis means four avenues and
four streets, so every point in the district has a nearest crossroads, and the board
reads *"Fire, casualty reported — 3rd Ave & Pine St"* rather than a set of coordinates.

The board is passive in exactly the way the mission is: it watches `node_added` rather
than being told, so nothing on the map registers with it. The mission still reads
incidents directly, deliberately — the shout works and is well covered, and keeping the
board a view rather than the authority means it cannot be what breaks it.

Two ordering faults it turned up, both of the kind that pass by luck:

- `node_added` fires from **inside** `add_child`, and a spreading fire sets its position
  *after* being added — so reading the position there put every spread fire at its
  parent's feet. Close enough to group correctly by accident, and it would have stopped
  being so the day something spawned further from its parent.
- An incident that is **freed** rather than resolved emits nothing, so the call holding
  it sat on the board forever with a list of dangling references.

## Freeplay

The phase that turns a worked shout into a **shift**. `F2` starts it: for five
minutes `Director.gd` opens calls at plausible places — a collapse on a pavement
tile, a kerbside fire, a two-casualty **road traffic collision** at a crossroads —
and the mission scores the response instead of judging a single shout.

Everything it needed already existed, which was the bet the last three phases made:
the call board to score off, roles to make the choice of unit matter, a finite
roster to make it cost something. The director turned out to be closer to *stopping*
things than starting them — fires already spread and casualties already decline, so
its whole job is a cap on simultaneous calls (3), a breather after one closes (8s),
and placement that keeps clear of both forecourts and every open scene. As shipped it
never opened a building fire — there was no appliance and no firefighter to buy, so
every fire it created was one a patrol car's extinguisher could honestly deal with.
Phase 19 turned that ban into a **career gate**: buildings and rescues enter the draw
once the station owns both an engine and a crew, and the underlying rule is unchanged —
never set the district a job the roster cannot answer.

**Scoring is where calls finally become authoritative.** The mission had read raw
incidents since phase 5 — deliberately, so the board stayed a view and could not
break the shout. In a scored shift that inverts: 50 a fire out, 100 a casualty
delivered, −150 lost, plus a **response bonus** per call cleared — full inside a
10-second grace, sliding to a floor of 25% for a call that sat waiting. The call
already knew its age; it now records the age at which its status first turned
`ON_SCENE`, and that gap is what the bonus is paid on. Losing a casualty costs
points rather than the shift — `fail_on_casualty_lost` was exported with exactly
this softer mode in mind, back in phase 5.

Time running out does not end a shift with a job on the board: no new calls open,
and the debrief — `SHIFT COMPLETE`, score, calls cleared and failed, delivered and
lost — waits for the last call to close.

Two shapes worth recording:

- **An RTC is casualties plus a name.** Grouping and addressing were already free —
  two bodies in one junction are one call at one crossroads. What was missing was
  the title: two casualties read "Medical emergency", which undersells a collision.
  `Incident.flavour` carries the name, and the call prefers it over its derived kind.
- **A vacuous check, caught at review.** "New calls open apart from open ones" can
  never fail measured off the live board — the board's own 14m grouping forbids two
  open calls that close together, whatever the director does. The check that means
  something is the invariant between the constants: the director's 25m spacing must
  exceed the board's 14m grouping, or a "new" call silently joins the scene it was
  meant to be distinct from.

## The interface

The phase aimed squarely at Emergency 4 rather than at "an RTS demo". It shipped as a
solid **docked bar** across the bottom — portrait, roster, command tiles, dispatch — with
the world keeping everything above it. In August 2026 that bar was unpicked into
**panels floating in the corners**, on the user's supplied kit and reference layout, with
the city visible between them; each panel stops the mouse over itself, the layers between
them ignore it, so a click that lands on a panel is a click on the interface and never
also an order out in the street. See "The interface onto the user's UI kit" above for how
that was done without moving a single node in the tree.

What replaced what:

| Before | Now |
| --- | --- |
| Two floating labels of status text | A portrait: avatar, name, speed, crew, current order |
| Nothing showing the selection | Every unit under command, as a strip of avatars |
| Text buttons reading "Ext" / "Brd" | Command tiles with hotkeys, in keyboard order |
| Incidents were dots on the minimap | Pills naming each one, its state and its age — click to jump |
| A minimap of drawn rectangles | An overhead render of the actual district |
| A HUD in fixed screen pixels | Laid out for 1600x900 and scaled to any window |
| Clock and tallies in a corner | A status strip across the top: time, and what is outstanding |
| `theme_override_*` on every node | One generated `Theme.tres`, one `Palette.gd` colour table |
| Styleboxes drawn in code | The user's UI kit: 114 nine-sliced frame vectors, Rajdhani + Barlow |
| One docked bar owning the bottom 176px | Panels floated into the corners, city visible between |
| The pause menu reachable only by `P` | A score strip top-right with pause and settings buttons |
| A hint label floating over the middle of the city | An objective bar in the top-left corner |

### Unit avatars are real renders

Each is a photograph of the same prefab that is driving around the map, shot by
`build_portraits.gd` — one camera angle, one lighting rig, and **one frame size shared
across the whole group**, sized from the largest member. Every vehicle is shot
identically *and* keeps its true size relative to the others, so the ambulance is
visibly the big one. Framing each to its own bounds would have made a hatchback and a
van the same size on screen, which is exactly the pattern this avoids.

It has the same trap as the map generator: **it must run with a window.** Rendering goes
through a `SubViewport`, and headless is the dummy driver — every capture comes back
empty and the portraits save blank. A missing portrait falls back to a drawn outline, so
nothing breaks; it just quietly looks worse. A test now asserts every unit has one.

The **minimap** is the same idea at map scale: an overhead render of the district rather
than a lattice of drawn rectangles, so the block that looks like a hospital is the
hospital. It has to be orthogonal, and its camera basis has to be written out longhand
— looking straight down leaves the up vector colinear, and `look_at` then picks an
arbitrary roll, which is the trap that once put the entire road kit in sideways. Here it
would have rotated the whole map silently under the markers.

Everything that is *not* a photograph now comes from the icon pack (August 2026):
one white 64px PNG per symbol key, tinted per panel, curated out of the 4,890-icon
pack `.gdignore`d under `Assets/padding/`. The original drawn primitives stay in
`Glyph.gd` as the fallback for any key without a texture, and a check asserts none
is quietly falling back. One texture serves a 54px tile, a 38px avatar and a 22px
pill. The controls card draws the keyboard as keycaps, sectioned by function, and
ships closed behind a visible CONTROLS chip — F1 is its shortcut, not a secret.

### The roster is a control, not a readout

It lists the whole shift rather than mirroring the selection, so the parked ambulance can
be sent from the bar without first finding it in the street. Fill carries state: pale is
standing by, solid is working, faded is riding in a vehicle, a dark ring is selected.

Membership comes from a new `Unit.service` — police, medical, fire, or none — which is
also what colours the avatars and the map dots. It is **identity, not capability**:
phase 13 reads the same field to gate abilities, but today it says who a unit is, not
what it can do. Civilians and traffic are `NONE`, which is what keeps 26 shoppers out of
the roster.

### Small things that were load-bearing

The generated command bar survived the rewrite intact: tiles are still built from
whatever abilities the selection advertises, so a new verb appears — with its key bound
— without touching a UI file. What is new is that `Ability` declares its own `icon()`
and `hotkey()`, and that the tile grid and the keyboard resolve against **one** list on
the controller, so the key printed on a tile is always the ability that tile runs.

Hotkeys are `Z X C V B N M`, which looks arbitrary and is not: the camera polls
`W A S D` and `Q E` through `Input.get_vector` every frame, so those keys pan and rotate
whether or not an event was consumed. `F`, `R`, `Esc` and `1`–`9` are spoken for too.

**Lightbars** flash while a vehicle is navigating and go dark on arrival. The prefabs
model the bar into the hull mesh and share one palette atlas, so there was nothing to
switch on — a pair of emissive beads sit on the modelled bar instead, positioned by
reading the hull's own vertices near the roof peak. The **ambulance's rear doors** swing
open when anyone gets in or out; only it has them as separate meshes, so it is a no-op
everywhere else.

---

## Asset pack: POLYGON City

At `Assets/Synty/PolygonCity/` — **337 prefabs, 412 pre-extracted meshes, 51 MB**
(813 MB as delivered). Integrated 2026-08-04.

It arrived as a **complete Godot project** rather than an asset folder, with its own
`project.godot` and every prefab referencing a path that did not exist from this
project's root. Fixed by lifting the inner asset folder up so those paths resolve, then
deleting the wrapper. `SourceFiles/` (766 MB of FBX/OBJ/Maya) was removed; Godot never
needed it, since the meshes ship pre-extracted as `.res`.

Two things about it shaped everything since:

- **The character rigs are already retargeted** to `SkeletonProfileHumanoid`, with bone
  names identical to the Starter rig. So the 43-clip Universal Animation Library drives
  every character with no bone map and no importer changes. That was the single biggest
  risk in the original plan and it turned out to be free.
- **The kit is a strict 5m grid** — every ground tile, façade course and roof cap
  occupies `x[0,5] z[-5,0]` in its own local space. That one regularity is what let the
  whole district be generated rather than assembled by hand.

Watch out for the road kit: it uses the **opposite facing convention** to the buildings
(markings on the `+X` edge, street running along `Z`, against façades facing `+Z`). Get
it wrong and every road marking and crossing sits at right angles to its street.

### What is used

- **Ambulance, police car** — in play, with working lightbars and doors
- **Road and sidewalk kit** — in play; the roads *are* the vehicle pathfinding graph
- **Civilian traffic** — in play; all six bodies drive the grid in lane
- **Pedestrians** — in play; all seven outfits walk the pavements and flee fires
- **`Sign_Hospital`, `Sign_Police`** — in play, mounted on the building faces (they are
  wall fascia boards, not pole signs)
- **Hydrants** — drawn into the street-furniture batches *and* remembered as nodes: an
  appliance refills its tank beside one. The first scenery in the project to earn a
  mechanic
- **Cones, barriers, benches, lamp standards, bus stops** — placed as decoration, still
  awaiting a mechanic to use them

### Gaps

- **No fire engine, and no firefighter or paramedic uniforms.** Police is the only
  service the pack dresses properly. The fire service exists and is real underneath —
  what it wears is the patrol car's hull and `Character_Male_Police`, both folded
  through the pack's orange palette, and paramedics are in police blues. No amount of
  code fixes a jacket; it needs another pack. Swapping one in is a line each: the
  `prefab` in `build_vehicles.VEHICLES`, the `source` in `build_character.gd`, and the
  portrait entries.

---

## Lessons that cost time

- **Build the map with a window, not `--headless`.** The district is drawn with
  `MultiMeshInstance3D`, which keeps its transforms in the RenderingServer — the dummy
  driver under `--headless` discards them. The build reports success, the scene saves,
  every buffer comes back empty, and the city renders as *nothing*. Navigation still
  bakes correctly, because it reads colliders, which is what makes it so quiet.
- **Picking is a camera ray, so anything solid eats clicks.** Three times, in different
  disguises: a collider taller than its building, an opening camera focused on a block
  *centre* (which puts it over the roof, with the units below it), and pedestrians
  standing in the line of sight. The game briefly shipped with all seven starting units
  unselectable. A test now checks exactly that, first, before anything moves.
- **Read a piece's orientation from a plan view, never a raking one.** A top-down
  `look_at` has a colinear up vector, so Godot picks an arbitrary roll and the contact
  sheet renders at an unknowable rotation. Trusting it put the entire road kit in at
  right angles to its streets.
- **A resource saved to disk is not a resource anyone references.** `ResourceSaver.save()`
  writes the file and leaves the in-memory object pathless, and `PackedScene.pack()`
  inlines whatever it cannot point at. `build_character.gd` had extracted Synty's 43-clip
  animation library to its own file since the day it was written, said so in its comments,
  and then embedded a private 3 MB copy of it in all eleven character scenes anyway. It
  cost 315 ms to parse each one: five seconds to open the tutorial, two thirds of a second
  every time a mission put a person on the map. One `take_over_path()` call, and a rebuild,
  took the eleven from 3,461 ms to 66 ms and the tutorial's first frame from 5,770 ms to
  28 ms. Writing the library **binary** rather than text did most of the rest — the same
  clips are 313 ms of text parsing or 7 ms of binary. Nothing about the game looked wrong
  in either state, which is why it stood for months and why it is now checked.
- **Measure the fault, do not tune by feel.** Every handling complaint above was
  reproduced headlessly and quantified before anything changed — which twice showed the
  first diagnosis was wrong, and once showed the fix was doing nothing at all.
- **Check the harness before believing it.** One measurement reported that the ambulance
  "could not corner" when the patrol car from the previous run was parked on the finish
  line. Two interface checks later turned out to pass with their fix deleted — one
  because the thing it excluded had already been cleared from the map by the time it
  ran. A test only counts once it has been *seen* to fail.
- **pack() drops property overrides on instance children unless they are
  owner-flagged.** The generator assigned the minimap's camera path on a node inside
  the instanced HUD scene; the saved scene silently had none, and the shipped minimap
  ignored every click for months. No behavioural test covered it, nothing errored --
  the panel just quietly did less than the README said. The fix is a runtime fallback
  to the current 3D camera, plus the click test that was always missing.
- **A seeded generator is not reproducible if one call is not.** `build_map.gd` seeds
  its RNG, but the crowd was placed with `Array.shuffle()`, which draws from Godot's
  *global* random state and ignores that seed. The district looked stable because only
  the crowd moved; it surfaced as a picking test failing on a build that had changed
  nothing near it.
- **The map bakes what the vehicles are, so regenerate it too.** Changing a collision
  mask in `build_vehicles.gd` and regenerating the vehicle scenes changed nothing:
  `Playground.tscn` stores every instanced car with its properties written out, so
  the old mask was still what loaded. Measuring the *runtime* value rather than
  trusting the file is what found it. **build_vehicles → build_map, in that order.**
- **"It never happened in this window" is not "it cannot happen".** The first
  interpenetration check sampled the ambient fleet for ten seconds and passed
  happily with collision switched back off, because no two cars happened to cross in
  that window. Replaced with a staged one — drive a car at a parked one with the
  avoidance disabled — which reports 0.1m the moment the masks are wrong.
- **A rule with no check is a rule you cannot claim.** Sabotaging the junction
  give-way produced no red at all: the whole suite passed without it. It needed its
  own check (two cars converging on one crossroads) before it could be said to do
  anything.
- **A seeded stream is a contract — cosmetic draws need their own.** Adding one
  colour pick per parked car to the generator's RNG shifted every placement drawn
  after it, and the same pick on a traffic car's routing RNG changed its route:
  twice in one afternoon, a layout the tests had proven clean started failing over
  paint. Anything decorative draws from a dedicated stream now, so a colour can
  never move a car.
- **An alt palette is a texture atlas, not a colour.** The same material paints two
  meshes two different colours, because each mesh's UVs choose which swatch of the
  atlas they land on. Reading the material's name tells you nothing about what comes
  out: `PolygonCity_04_A` is orange on the patrol car, charcoal on the van and olive
  on the character rig. It shipped a black fire engine and a green fire crew, and
  neither was noticed for months, because there is nothing in the code to notice —
  the colour only exists once it is rendered. The fix that generalises is to
  **sample**: average the albedo at the mesh's own UVs and assert what you claim.

---

## Next steps

Moved to `NEXT.md`, so there is one place to look for what is still to do rather than
two that drift apart. This section deliberately keeps no list of its own — it had one
once, and it went stale enough to contradict the phase table at the top of this file.
