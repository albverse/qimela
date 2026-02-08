extends Node
class_name PlayerHealth

## Health（Phase0）
## 核心：hp 管理 + 无敌帧 + 击退 + damage_applied 信号
## damage_applied 连接到 ActionFSM.on_damaged

signal damage_applied(amount: int, source_pos: Vector2)
signal hp_changed(new_hp: int, old_hp: int)

@export var max_hp: int = 5
@export var invincible_time: float = 0.1
@export var post_hit_stun_time: float = 0.2
@export var knockback_air_time: float = 0.25
@export var knockback_distance: float = 110.0
@export var knockback_arc_height: float = 40.0

var hp: int = 5
var _player: CharacterBody2D = null
var _inv_t: float = 0.0
var _kb_t: float = 0.0
var _kb_fly_t: float = 0.0
var _kb_vel: Vector2 = Vector2.ZERO
var _kb_gravity: float = 0.0
var _pending_land_stun: float = 0.0


func setup(player: CharacterBody2D) -> void:
	_player = player
	hp = max_hp


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
			if _pending_land_stun > 0.0:
				_kb_t = maxf(_kb_t, _pending_land_stun)
				_pending_land_stun = 0.0
			return

		_kb_fly_t -= dt
		if _player != null:
			_player.velocity.x = _kb_vel.x
			_player.velocity.y = _kb_vel.y
			_kb_vel.y += _kb_gravity * dt

		if _kb_fly_t <= 0.0:
			_kb_vel = Vector2.ZERO
			_kb_gravity = 0.0
			if _pending_land_stun > 0.0:
				_kb_t = maxf(_kb_t, _pending_land_stun)
				_pending_land_stun = 0.0


func is_knockback_active() -> bool:
	return _kb_t > 0.0 or _kb_fly_t > 0.0

func is_invincible() -> bool:
	return _inv_t > 0.0


func apply_damage(amount: int, source_global_pos: Vector2) -> void:
	if amount <= 0:
		return
	if _inv_t > 0.0:
		return

	var old_hp: int = hp
	hp = clamp(hp - amount, 0, max_hp)
	_inv_t = invincible_time

	# 击退
	if _player != null:
		var dx: float = _player.global_position.x - source_global_pos.x
		var dir_x: float = signf(dx)
		if is_zero_approx(dir_x):
			dir_x = -float(_player.facing)
		_kb_t = 0.0
		_pending_land_stun = maxf(post_hit_stun_time, 0.0)
		var fly_time: float = maxf(knockback_air_time, 0.0)
		_kb_fly_t = fly_time
		if fly_time > 0.0:
			var safe_time: float = maxf(fly_time, 0.0001)
			_kb_vel = Vector2(
				dir_x * knockback_distance / safe_time,
				-(4.0 * knockback_arc_height) / safe_time
			)
			_kb_gravity = (8.0 * knockback_arc_height) / (safe_time * safe_time)
		else:
			_kb_vel = Vector2.ZERO
			_kb_gravity = 0.0
			if _pending_land_stun > 0.0:
				_kb_t = maxf(_kb_t, _pending_land_stun)
				_pending_land_stun = 0.0

	# 通知 ActionFSM
	damage_applied.emit(amount, source_global_pos)
	hp_changed.emit(hp, old_hp)

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("HEALTH", "damage=%d hp=%d" % [amount, hp])


func heal(amount: int) -> void:
	if amount <= 0:
		return
	var old_hp: int = hp
	hp = min(hp + amount, max_hp)
	if hp != old_hp:
		hp_changed.emit(hp, old_hp)
