extends SceneTree

## Synthesises the game's placeholder sounds as 16-bit mono WAVs.
##
##   godot --headless --path . --script res://Game/build_audio.gd
##
## The project ships no recordings and buying a sound library was not the point, so
## every sound here is written out sample by sample -- the same way the two-tone
## siren was. They are honest placeholders: an engine that is clearly an engine at a
## glance, a radio tone that reads as a radio tone. Drop a recording in over any of
## them and nothing else changes, which is the whole reason they are files rather
## than generators wired into the game.
##
## **Loops have to close.** A tone whose buffer ends mid-cycle clicks once per loop,
## and at an engine's loop length that is a rattle. Every looping sound here is an
## exact whole number of cycles of its own fundamental, which is why the durations
## look arbitrary.

const OUT_DIR := "res://Game/Audio/"
const RATE := 22050


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_write("engine.wav", _engine())
	_write("crackle.wav", _crackle())
	_write("city.wav", _city())
	_write("radio.wav", _radio())
	print("done -- run --import before the game can load them")
	quit()


## A diesel idle: a low fundamental with its first harmonics and a little roughness.
## 55Hz over exactly 22 cycles, so the loop closes on a zero crossing.
func _engine() -> PackedFloat32Array:
	var samples := _buffer(22.0 / 55.0)
	var noise := RandomNumberGenerator.new()
	noise.seed = 4
	for i in samples.size():
		var t := float(i) / RATE
		var value := 0.0
		# Harmonics thin out up the series, which is what makes it read as an engine
		# rather than as an organ note.
		for harmonic in [1.0, 2.0, 3.0, 4.0, 6.0]:
			value += sin(TAU * 55.0 * harmonic * t) / (harmonic * 1.6)
		value += noise.randf_range(-0.06, 0.06)
		samples[i] = value * 0.32
	return samples


## Fire: a broadband hiss with pops scattered through it. The hiss is stationary so
## the seam is inaudible; the pops are kept clear of both ends for the same reason.
func _crackle() -> PackedFloat32Array:
	var samples := _buffer(2.0)
	var noise := RandomNumberGenerator.new()
	noise.seed = 11
	var smoothed := 0.0
	for i in samples.size():
		# A one-pole low-pass on white noise: cheaper than a filter bank and enough
		# to take the fizz off so it sounds like burning rather than like static.
		smoothed = smoothed * 0.72 + noise.randf_range(-1.0, 1.0) * 0.28
		samples[i] = smoothed * 0.22

	for pop in 26:
		var at := int(noise.randf_range(0.06, 0.94) * samples.size())
		var length := int(noise.randf_range(0.004, 0.02) * RATE)
		var loudness := noise.randf_range(0.25, 0.7)
		for i in length:
			if at + i >= samples.size():
				break
			# Exponential decay: a spit, not a beep.
			var decay := exp(-float(i) / (length * 0.28))
			samples[at + i] += noise.randf_range(-1.0, 1.0) * loudness * decay
	return samples


## The district itself: a low rumble under a soft wash. Two close fundamentals so it
## drifts slightly instead of sitting still. 40Hz and 45Hz both close over 4s.
func _city() -> PackedFloat32Array:
	var samples := _buffer(4.0)
	var noise := RandomNumberGenerator.new()
	noise.seed = 7
	var smoothed := 0.0
	for i in samples.size():
		var t := float(i) / RATE
		smoothed = smoothed * 0.9 + noise.randf_range(-1.0, 1.0) * 0.1
		var rumble := sin(TAU * 40.0 * t) * 0.5 + sin(TAU * 45.0 * t) * 0.35
		samples[i] = (rumble + smoothed * 0.5) * 0.12
	return samples


## Dispatch: two short tones with the squelch either side, the shape every radio in
## every control room has. Not looped -- it fires once per call.
func _radio() -> PackedFloat32Array:
	var samples := _buffer(0.44)
	var noise := RandomNumberGenerator.new()
	noise.seed = 21
	for i in samples.size():
		var t := float(i) / RATE
		var value := 0.0
		if t < 0.09:
			value = sin(TAU * 1180.0 * t) * 0.5
		elif t > 0.12 and t < 0.24:
			value = sin(TAU * 880.0 * t) * 0.5
		# Squelch on the tail, so it ends like a released key rather than a cut tape.
		if t > 0.24:
			value += noise.randf_range(-1.0, 1.0) * 0.18 * exp(-(t - 0.24) * 22.0)
		# Short fades at both ends: a tone that starts at full amplitude clicks.
		var edge := minf(t, maxf(0.44 - t, 0.0)) / 0.01
		samples[i] = value * clampf(edge, 0.0, 1.0)
	return samples


func _buffer(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * RATE))
	return samples


## Writes a RIFF/WAVE file: 16-bit mono PCM, which is what Godot's importer wants
## and what AudioStreamWAV.data holds at runtime.
func _write(file_name: String, samples: PackedFloat32Array) -> void:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		pcm.encode_s16(i * 2, value)

	var file := FileAccess.open(OUT_DIR + file_name, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % file_name)
		return
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + pcm.size())
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)          # PCM header length
	file.store_16(1)           # format: uncompressed PCM
	file.store_16(1)           # channels: mono
	file.store_32(RATE)
	file.store_32(RATE * 2)    # bytes per second
	file.store_16(2)           # block align
	file.store_16(16)          # bits per sample
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(pcm.size())
	file.store_buffer(pcm)
	file.close()
	print("  %s  %.2fs" % [file_name, float(samples.size()) / RATE])
