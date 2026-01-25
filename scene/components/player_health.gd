extends Node
class_name PlayerHealth

@export var max_hp: int = 5
@export var invincible_time: float = 0.1  # 文档要求=0.1s

# 击退：短时间锁定水平输入并强推（你已确认）
@export var knockback_strength: float = 550.0
@export var hit_stun_time: float = 0.2

# UI
@export var hearts_ui_scene: PackedScene = preload("res://ui/hearts_ui.tscn")
@export var hud_layer_name: StringName = &"HUD"

var hp: int

var _player: Player
var _inv_t: float = 0.0
var _kb_t: float = 0.0
var _kb_dir_x: float = 0.0

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
		if _player != null:
			# 只强推水平（符合“锁定水平输入并强推”）
			_player.velocity.x = _kb_dir_x * knockback_strength
		if _kb_t <= 0.0:
			_kb_dir_x = 0.0

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
		_kb_dir_x = signf(dx)
		if is_zero_approx(_kb_dir_x):
			_kb_dir_x = -float(_player.facing)  # 极端重合时给个合理方向
		_kb_t = hit_stun_time

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
