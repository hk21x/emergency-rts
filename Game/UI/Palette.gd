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
## The scheme is light: pale chrome, white cards, dark text. It reads better over a
## bright Synty city than the dark one it replaced, and a white card with a saturated
## service colour on it stays legible against a lit shopfront in a way a dark
## translucent panel does not.

# --- Chrome ------------------------------------------------------------------

## The docked bar. Opaque: it is the edge of the screen, not an overlay.
const BAR := Color(0.929, 0.945, 0.961)
## Cards, in the bar and floating over the world alike.
const CARD := Color(1.0, 1.0, 1.0)
## Recessed fill inside a card: an unarmed command tile, a progress track.
const WELL := Color(0.929, 0.945, 0.961)
const EDGE := Color(0.847, 0.878, 0.906)
const HOVER := Color(0.886, 0.910, 0.933)
const PRESSED := Color(0.827, 0.859, 0.890)

# --- Text --------------------------------------------------------------------

const TEXT := Color(0.133, 0.188, 0.247)
## Labels, units, and anything the eye should skip on the way to the value.
const TEXT_DIM := Color(0.373, 0.420, 0.471)
const TEXT_DISABLED := Color(0.647, 0.686, 0.729)
## Cards carry their own contrast, so outlines are only for text with nothing behind it.
const OUTLINE := Color(1, 1, 1, 0.85)

# --- State -------------------------------------------------------------------

## Armed ability, destination marker, anything awaiting the player's next click.
const ACCENT := Color(0.937, 0.624, 0.153)
const SELECTED := Color(0.114, 0.620, 0.459)
const GOOD := Color(0.114, 0.620, 0.459)
const BAD := Color(0.886, 0.294, 0.290)
const WARN := Color(0.937, 0.624, 0.153)

# --- Services ----------------------------------------------------------------
#
# Three shades each: the solid fill for a unit that is working, a pale fill for one
# standing by, and a deep tone dark enough to be read as text or as a symbol on the
# pale fill. [method service] hands them out by Unit.Service.
#
# Fire is defined but nothing wears it: the City pack has no appliance and no
# firefighter, and dressing something else in fire colours would be the interface
# telling a lie about what can be dispatched.

const POLICE := Color(0.216, 0.541, 0.867)
const POLICE_PALE := Color(0.710, 0.831, 0.957)
const POLICE_DEEP := Color(0.094, 0.373, 0.647)

const MEDICAL := Color(0.114, 0.620, 0.459)
const MEDICAL_PALE := Color(0.624, 0.882, 0.796)
const MEDICAL_DEEP := Color(0.059, 0.431, 0.337)

const FIRE := Color(0.847, 0.353, 0.188)
const FIRE_PALE := Color(0.980, 0.780, 0.459)
const FIRE_DEEP := Color(0.522, 0.310, 0.043)

const CIVILIAN := Color(0.373, 0.420, 0.471)
const CIVILIAN_PALE := Color(0.847, 0.878, 0.906)
const CIVILIAN_DEEP := Color(0.220, 0.259, 0.302)

# --- Incidents ---------------------------------------------------------------

const FIRE_MARKER := Color(0.937, 0.624, 0.153)
const FIRE_MARKER_DEEP := Color(0.255, 0.141, 0.008)
const CASUALTY_MARKER := Color(0.886, 0.294, 0.290)
const CASUALTY_DEEP := Color(0.639, 0.176, 0.176)
## Behind the "N waiting" pill, so an outstanding call reads as urgent at a glance.
const ALARM_WASH := Color(0.988, 0.922, 0.922)

# --- World -------------------------------------------------------------------

const STREET := Color(0.965, 0.976, 0.969)
## City blocks on the minimap. Darker than the mockup's flat green because this map
## carries a whole lattice of streets rather than two, and the pattern only reads if
## the ground it is cut into is a clear step down from it.
const BLOCKS := Color(0.741, 0.808, 0.769)


## The three shades of a service, as fill / pale / deep.
static func service(kind: int) -> Array[Color]:
	match kind:
		Unit.Service.POLICE: return [POLICE, POLICE_PALE, POLICE_DEEP]
		Unit.Service.MEDICAL: return [MEDICAL, MEDICAL_PALE, MEDICAL_DEEP]
		Unit.Service.FIRE: return [FIRE, FIRE_PALE, FIRE_DEEP]
		_: return [CIVILIAN, CIVILIAN_PALE, CIVILIAN_DEEP]


## Fades a colour without touching its hue -- for disabled tiles and idle rows.
static func dim(colour: Color, amount := 0.45) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * amount)
