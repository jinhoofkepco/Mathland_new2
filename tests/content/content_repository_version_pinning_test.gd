extends "res://tests/support/test_case.gd"

const ContentRepositoryScript = preload("res://src/content/content_repository.gd")

func run(_tree: SceneTree) -> void:
	var repository := ContentRepositoryScript.new()
	repository.call("_commit_candidate", _candidate("1.0.0", "old run"))
	var pinned := repository.get_activity(&"foundations_counting", "1.0.0")
	assert_eq(pinned.get("marker"), "old run")
	repository.call("_commit_candidate", _candidate("1.1.0", "new run"))
	assert_eq(repository.get_active_version(&"foundations_counting"), "1.1.0")
	assert_eq(repository.get_activity(&"foundations_counting").get("marker"), "new run")
	assert_eq(
		repository.get_activity(&"foundations_counting", "1.0.0"),
		pinned,
		"publication switch invalidated a running session pinned to its starting version"
	)

func _candidate(version: String, marker: String) -> Dictionary:
	var path := "content/packages/foundations_counting/%s.json" % version
	return {
		"manifest": {
			"activity_order": ["foundations_counting"],
			"packages": [{
				"activity_id": "foundations_counting",
				"content_version": version,
				"path": path,
			}],
		},
		"packages_by_path": {path: {
			"activity_id": "foundations_counting",
			"content_version": version,
			"marker": marker,
		}},
	}
