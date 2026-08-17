extends RefCounted
class_name Palette

## Every colour the interface uses, in one place.
##
## Two things read this: `build_theme.gd`, which bakes the Control styling into
## `Theme.tres`, and the panels that draw themselves -- the minimap, the command tiles,
## the unit avatars. Without a shared table those two drift, and an ambulance ends up
## one green in the roster and a different green on the map.
##
## Constants rather than a resource because the drawing code needs them at run time and
## a Theme cannot carry arbitrary named colours.
##
## **The scheme is dark**, to a reference the player supplied in August 2026: near-black
## chrome, dark slate cards with a visible border, near-white text, saturated service
## accents.
##
## It was light before that, and the reason recorded here was real -- a dark *translucent*
## panel loses against a lit Synty shopfront. The reference answers that objection rather
## than ignoring it: every card is **opaque and bordered**, so what it sits over does not
## matter. If dark turns out to read badly at DAY, that finding belongs here, and the way
## back is this file rather than forty call sites.
##
## Two names now describe **roles rather than lightness**, and this is the one confusing
## thing in the file. `_PALE` is the muted fill behind a unit standing by -- on a dark
## scheme that is *darker* than the base colour, not paler. `_DEEP` is the ink drawn on
## top of it, and on a dark scheme that is *lighter*. Renaming them to `_MUTED` / `_INK`
## is the honest follow-up; it was left out of the restyle deliberately so that anything
## that looked wrong afterwards was known to be a colour and not a rename.
##
## Not touched by the inversion: [constant STREET] and [constant BLOCKS]. Those feed
## `build_minimap.gd`, which bakes `MinimapBase.png` and **needs a window** -- changing
## them headlessly would leave the palette and the baked image disagreeing.

# --- Chrome ------------------------------------------------------------------
#
# **These are the UI kit's tokens, to the byte** (`ui-kit/tokens/tokens.json`). The
# scheme was already in this family -- it was set from the same reference in August
# 2026, and `TEXT_DIM` was within one unit of the kit's `text.secondary` before anyone
# compared them -- so adopting the kit moved the chrome by a few points rather than
# repainting it. What it buys is that the drawn panels (minimap, tiles, avatars) and
# the *art* panels (every frame under `Game/UI/Kit/`) are now provably the same
# colours, instead of two sets that merely looked alike.
#
# The split to keep in mind: **chrome is the kit's, signals are the game's.** Below
# this section the service and marker colours stay as they were, deliberately. They
# are read over a lit 3D city, which is a different job from sitting on a dark panel,
# and the kit has no opinion about it.

## The docked bar. Opaque: it is the edge of the screen, not an overlay. `surface.bg`.
const BAR := Color(0.031, 0.051, 0.078)
## A section of chrome one step up from the bar. `surface.section`.
const SECTION := Color(0.051, 0.075, 0.106)
## Cards, in the bar and floating over the world alike. `surface.card`.
const CARD := Color(0.082, 0.118, 0.165)
## Recessed fill inside a card: an unarmed command tile, a progress track.
## `surface.inset-top`.
const WELL := Color(0.047, 0.071, 0.106)
## `stroke.default` -- the line around a raised surface, and the thing that actually
## separates a card from the bar in this scheme. The fills are only 1.16:1 apart; the
## edge is what the eye lands on. See the surface check in the suite.
const EDGE := Color(0.129, 0.176, 0.235)
## `stroke.soft` -- the line around a *recessed* surface, where the fill is already
## darker than its surroundings and the stroke is a hairline highlight rather than a
## border.
const EDGE_SOFT := Color(0.094, 0.133, 0.180)
## `stroke.bright` -- the lit edge of something under the pointer.
const HOVER := Color(0.180, 0.239, 0.310)
const PRESSED := Color(0.071, 0.314, 0.561)

# --- Primary ------------------------------------------------------------------
#
# The interface's own blue, for chrome that is *offering* something: a primary button,
# a selected row, the line under a live tab. Distinct from POLICE below, which is a
# service identity and belongs to units.

## `primary.base`.
const PRIMARY := Color(0.086, 0.408, 0.784)
## `primary.top` -- the lighter end of a primary button's gradient, and the fill of
## anything small enough that a gradient would be lost on it.
const PRIMARY_LIGHT := Color(0.165, 0.498, 0.878)
## `primary.line` -- a hairline of it, for underscores and focus edges.
const PRIMARY_LINE := Color(0.290, 0.612, 0.941)

# --- Text --------------------------------------------------------------------

const TEXT := Color(0.875, 0.906, 0.941)
## Labels, units, and anything the eye should skip on the way to the value.
const TEXT_DIM := Color(0.561, 0.627, 0.698)
const TEXT_DISABLED := Color(0.333, 0.388, 0.435)
## Cards carry their own contrast, so outlines are only for text with nothing behind it.
const OUTLINE := Color(0.02, 0.03, 0.05, 0.85)

# --- State -------------------------------------------------------------------

## Armed ability, destination marker, anything awaiting the player's next click.
const ACCENT := Color(0.941, 0.663, 0.231)
const SELECTED := Color(0.961, 0.722, 0.255)
const GOOD := Color(0.290, 0.871, 0.502)
const BAD := Color(0.937, 0.267, 0.267)
const WARN := Color(0.961, 0.620, 0.043)

# --- Services ----------------------------------------------------------------
#
# Three shades each: the solid fill for a unit that is working, a pale fill for one
# standing by, and a deep tone dark enough to be read as text or as a symbol on the
# pale fill. [method service] hands them out by Unit.Service.
#
# Fire is defined but nothing wears it: the City pack has no appliance and no
# firefighter, and dressing something else in fire colours would be the interface
# telling a lie about what can be dispatched.

const POLICE := Color(0.290, 0.620, 1.0)
const POLICE_PALE := Color(0.106, 0.200, 0.322)
const POLICE_DEEP := Color(0.612, 0.784, 1.0)

const MEDICAL := Color(0.239, 0.749, 0.420)
const MEDICAL_PALE := Color(0.075, 0.208, 0.141)
const MEDICAL_DEEP := Color(0.525, 0.890, 0.667)

const FIRE := Color(0.910, 0.318, 0.235)
const FIRE_PALE := Color(0.227, 0.102, 0.086)
const FIRE_DEEP := Color(1.0, 0.620, 0.541)

const CIVILIAN := Color(0.561, 0.631, 0.698)
const CIVILIAN_PALE := Color(0.137, 0.180, 0.227)
const CIVILIAN_DEEP := Color(0.765, 0.808, 0.851)

# --- Incidents ---------------------------------------------------------------

const FIRE_MARKER := Color(1.0, 0.541, 0.239)
const FIRE_MARKER_DEEP := Color(1.0, 0.796, 0.651)
const CASUALTY_MARKER := Color(0.937, 0.267, 0.267)
const CASUALTY_DEEP := Color(1.0, 0.659, 0.659)
## Behind the "N waiting" pill, so an outstanding call reads as urgent at a glance.
const ALARM_WASH := Color(0.227, 0.086, 0.125)

# --- World -------------------------------------------------------------------

const STREET := Color(0.965, 0.976, 0.969)
## City blocks on the minimap. Darker than the mockup's flat green because this map
## carries a whole lattice of streets rather than two, and the pattern only reads if
## the ground it is cut into is a clear step down from it.
const BLOCKS := Color(0.741, 0.808, 0.769)


# --- Spacing -----------------------------------------------------------------
#
# The gaps, named. Twenty-four `add_theme_constant_override("separation", ...)` calls
# across eleven different values grew here over twenty phases -- a scale that existed in
# somebody's head and nowhere in the code, so every new panel guessed at it afresh.
#
# **The container defaults in `build_theme.gd` are set from these.** The twenty-four
# existing overrides are *not* touched yet, and that is deliberate rather than unfinished:
# retuning a gap by two pixels inside `CommandBlock` rewraps the command tiles, which
# makes the bar taller, which covers whatever floats above it -- the trap that has caught
# this project six times. Even deleting an override that merely *matches* its default
# needs the container type read at each site, not pattern-matched.
#
# Collapsing them onto the scale is worth doing behind the generalised bar guard, one file
# at a time, checking after each. It is not worth doing in a batch, and it is not worth
# doing at all until something else in the interface needs to move.

const TIGHT := 3
const SNUG := 6
const STEP := 8
const WIDE := 12
const GAP := 18


## The three shades of a service, as fill / pale / deep.
static func service(kind: int) -> Array[Color]:
	match kind:
		Unit.Service.POLICE: return [POLICE, POLICE_PALE, POLICE_DEEP]
		Unit.Service.MEDICAL: return [MEDICAL, MEDICAL_PALE, MEDICAL_DEEP]
		Unit.Service.FIRE: return [FIRE, FIRE_PALE, FIRE_DEEP]
		_: return [CIVILIAN, CIVILIAN_PALE, CIVILIAN_DEEP]


## WCAG relative-luminance contrast ratio between two opaque colours, 1.0 (identical) to
## 21.0 (black on white).
##
## Exists so one check can guard a **class** of bug rather than an instance of it. The
## interface has twice shipped a colour written by hand at a call site that was right for
## the scheme at the time and wrong afterwards -- a 13% white progress track that was
## invisible on a white card, and near-black shop wells that survived the light scheme.
## A table of the (ink, ground) pairs the interface actually uses, each asserted to clear
## a bar, catches the next one without anybody having to notice it.
static func contrast(ink: Color, ground: Color) -> float:
	var a := _luminance(ink)
	var b := _luminance(ground)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


static func _luminance(colour: Color) -> float:
	var channels := [colour.r, colour.g, colour.b]
	var linear: Array[float] = []
	for value: float in channels:
		linear.append(value / 12.92 if value <= 0.04045
			else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


## Fades a colour without touching its hue -- for disabled tiles and idle rows.
static func dim(colour: Color, amount := 0.45) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * amount)
