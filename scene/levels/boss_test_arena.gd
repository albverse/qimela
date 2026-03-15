extends Node2D

@export var collapse_delay: float = 2.0
@export var recover_delay: float = 3.0

var _platform_states: Dictionary = {}

func _ready() -> void:
	for platform in [$PlatformA, $PlatformB, $PlatformC]:
		var trigger: Area2D = platform.get_node("Trigger")
		trigger.body_entered.connect(_on_platform_body_entered.bind(platform))
		_platform_states[platform] = {"collapsing": false}

func _on_platform_body_entered(body: Node, platform: StaticBody2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	var state: Dictionary = _platform_states.get(platform, {})
	if state.get("collapsing", false):
		return
	state["collapsing"] = true
	_platform_states[platform] = state
	_start_platform_collapse(platform)

func _start_platform_collapse(platform: StaticBody2D) -> void:
	await get_tree().create_timer(collapse_delay).timeout
	if not is_instance_valid(platform):
		return
	var shape: CollisionShape2D = platform.get_node("CollisionShape2D")
	if shape != null:
		shape.set_deferred("disabled", true)
	await get_tree().create_timer(recover_delay).timeout
	if not is_instance_valid(platform):
		return
	if shape != null:
		shape.set_deferred("disabled", false)
	var state: Dictionary = _platform_states.get(platform, {})
	state["collapsing"] = false
	_platform_states[platform] = state
