extends "res://tests/support/test_case.gd"

const AudioServiceScript = preload("res://src/presentation/audio/audio_service.gd")
const ToneFactoryScript = preload("res://src/presentation/audio/tone_factory.gd")

func run(tree: SceneTree) -> void:
	_test_bus_layout_and_profile_settings()
	await _test_release_audio_manifest_is_loaded(tree)
	await _test_offline_sfx_are_deterministic(tree)
	await _test_voice_interruption_missing_and_independent_disable(tree)

func _test_release_audio_manifest_is_loaded(tree: SceneTree) -> void:
	var service = AudioServiceScript.new()
	tree.root.add_child(service)
	await tree.process_frame
	assert_eq(service.audio_asset_counts(), {"music": 3, "sfx": 12, "voice": 9})
	assert_true(service.question_voice_requires_speaker())
	assert_false(service.voice_blocks_input())
	assert_true(service.play_music(&"exploration_loop"))
	assert_eq(service.current_music_id(), &"exploration_loop")
	var music_player: AudioStreamPlayer = service.get_node("MusicPlayer")
	assert_true(music_player.stream is AudioStreamOggVorbis)
	assert_true((music_player.stream as AudioStreamOggVorbis).loop)
	assert_true(service.play_sfx(&"heart_loss"))
	assert_true(service.get_node("SFXPlayer").stream is AudioStreamOggVorbis)
	assert_true(service.play_voice(&"moa_home_welcome"))
	assert_true(service.get_node("VoicePlayer").stream is AudioStreamOggVorbis)
	service.stop_music()
	assert_eq(service.current_music_id(), &"")
	service.queue_free()
	await tree.process_frame

func _test_bus_layout_and_profile_settings() -> void:
	var names: Array[StringName] = []
	for index in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(index))
	assert_eq(names, [&"Master", &"Music", &"SFX", &"Voice"])
	var service = AudioServiceScript.new()
	assert_true(service.apply_settings({
		"master_db": -3.0,
		"music_db": -12.5,
		"sfx_db": -6.0,
		"voice_db": -9.0,
		"voice_enabled": true,
		"reduced_motion": false,
	}))
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Master")), -3.0)
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), -12.5)
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX")), -6.0)
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Voice")), -9.0)
	var before := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music"))
	assert_false(service.apply_settings({"music_db": NAN}), "invalid audio settings were accepted")
	assert_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), before, "invalid settings partially mutated buses")
	assert_true(service.apply_settings({"master_db": 0.0, "music_db": -6.0, "sfx_db": 0.0, "voice_db": 0.0, "voice_enabled": true}))
	service.free()

func _test_offline_sfx_are_deterministic(tree: SceneTree) -> void:
	var factory := ToneFactoryScript.new()
	var first: AudioStreamWAV = factory.create_sfx(&"button_down")
	var second: AudioStreamWAV = factory.create_sfx(&"button_down")
	assert_not_null(first)
	assert_not_null(second)
	assert_eq(first.mix_rate, 48000)
	assert_false(first.stereo)
	assert_true(not first.data.is_empty())
	assert_eq(first.data, second.data, "offline tone generation is not deterministic")
	assert_null(factory.create_sfx(&"unknown"))
	var service = AudioServiceScript.new()
	tree.root.add_child(service)
	await tree.process_frame
	assert_eq(service.get_child_count(), 3)
	assert_eq(service.get_node("MusicPlayer").bus, &"Music")
	for sfx_id in [&"button_down", &"correct", &"wrong", &"heart_loss", &"health_loss", &"reward"]:
		assert_true(service.play_sfx(sfx_id), "%s did not resolve offline" % sfx_id)
		var player: AudioStreamPlayer = service.get_node("SFXPlayer")
		assert_eq(player.bus, &"SFX")
		assert_true(player.stream is AudioStreamOggVorbis)
	assert_false(service.play_sfx(&"unknown"))
	service.queue_free()
	await tree.process_frame

func _test_voice_interruption_missing_and_independent_disable(tree: SceneTree) -> void:
	var factory := ToneFactoryScript.new()
	var voice_a: AudioStreamWAV = factory.create_sfx(&"correct")
	var voice_b: AudioStreamWAV = factory.create_sfx(&"reward")
	var service = AudioServiceScript.new()
	tree.root.add_child(service)
	await tree.process_frame
	assert_true(service.register_voice(&"moa_home_welcome", voice_a))
	assert_true(service.register_voice(&"moa_reward", voice_b))
	assert_false(service.register_voice(&"unknown_dialogue", voice_a))
	var finished: Array[StringName] = []
	var missing: Array[StringName] = []
	service.voice_finished.connect(func(id: StringName): finished.append(id))
	service.voice_missing.connect(func(id: StringName): missing.append(id))
	assert_true(service.play_voice(&"moa_home_welcome"))
	assert_eq(service.current_voice_id(), &"moa_home_welcome")
	var voice_player: AudioStreamPlayer = service.get_node("VoicePlayer")
	assert_eq(voice_player.bus, &"Voice")
	assert_true(service.play_voice(&"moa_reward"))
	assert_eq(service.current_voice_id(), &"moa_reward")
	assert_true(voice_player.stream == voice_b)
	assert_eq(finished, [], "interrupting voice A incorrectly completed it")
	voice_player.finished.emit()
	assert_eq(finished, [&"moa_reward"])
	assert_eq(service.current_voice_id(), &"")
	assert_false(service.play_voice(&"unknown_dialogue"))
	assert_eq(missing, [&"unknown_dialogue"])
	assert_true(service.play_voice(&"moa_home_welcome"))
	service.stop_voice()
	assert_eq(service.current_voice_id(), &"")
	assert_eq(finished, [&"moa_reward"], "manual stop must not masquerade as natural completion")
	assert_true(service.play_voice(&"moa_home_welcome"))
	assert_true(service.apply_settings({"voice_enabled": false}))
	assert_eq(service.current_voice_id(), &"", "disabling voice did not interrupt the active clip")
	assert_false(service.play_voice(&"moa_home_welcome"))
	assert_eq(missing, [&"unknown_dialogue"], "disabled voice must not emit a missing-asset warning")
	assert_true(service.play_sfx(&"correct"), "disabling voice also disabled SFX")
	assert_true(service.apply_settings({"voice_enabled": true}))
	assert_true(service.play_voice(&"moa_home_welcome"))
	service.queue_free()
	await tree.process_frame
