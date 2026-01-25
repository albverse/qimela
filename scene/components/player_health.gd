extends Node
class_name PlayerHealth

@export var max_hp: int = 5
@export var invincible_time: float = 0.1  # 文档要求=0.1s

# 击退：短时间锁定水平输入并强推（你已确认）
@export var hit_stun_time: float = 0.2
@export var knockback_air_time: float = 0.25
@export var knockback_distance: float = 110.0
@export var knockback_arc_height: float = 40.0

# UI
@export var hearts_ui_scene: PackedScene = preload("res://ui/hearts_ui.tscn")
@export var hud_layer_name: StringName = &"HUD"

var hp: int

var _player: Player
var _inv_t: float = 0.0
var _kb_t: float = 0.0
var _kb_fly_t: float = 0.0
var _kb_vel: Vector2 = Vector2.ZERO
var _kb_gravity: float = 0.0

var _ui: Node = null

func setup(player: Player) -> void:
	_player = player

func _ready() -> void:
	hp = max_hp
	call_deferred("_init_ui")

func _init_ui() -> void:
	var root := get_tree().current_scene
	if root == null:
		return

	var hud := root.find_child(String(hud_layer_name), true, false) as CanvasLayer
	if hud == null:
		hud = CanvasLayer.new()
		hud.name = String(hud_layer_name)
		root.add_child(hud) # 这里已经是 deferred 时机，通常安全

	_ui = hud.find_child("HeartsUI", true, false)
	if _ui == null and hearts_ui_scene != null:
		_ui = hearts_ui_scene.instantiate()
		hud.add_child(_ui)

	# ⚠️ 关键：不要马上 call setup（HeartsUI 可能还没 ready）
	if _ui != null:
		_ui.call_deferred("setup", max_hp, hp)

func tick(dt: float) -> void:
	if _inv_t > 0.0:
		_inv_t -= dt

	if _kb_t > 0.0:
		_kb_t -= dt
	if _kb_fly_t > 0.0:
		if _player != null and _player.is_on_floor() and _kb_vel.y >= 0.0:
			_kb_fly_t = 0.0
			_kb_vel = Vector2.ZERO
			_kb_gravity = 0.0
			return
		_kb_fly_t -= dt
		if _player != null:
			# 命中后击退：轨迹为抛物线，飞行时间与僵直时间分离
			_player.velocity.x = _kb_vel.x
			_player.velocity.y = _kb_vel.y
			_kb_vel.y += _kb_gravity * dt
		if _kb_fly_t <= 0.0:
			_kb_vel = Vector2.ZERO
			_kb_gravity = 0.0

func is_knockback_active() -> bool:
	return _kb_t > 0.0

func is_invincible() -> bool:
	return _inv_t > 0.0

func apply_damage(amount: int, source_global_pos: Vector2) -> void:
	if amount <= 0:
		return
	if _inv_t > 0.0:
		return

	hp = clamp(hp - amount, 0, max_hp)
	_inv_t = invincible_time

	# 计算击退方向：从伤害源 -> 玩家
	if _player != null:
		var dx := _player.global_position.x - source_global_pos.x
		var dir_x := signf(dx)
		if is_zero_approx(dir_x):
			dir_x = -float(_player.facing)  # 极端重合时给个合理方向
		_kb_t = hit_stun_time
		var fly_time := maxf(knockback_air_time, 0.0)
		_kb_fly_t = fly_time
		if fly_time > 0.0:
			var safe_time := maxf(fly_time, 0.0001)
			var horizontal_speed := knockback_distance / safe_time
			var up_speed := (4.0 * knockback_arc_height) / safe_time
			_kb_vel = Vector2(dir_x * horizontal_speed, -up_speed)
			_kb_gravity = (8.0 * knockback_arc_height) / (safe_time * safe_time)
		else:
			_kb_vel = Vector2.ZERO
			_kb_gravity = 0.0

	_sync_ui_instant()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	var from_hp := hp
	hp = min(hp + amount, max_hp)
	if hp == from_hp:
		return

	if _ui != null:
		if _ui.has_method("play_heal_fill"):
			_ui.call("play_heal_fill", from_hp, hp)
		elif _ui.has_method("set_hp_instant"):
			_ui.call("set_hp_instant", hp)
	else:
		_sync_ui_instant()

func _sync_ui_instant() -> void:
	if _ui != null and _ui.has_method("set_hp_instant"):
		_ui.call("set_hp_instant", hp)
