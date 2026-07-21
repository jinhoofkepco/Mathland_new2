class_name AudioService
extends Node

signal voice_finished(dialogue_id: StringName)
signal voice_missing(dialogue_id: StringName)

const ToneFactoryScript = preload("res://src/presentation/audio/tone_factory.gd")
const MANIFEST_PATH := "res://assets/audio/audio-manifest.json"
const BUS_SETTING_KEYS := {
	"master_db": &"Master",
	"music_db": &"Music",
	"sfx_db": &"SFX",
	"voice_db": &"Voice",
}
const VOICE_IDS: Array[StringName] = [
	&"moa_home_welcome",
	&"moa_tutorial_counting",
	&"moa_tutorial_number_bonds",
	&"moa_tutorial_ten_frame",
	&"moa_tutorial_base_ten",
	&"moa_tutorial_number_line",
	&"moa_tutorial_basic_operations",
	&"moa_reward",
	&"moa_level_up",
]
const MUSIC_IDS: Array[StringName] = [
	&"exploration_loop",
	&"concentration_loop",
	&"boss_loop",
]
const SFX_IDS: Array[StringName] = [
	&"button_down",
	&"button_release",
	&"correct",
	&"wrong",
	&"heart_loss",
	&"combo_1",
	&"combo_2",
	&"combo_3",
	&"boss",
	&"level_up",
	&"reward",
	&"manipulative_place",
]
const MIN_AUDIO_DB := -80.0
const MAX_AUDIO_DB := 0.0

var _tone_factory := ToneFactoryScript.new()
var _music_registry: Dictionary = {}
var _sfx_registry: Dictionary = {}
var _voice_registry: Dictionary = {}
var _voice_enabled := true
var _manifest_loaded := false
var _question_voice_requires_speaker := true
var _voice_blocks_input := false
var _current_music_id: StringName = &""
var _current_voice_id: StringName = &""
var _music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer

func _ready() -> void:
	_load_manifest()
	_ensure_players()

func _exit_tree() -> void:
	_current_music_id = &""
	_current_voice_id = &""
	for player in [_music_player, _sfx_player, _voice_player]:
		if player != null:
			player.stop()
			player.stream = null
	_music_registry.clear()
	_sfx_registry.clear()
	_voice_registry.clear()
	_manifest_loaded = false

func apply_settings(settings: Dictionary) -> bool:
	var pending_volumes := {}
	for key in BUS_SETTING_KEYS:
		if not settings.has(key):
			continue
		var value: Variant = settings[key]
		if not _is_valid_decibels(value):
			return false
		var bus_name: StringName = BUS_SETTING_KEYS[key]
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index < 0:
			return false
		pending_volumes[bus_index] = float(value)
	var has_voice_setting := settings.has("voice_enabled")
	if has_voice_setting and not settings.voice_enabled is bool:
		return false
	if pending_volumes.is_empty() and not has_voice_setting:
		return false
	for bus_index in pending_volumes:
		AudioServer.set_bus_volume_db(bus_index, pending_volumes[bus_index])
	if has_voice_setting:
		_voice_enabled = settings.voice_enabled
		if not _voice_enabled:
			stop_voice()
	return true

func play_sfx(sfx_id: StringName) -> bool:
	_load_manifest()
	var canonical_id := &"heart_loss" if sfx_id == &"health_loss" else sfx_id
	var stream: AudioStream = _sfx_registry.get(canonical_id)
	if stream == null:
		stream = _tone_factory.create_sfx(sfx_id)
	if stream == null or not _ensure_players():
		return false
	_sfx_player.stream = stream
	_start_player(_sfx_player)
	return true

func play_music(music_id: StringName) -> bool:
	_load_manifest()
	var stream: AudioStream = _music_registry.get(music_id)
	if stream == null or not _ensure_players():
		return false
	if _current_music_id == music_id and _music_player.stream == stream:
		return true
	_current_music_id = music_id
	_music_player.stream = stream
	_start_player(_music_player)
	return true

func stop_music() -> void:
	_current_music_id = &""
	if _music_player != null:
		_music_player.stop()
		_music_player.stream = null

func current_music_id() -> StringName:
	return _current_music_id

func register_voice(dialogue_id: StringName, stream: AudioStream) -> bool:
	if dialogue_id not in VOICE_IDS or stream == null:
		return false
	_voice_registry[dialogue_id] = stream
	return true

func play_voice(dialogue_id: StringName) -> bool:
	_load_manifest()
	if not _voice_enabled:
		return false
	if dialogue_id not in VOICE_IDS or not _voice_registry.has(dialogue_id):
		voice_missing.emit(dialogue_id)
		return false
	if not _ensure_players():
		return false
	stop_voice()
	_current_voice_id = dialogue_id
	_voice_player.stream = _voice_registry[dialogue_id]
	_start_player(_voice_player)
	return true

func stop_voice() -> void:
	_current_voice_id = &""
	if _voice_player != null:
		_voice_player.stop()
		_voice_player.stream = null

func current_voice_id() -> StringName:
	return _current_voice_id

func audio_asset_counts() -> Dictionary:
	_load_manifest()
	return {
		"music": _music_registry.size(),
		"sfx": _sfx_registry.size(),
		"voice": _voice_registry.size(),
	}

func question_voice_requires_speaker() -> bool:
	_load_manifest()
	return _question_voice_requires_speaker

func voice_blocks_input() -> bool:
	_load_manifest()
	return _voice_blocks_input

func _load_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		return
	var policy: Variant = parsed.get("questionNarration")
	if (
		not policy is Dictionary
		or policy.get("autoplay") != false
		or policy.get("trigger") != "speaker_control_only"
		or policy.get("blocksInput") != false
	):
		return
	_question_voice_requires_speaker = true
	_voice_blocks_input = false
	_register_manifest_entries(parsed.get("music"), &"music", MUSIC_IDS, _music_registry)
	_register_manifest_entries(parsed.get("sfx"), &"sfx", SFX_IDS, _sfx_registry)
	_register_manifest_entries(parsed.get("voice"), &"voice", VOICE_IDS, _voice_registry)

func _register_manifest_entries(
	raw_entries: Variant,
	expected_kind: StringName,
	allowed_ids: Array[StringName],
	registry: Dictionary
) -> void:
	if not raw_entries is Array:
		return
	for raw_entry in raw_entries:
		if not raw_entry is Dictionary:
			continue
		var raw_id: Variant = raw_entry.get("id")
		var raw_path: Variant = raw_entry.get("path")
		if not raw_id is String or not raw_path is String or raw_entry.get("kind") != String(expected_kind):
			continue
		var asset_id := StringName(raw_id)
		var relative_path := String(raw_path)
		if asset_id not in allowed_ids or not _is_safe_audio_path(relative_path):
			continue
		var resource_path := "res://%s" % relative_path
		var stream: Variant
		if OS.has_feature("editor"):
			stream = AudioStreamOggVorbis.load_from_file(resource_path)
		elif ResourceLoader.exists(resource_path):
			stream = ResourceLoader.load(resource_path)
		if not stream is AudioStream:
			continue
		if expected_kind == &"music" and stream is AudioStreamOggVorbis:
			stream.loop = true
		registry[asset_id] = stream

func _is_safe_audio_path(relative_path: String) -> bool:
	return (
		relative_path.begins_with("assets/audio/")
		and relative_path.ends_with(".ogg")
		and not relative_path.contains("..")
		and not relative_path.contains("\\")
		and not relative_path.contains(":")
	)

func _ensure_players() -> bool:
	if _music_player != null and _sfx_player != null and _voice_player != null:
		return true
	for bus_name in [&"Music", &"SFX", &"Voice"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			return false
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = &"Music"
	add_child(_music_player)
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SFXPlayer"
	_sfx_player.bus = &"SFX"
	add_child(_sfx_player)
	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "VoicePlayer"
	_voice_player.bus = &"Voice"
	_voice_player.finished.connect(_on_voice_player_finished)
	add_child(_voice_player)
	return true

func _on_voice_player_finished() -> void:
	if _current_voice_id.is_empty():
		return
	var completed_id := _current_voice_id
	_current_voice_id = &""
	_voice_player.stream = null
	voice_finished.emit(completed_id)

func _start_player(player: AudioStreamPlayer) -> void:
	if DisplayServer.get_name() != "headless":
		player.play()

func _is_valid_decibels(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= MIN_AUDIO_DB and value <= MAX_AUDIO_DB
