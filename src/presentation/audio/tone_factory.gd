class_name ToneFactory
extends RefCounted

const MIX_RATE := 48000
const AMPLITUDE := 0.22
const TONE_SPECS := {
	&"button_down": {"start_hz": 360.0, "end_hz": 300.0, "duration_ms": 55},
	&"correct": {"start_hz": 620.0, "end_hz": 880.0, "duration_ms": 180},
	&"wrong": {"start_hz": 260.0, "end_hz": 190.0, "duration_ms": 150},
	&"health_loss": {"start_hz": 220.0, "end_hz": 150.0, "duration_ms": 210},
	&"reward": {"start_hz": 520.0, "end_hz": 1040.0, "duration_ms": 260},
}

func create_sfx(sfx_id: StringName) -> AudioStreamWAV:
	if not TONE_SPECS.has(sfx_id):
		return null
	var spec: Dictionary = TONE_SPECS[sfx_id]
	var sample_count := maxi(1, int(MIX_RATE * int(spec.duration_ms) / 1000.0))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for index in sample_count:
		var progress := float(index) / float(maxi(sample_count - 1, 1))
		var frequency := lerpf(float(spec.start_hz), float(spec.end_hz), progress)
		phase += TAU * frequency / MIX_RATE
		var attack := clampf(progress / 0.06, 0.0, 1.0)
		var release := clampf((1.0 - progress) / 0.18, 0.0, 1.0)
		var envelope := minf(attack, release)
		var waveform := sin(phase) + 0.18 * sin(phase * 2.0)
		var sample := clampi(roundi(waveform * envelope * AMPLITUDE * 32767.0), -32768, 32767)
		data.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
