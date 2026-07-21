extends "res://tests/support/test_case.gd"

const POLICY_PATH := "res://src/ui/shared/ui_policy.gd"
const MathlandUiScript = preload("res://src/ui/shared/mathland_ui.gd")

func run(_tree: SceneTree) -> void:
	assert_true(ResourceLoader.exists(POLICY_PATH), "UI policy service is missing")
	if not ResourceLoader.exists(POLICY_PATH):
		return
	var PolicyScript: Variant = load(POLICY_PATH)
	var policy: Variant = PolicyScript.new()
	var first: Control = MathlandUiScript.tactile_button("First", "ui.continue")
	policy.register_tactile(first)
	assert_false(first.reduced_motion)
	policy.set_reduced_motion(true)
	assert_true(first.reduced_motion, "current tactile controls must update immediately")
	var later: Control = MathlandUiScript.tactile_button("Later", "ui.continue")
	policy.register_tactile(later)
	assert_true(later.reduced_motion, "new tactile controls must inherit current policy")
	first.free()
	later.free()
