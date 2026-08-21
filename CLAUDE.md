# Emergency-RTS (Godot) — project instructions

An Emergency 4–style RTS demo. Godot 4.x, pure GDScript, no C#, Forward+ renderer.
Built on 4.6.3, verified on 4.7 (`/opt/homebrew/bin/godot` on this machine — plain
`godot` on PATH).

Read before working: `PROGRESS.md` (status + what each phase taught), `NEXT.md`
(what is left), `Game/README.md` (technical reference: how each system works and
the traps).

All 15 planned phases are done, and so are 16 (the world reacts), 17 (audio), 18
(game framing) and 19 (the fire service, on a real appliance and, since August 2026,
a real fire crew -- the POLYGON City Characters pack closed the last asset gap). **Phase 20 is done** -- the career
economy and, since August 2026, the campaign scenarios: three designed shifts picked
from the title card, each a timeline of calls against a par time. Everything else left
is in NEXT.md.

## Commands

| What | Command |
| --- | --- |
| **Run the test suite (fast)** | `godot --headless --fixed-fps 60 --path . --script res://Game/smoke_test.gd` |
| Parse-check one script | `godot --headless --path . --check-only --script res://Game/<file>.gd` |
| Boot gate (scene loads, scripts compile) | `godot --headless --fixed-fps 60 --path . --quit-after 2` |
| Refresh import/class cache | `godot --headless --path . --import` |
| Rebuild the tutorial scene (nav bake; works headless) | `godot --headless --path . --script res://Game/build_tutorial.gd` |
| Calibrate a held prop (**needs a window**) | `godot --path . res://Game/HandCalibration.tscn` |
| Play the game (opens a window) | `godot --path .` |

**`--fixed-fps 60` matters.** Without it the headless loop paces to real time and
the suite takes ~9 minutes; with it, **~60 seconds**, same fixed-step physics, every
check identical. Use it for every headless run except the generators below.

That figure said "~20 seconds" until August 2026 and had been wrong for a long time --
measured at 59s with no new checks in, on a suite that has roughly doubled in size since
the number was written. Re-measured at **1:08.63 wall clock** (63s user, 157% CPU) at 1295
checks, so it grows roughly with the check count and the number is worth re-taking rather
than trusting. **Do not take a runtime figure from a subagent's report**: three of them
quoted seven to ten minutes for this suite in August 2026 and none of it reproduced under
`time`. Most of the wall clock is a handful of end-to-end *drives*: the
simulated seconds are real seconds when the scene is the 6,700-node tutorial town.

## Verification rules

- **The suite is the arbiter.** 1308 checks, exits non-zero on failure. A change to
  `Game/` is not done until it is green. It **reports its own total** —
  `all checks passed (1308)` — so take the count from a run rather than from here or
  from memory; that number is why these documents have carried a stale figure twice.
- **The checks live in `Game/Tests/`, not in `smoke_test.gd`.** Fourteen section files
  plus `Tests/TestCase.gd` (the fixture and every helper), chained by plain script
  inheritance and ending at `smoke_test.gd`, which is now only the run order. One `self`,
  one set of fixture fields — a new check goes in the section file it belongs to and needs
  nothing else. The run still starts from `res://Game/smoke_test.gd`.
- **Every run prints a per-section tally** before the summary. That is the truncation
  detector: a section that silently loses a check moves its own line, and the line names
  the file to open. A tally that does not add up to the total fails the run.
- **Do not run the suite inline — delegate it.** Ask the `godot-test-runner` agent
  and get one line back. A full run is ~550 lines of output, and output in the main
  conversation is re-sent on every later turn, so a suite run early in a session is
  paid for dozens of times; a subagent's is paid once. The Stop hook
  (`.claude/hooks/stop-suite-gate.sh`) runs the full suite at the end of the turn
  anyway, and only when `Game/` actually changed — so running it by hand buys the
  same information twice.
- **A runtime error inside a check skips the rest of that check, silently.** The suite
  goes on and reports green; only the **check count** falls. That is the other reason to
  read the count from the run rather than trusting "all checks passed" — but the count is
  a *weak* witness, and August 2026 proved how weak: two checks had been stopping short
  for months and it cost three checks out of six hundred, which nobody notices. One was
  the only test of the dispatch panel's click path, and its helper had returned null on
  every call it had ever made. **Grep a run for `SCRIPT ERROR` from time to time.** It is
  the only signal that separates "all checks passed" from "all checks that still run
  passed".
- **A parse error exits 0.** Godot returns success when `--script` fails to *load*, so a
  broken suite reads as green from the exit code alone. The summary line is the only
  honest signal: no `all checks passed (N)` means no verdict, whatever the status was.
- **Judge by exit code / "all checks passed", not stderr.** Godot prints alarming
  `ObjectDB instances leaked` / `RID allocations ... leaked at exit` errors even on
  a fully green run. They are exit noise, not failures — do not chase them.
- **A new `class_name` needs `--import` once** before other scripts can reference
  it; until then every dependent script fails to parse with "not declared in the
  current scope". If a wall of parse errors appears after adding a class, refresh
  the cache before debugging anything.
- **Every new check must be seen to fail.** Revert the fix (or sabotage the
  behaviour), watch the check go red, restore. Several checks in this project's
  history passed with their fix deleted; NEXT.md "Working notes" has the specimens.
  **Delegate this to the `godot-check-sabotage` agent** — it is four suite runs per
  check and none of them needs to be in the conversation. It backs up before it edits,
  restores from those copies, and confirms green before reporting. (This line used to say
  "there is no version control here" -- **there is**: `git log` shows commits. The backups
  are still the mechanism the agent relies on, since it must restore mid-turn without
  disturbing uncommitted work, but git is a real second net and the agent was being told
  it had none.) It also reports *collateral*: a sabotage that reddens thirty
  checks broke the game rather than the behaviour, and proves much less than it looks.
- **Never run `godot-check-sabotage` in the background, and never alongside anything
  else that reads the tree — including an open Godot editor window.** The editor
  re-imports on file change, and a sabotage cycle deliberately breaks source for about a
  minute at a time, so the editor is reading and re-importing a tree that is a lie. It
  has now been live through seven cycles in August 2026 with no observable harm (every
  restore byte-identical by md5, every sabotaged run reddening only its target), so this
  is **note it and continue**, not abort — but say so in the report, because it is the
  first thing to suspect if a cycle ever produces an inexplicable result. That includes **resuming one with `SendMessage`**, which
  always launches in the background -- there is no synchronous continuation. The hazard is
  any path that starts the agent, not the `run_in_background` flag: an August 2026 turn
  ran every cycle correctly with `run_in_background: false`, then continued one with
  `SendMessage` and the Stop gate ran the suite against a tree with `cells = 1` injected
  into `TowTruck.tscn`, blocking on a failure that did not exist. If a cycle must be
  continued, hold the turn open with a background watcher that waits for the restore run
  to print `all checks passed` before letting the gate fire. It deliberately breaks source for a minute at a time, so
  for that minute the working copy is a lie. **Run the sabotaged step in the background
  deliberately and block on a `pgrep -f smoke_test.gd` until-loop** -- do not try to size
  a `timeout` around it. Two cycles in August 2026 overran a 590000ms and a 600000ms
  timeout and were pushed into the background with the tree still broken, which is the one
  state that must never be left unattended.
  **The cause of those overruns is not established.** The subagents that hit them reported
  runtimes of seven to ten minutes and blamed failing checks sitting out their full wait
  loops -- but a green run of the same suite measures **69s** by direct `time`, so raw
  suite runtime cannot explain an eight-fold overrun and that explanation does not survive
  measurement. Treat it as unexplained rather than solved. Backgrounding and polling does
  not race whatever the cause; a timeout does. Never end the turn while a sabotage is on
  disk. Backgrounding one raced the Stop gate,
  which ran the suite against the sabotaged tree and blocked the turn on a failure that
  did not exist. Run it synchronously, one at a time, and let it finish.
- **Measure a fault before fixing it** — reproduce headlessly and quantify. Twice
  the first diagnosis was wrong; once a fix was doing nothing.
- **A throwaway probe MUST repoint every `user://` path it writes.** `Station` saves the
  career on every purchase, so a probe that buys units overwrites the real
  `user://career.cfg` — the player's fleet and purse, gone, with no warning. Set
  `station.career_path = "user://probe-<name>-career.cfg"` **before** the first purchase
  and delete the file afterwards; the `probe-*-career.cfg` files already in the userdata
  folder are the convention. This was learned the expensive way in August 2026, on a
  probe written to measure HUD panel sizes, which had no business touching the books at
  all.

## The .tscn boundary

`Game/Playground.tscn` is **generated** by `Game/build_map.gd`; vehicles, characters
and civilians by their own `build_*.gd`. The rule for changes:

1. Edit the generator, and regenerate when possible — but the generators **need a
   window** (`godot --path . --script res://Game/build_map.gd`, no `--headless`):
   MultiMesh transforms live in the RenderingServer and the headless dummy driver
   silently writes an empty city / blank portraits.
2. When a window is unavailable, hand-edit the generated `.tscn` **and make the
   identical change in the generator**, so the next regeneration produces the same
   scene. This is how the Director node was added; it works, but the generator edit
   is not optional.
3. **Regenerate in dependency order: `build_vehicles.gd` → `build_map.gd`.** The map
   writes every instanced vehicle's properties into `Playground.tscn`, so changing a
   vehicle scene and regenerating only *it* leaves the map loading the old values —
   silently, since the scene file on disk looks right.
4. `HUD.tscn` is hand-authored — edit it directly.
5. Never modify anything under `Assets/Synty/`, `Assets/PolygonTown/` or
   `Assets/Particle_FX/`. They are vendor packs; the game adapts to them, not the
   other way round. A prefab from a second pack is reached by giving `build_vehicles`
   or `build_portraits` a full `res://` path instead of a bare name.

## Conventions

- Godot 4 GDScript, typed (`:=`, typed arrays), tabs, ~90-col lines. Doc comments
  are `##` and explain *why*, in the project's plain-prose voice — read a couple of
  existing files first and match them.
- The district's layout is the two band tables in `CityGrid.gd` (`X_BANDS`/`Z_BANDS`,
  deliberately irregular) — roads, blocks, junctions, addresses, traffic, crowd and
  director placement all derive from them. Change them and **regenerate the map**;
  checks pin the 260m size, the span variance and the parks. The pedestrian graph
  (`walk_moves`) and the zebra crossings derive from the same tables — civilians
  must never leave it, and a 7,200-sample check watches that they do not.
- Systems are **passive watchers** where possible: `Mission`, `CallBoard` hook
  `SceneTree.node_added` rather than being registered with. Keep new systems the
  same shape.
- Adding a verb = a new `Ability` (+`Order`); it gets its command tile, hotkey and
  right-click meaning from the scoring ladder with no UI changes. Hotkeys `Z X C V
  B N M G H J K L T Y U I O P` are the command keys; `W A S D Q E F R F1 F2 F3 F4 F5 Esc Enter
  Space 1-9` are taken. **`O` is the only letter still free** -- `P` went to Connect and
  `I` to Disarm and `O` to Clear in August 2026, so the next verb after that one has no
  key at all. A check sweeps every unit scene for a key that answers twice, for one the
  camera polls, and for one with no slot in `COMMAND_KEYS` -- it exists because `Clear`
  and `Lights` both sat on `J` until the recovery truck became the first unit to carry
  both, and nothing noticed.
  `F3` files a black-box record, `F4` toggles the navigation overlay, and `F5` opens
  the call spawner -- pick any call kind instead of waiting for the director's
  weighted roll.
- **`Esc` has three claimants and they are ordered deliberately**: disarm an armed
  ability, else close the shop, else open the pause menu. `GameMenu._input` runs
  *before* both of the others, so it asks `_escape_is_spoken_for()` first rather than
  leaving the outcome to tree order. Anything new that wants `Esc` joins that guard.
  Sabotaging it reddens ~150 checks, because a district that pauses when the player
  meant "cancel" stays paused for every check after it.
- Seeded randomness only: `RandomNumberGenerator` instances, never
  `Array.shuffle()` / global `randi()` in anything that must reproduce (the map
  build and the tests rely on it).
- Units: `Unit.service` is identity (POLICE / MEDICAL / NONE); capability gating is
  hard — a unit simply lacks the ability. Civilians/traffic are `NONE` and must
  stay unselectable and un-pickable (own collision layers, excluded from
  `PICK_MASK`).
- The map ships **quiet** — no scripted incidents; the district idles until F2 opens
  a shift. Freeplay (`Director.gd`) must stay **inert until `begin_shift()`**, and a
  director that can start on its own breaks dozens of checks at once (there are
  checks for exactly both).

## After any change

1. Fast suite green (command above).
2. Docs: `PROGRESS.md` / `NEXT.md` / `Game/README.md` updated if behaviour, checks
   or controls changed — including the check count, which the docs state.
