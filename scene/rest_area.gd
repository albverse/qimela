extends Node2D
class_name RestArea

## StoneMaskBird 回巢点：
## - 正常状态：加入 rest_area 组；同一时刻仅允许一只 StoneMaskBird 占用
## - 被摧毁时（hp <= 0）：转换为 rest_area_break 状态，不会 queue_free
##   · 移出 rest_area 组，加入 rest_area_break 组
##   · StoneMaskBird 可飞过来修复（ActRepairRestArea）
##   · 每 1s 调用 add_repair_progress() 一次；hp 回到 max_hp 时恢复为 rest_area

@export var max_hp: int = 3
var hp: int = 3

var _occupying_bird_ref: WeakRef = null
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _hurt_shape: CollisionShape2D = get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D


func _ready() -> void:
	hp = max_hp
	add_to_group("rest_area")
	_update_visual_state()


func apply_hit(hit: HitData) -> bool:
	if hit == null:
		return false
	if hp <= 0:
		return false
	# break 状态不再接受攻击
	if not is_in_group("rest_area"):
		return false
	var real_damage: int = maxi(int(hit.damage), 1)
	hp = maxi(hp - real_damage, 0)
	_flash_once()
	_update_visual_state()
	if hp <= 0:
		_convert_to_break()
	return true


# ──────────────────────────────────────────────────────────
# rest_area_break：修复接口
# ──────────────────────────────────────────────────────────

## 由 ActRepairRestArea 每 1s 调用一次。
## hp+1；当 hp 恢复到 max_hp 时恢复为 rest_area 全功能，返回 true。
func add_repair_progress() -> bool:
	if not is_in_group("rest_area_break"):
		return false
	hp = mini(hp + 1, max_hp)
	_update_visual_state()
	if hp >= max_hp:
		_restore_from_break()
		return true
	return false


# ──────────────────────────────────────────────────────────
# 状态转换
# ──────────────────────────────────────────────────────────

func _convert_to_break() -> void:
	# 释放占用预约
	_occupying_bird_ref = null
	hp = 0

	# 切换组：rest_area → rest_area_break
	remove_from_group("rest_area")
	add_to_group("rest_area_break")

	_update_visual_state()

	# 禁用 Hurtbox（break 状态不再响应武器命中）
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.monitorable = false
		hurtbox.monitoring = false


func _restore_from_break() -> void:
	hp = max_hp

	# 切换组：rest_area_break → rest_area
	remove_from_group("rest_area_break")
	add_to_group("rest_area")

	_update_visual_state()

	# 重新启用 Hurtbox monitorable（可被武器 Area2D 检测到）
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox:
		hurtbox.monitorable = true
		hurtbox.monitoring = false  # Hurtbox 无需主动监测，只需被检测到


# ──────────────────────────────────────────────────────────
# 占用预约接口（rest_area 专用）
# ──────────────────────────────────────────────────────────

func is_arrived(bird: Node2D) -> bool:
	if bird == null or not is_instance_valid(bird):
		return false
	if _hurt_shape == null or _hurt_shape.shape == null:
		return false

	var local := _hurt_shape.to_local(bird.global_position)
	var shape := _hurt_shape.shape
	if shape is CircleShape2D:
		return local.length_squared() <= pow((shape as CircleShape2D).radius, 2)
	if shape is RectangleShape2D:
		var ext := (shape as RectangleShape2D).size * 0.5
		return absf(local.x) <= ext.x and absf(local.y) <= ext.y
	if shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		var half_h := cap.height * 0.5
		var r := cap.radius
		if absf(local.x) <= r and absf(local.y) <= half_h:
			return true
		var top_center := Vector2(0.0, -half_h)
		var bot_center := Vector2(0.0, half_h)
		return local.distance_squared_to(top_center) <= r * r or local.distance_squared_to(bot_center) <= r * r
	return false


func on_chain_hit(_player: Node, _slot: int) -> int:
	return 0


func reserve_for(bird: Node2D) -> bool:
	if bird == null or not is_instance_valid(bird):
		return false
	# break 状态不可预约
	if not is_in_group("rest_area"):
		return false
	var cur := _get_occupying_bird()
	if cur != null and cur != bird:
		return false
	_occupying_bird_ref = weakref(bird)
	return true


func release_for(bird: Node2D) -> void:
	var cur := _get_occupying_bird()
	if cur == null:
		_occupying_bird_ref = null
		return
	if bird == cur:
		_occupying_bird_ref = null


func is_available_for(bird: Node2D) -> bool:
	if not is_in_group("rest_area"):
		return false
	var cur := _get_occupying_bird()
	return cur == null or cur == bird


# ──────────────────────────────────────────────────────────
# 内部工具
# ──────────────────────────────────────────────────────────

func _get_occupying_bird() -> Node2D:
	if _occupying_bird_ref == null:
		return null
	var obj: Object = _occupying_bird_ref.get_ref()
	if obj == null:
		_occupying_bird_ref = null
		return null
	return obj as Node2D


func _flash_once() -> void:
	if _sprite == null:
		return
	var tw := create_tween()
	_sprite.modulate = Color(1.2, 1.2, 1.2, 1.0)
	tw.tween_property(_sprite, "modulate", Color.WHITE, 0.1)


func _update_visual_state() -> void:
	if _sprite == null or max_hp <= 0:
		return
	var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
	# hp/max_hp=1.0 → Color.WHITE（正常）
	# hp/max_hp=0.0 → Color(1,0,0,1) 全红（已摧毁/break 状态）
	# 修复过程：红→橙→粉→白，直观反映修复进度
	_sprite.self_modulate = Color(1.0, ratio, ratio, 1.0)
