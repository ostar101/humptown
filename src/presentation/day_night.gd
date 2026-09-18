class_name DayNight
extends RefCounted
## How the world looks at a given time of day (D-032): the tint laid over the
## whole outdoor scene, and how brightly the street lamps burn.
##
## Pure functions of the minute of day, so the look of any hour is testable
## without a scene, and nothing about it is stored or saved — load a game at
## 23:00 and it is dark because it is 23:00, not because something remembered.
##
## The tint is a `CanvasModulate` colour: it multiplies everything drawn in the
## world, which is exactly what dusk does. The HUD sits on its own
## `CanvasLayer` and is untouched. Lamps are `PointLight2D`s, which a
## `CanvasModulate` does not dim — so they are what still shines at night.
##
## The keyframes suit the calendar the game starts on, early March at sixty
## degrees north: light by seven, dusk around six, properly dark by nine.

## (minute of day, tint). Must start at 0 and be in order; the last key wraps
## round to the first, so midnight is continuous.
const KEYS: Array = [
	[0, Color(0.30, 0.34, 0.54)],
	[300, Color(0.30, 0.34, 0.54)],      # 05:00 still night
	[375, Color(0.74, 0.60, 0.66)],      # 06:15 dawn
	[450, Color(1.0, 0.96, 0.92)],       # 07:30 early light
	[540, Color(1.0, 1.0, 1.0)],         # 09:00 full day
	[1020, Color(1.0, 1.0, 1.0)],        # 17:00
	[1110, Color(1.0, 0.80, 0.62)],      # 18:30 golden hour
	[1185, Color(0.56, 0.52, 0.72)],     # 19:45 blue hour
	[1275, Color(0.30, 0.34, 0.54)],     # 21:15 night
]

## Brightness below which the lamps come on, and the brightness at which they
## are fully lit. Tying them to the tint rather than to the clock means a lamp
## is never burning in daylight or dark under a night sky, whatever the
## keyframes are later tuned to.
const LAMPS_START_BELOW := 0.86
const LAMPS_FULL_AT := 0.45


## The world's tint at a minute of day, interpolated between keyframes.
## Fractional minutes are allowed; anything outside a day wraps.
static func tint_at(minute_of_day: float) -> Color:
	var m := fposmod(minute_of_day, float(GameClock.MINUTES_PER_DAY))
	for i in KEYS.size():
		var here: Array = KEYS[i]
		var next: Array = KEYS[(i + 1) % KEYS.size()]
		var start := float(here[0])
		var end := float(next[0]) if i + 1 < KEYS.size() else float(GameClock.MINUTES_PER_DAY)
		if m >= start and m < end:
			var weight := (m - start) / (end - start)
			return (here[1] as Color).lerp(next[1] as Color, weight)
	return KEYS[0][1]


## How brightly the street lamps burn, 0 (off) to 1 (full), for a tint.
static func lamp_energy_for(tint: Color) -> float:
	var brightness := tint.get_luminance()
	return clampf((LAMPS_START_BELOW - brightness) / (LAMPS_START_BELOW - LAMPS_FULL_AT), 0.0, 1.0)


static func lamp_energy_at(minute_of_day: float) -> float:
	return lamp_energy_for(tint_at(minute_of_day))
