class_name AudioService
extends Node

signal voice_finished(dialogue_id: StringName)
signal voice_missing(dialogue_id: StringName)

const ToneFactoryScript = preload("res://src/presentation/audio/tone_factory.gd")
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
const MIN_AUDIO_DB := -80.0
const MAX_AUDIO_DB := 0.0

var _tone_factory := ToneFactoryScript.new()
var _voice_registry: Dictionary = {}
var _voice_enabled := true
var _current_voice_id: StringName = &""
var _music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _voice_player: AudioStreamPlayer

func _ready() -> void:
	_ensure_players()

func _exit_tree() -> void:
	_current_voice_id = &""
	for player in [_music_player, _sfx_player, _voice_player]:
		if player != null:
			player.stop()
			player.stream = null
	_voice_registry.clear()

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
	var stream: AudioStreamWAV = _tone_factory.create_sfx(sfx_id)
	if stream == null or not _ensure_players():
		return false
	_sfx_player.stream = stream
	_start_player(_sfx_player)
	return true

func register_voice(dialogue_id: StringName, stream: AudioStream) -> bool:
	if dialogue_id not in VOICE_IDS or stream == null:
		return false
	_voice_registry[dialogue_id] = stream
	return true

func play_voice(dialogue_id: StringName) -> bool:
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
