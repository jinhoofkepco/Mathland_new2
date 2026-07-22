extends "res://tests/support/test_case.gd"

const RetryPolicyScript = preload("res://src/sync/sync_retry_policy.gd")

func run(_tree: SceneTree) -> void:
	var policy := RetryPolicyScript.new(func(): return 0.25)
	assert_eq(policy.next_delay_ms(0), 2500)
	assert_eq(policy.next_delay_ms(1), 5000)
	assert_eq(policy.next_delay_ms(20), 300000)
	assert_eq(policy.classify({"status": 0, "error": "timeout"}), &"retry")
	assert_eq(policy.classify({"status": 500}), &"retry")
	assert_eq(policy.classify({"status": 429}), &"retry")
	assert_eq(policy.classify({"status": 401}), &"refresh")
	assert_eq(policy.classify({"status": 400}), &"schema")
	assert_eq(policy.classify({"status": 403}), &"permission")
	assert_eq(policy.classify({"status": 422}), &"client")
	policy.record_failure()
	policy.record_failure()
	assert_eq(policy.current_attempt(), 2)
	policy.record_success()
	assert_eq(policy.current_attempt(), 0)
	assert_eq(policy.next_scheduled_delay_ms(), 2500)
