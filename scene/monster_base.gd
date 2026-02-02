extends EntityBase
class_name MonsterBase

# ===== 怪物专属 =====
@export var hit_stun_time: float = 0.1
# 受击时短暂眩晕时间

@export var weak_stun_time: float = 5.0
# 进入虚弱状态后的眩晕时间

@export var weak_stun_extend_time: float = 3.0
# 链接后延长的眩晕时间

@export var stun_duration: float = 2.0
# 【问题6】可配置的眩晕持续时间（被光花等击中时使用）

var stunned_t: float = 0.0
# 当前眩晕剩余时间

var weak_stun_t: float = 0.0
# 虚弱眩晕剩余时间

var _linked_slots: Array[int] = []
# 链接的锁链槽位列表

# ===== 光照系统 =====
@export var light_counter: float = 0.0
@export var light_counter_max: float = 10.0
@export var thunder_add_seconds: float = 3.0

@export var light_receiver_path: NodePath = ^"Hurtbox"
@onready var _light_receiver: Area2D = get_node_or_null(light_receiver_path) as Area2D

var _processed_light_sources: Dictionary = {}
var _active_light_sources: Dictionary = {}
var _thunder_processed_this_frame: bool = false

var _saved_collision_layer: int = -1
var _saved_collision_mask: int = -1
var _fusion_vanished: bool = false

func _ready() -> void:
	super._ready()
	entity_type = EntityType.MONSTER
	add_to_group("monster")
	
	if EventBus:
		EventBus.thunder_burst.connect(_on_thunder_burst)
		EventBus.light_started.connect(_on_light_started)
		EventBus.light_finished.connect(_on_light_finished)
	
	if _light_receiver:
		_light_receiver.area_entered.connect(_on_light_area_entered)

func _physics_process(dt: float) -> void:
	if light_counter > 0.0:
		light_counter -= dt
		light_counter = max(light_counter, 0.0)
	
	_thunder_processed_this_frame = false
	
	if weak:
		if weak_stun_t > 0.0:
			weak_stun_t -= dt
			if weak_stun_t <= 0.0:
				weak_stun_t = 0.0
				_restore_from_weak()
		return
	if stunned_t > 0.0:
		stunned_t -= dt
		if stunned_t < 0.0:
			stunned_t = 0.0
			_release_linked_chains()
		return

	_do_move(dt)

func _do_move(_dt: float) -> void:
	pass

# ===== 眩晕状态（重写基类方法）=====
func is_stunned() -> bool:
	# 【问题6】重写：返回当前是否处于眩晕状态
	return stunned_t > 0.0

# ===== 光/雷反应 =====
func _on_thunder_burst(add_seconds: float) -> void:
	if _thunder_processed_this_frame:
		return
	_thunder_processed_this_frame = true
	light_counter += add_seconds
	light_counter = min(light_counter, light_counter_max)

func on_light_exposure(remaining_time: float) -> void:
	light_counter += remaining_time
	light_counter = min(light_counter, light_counter_max)

func _on_light_started(source_id: int, remaining_time: float, source_light_area: Area2D) -> void:
	if _light_receiver == null or source_light_area == null:
		return
	if not source_light_area.overlaps_area(_light_receiver):
		_active_light_sources[source_id] = {
			"area": source_light_area,
			"remaining_time": remaining_time
		}
		return
	if _processed_light_sources.has(source_id):
		return
	_processed_light_sources[source_id] = true
	light_counter += remaining_time
	light_counter = min(light_counter, light_counter_max)

func _on_light_finished(source_id: int) -> void:
	_processed_light_sources.erase(source_id)
	_active_light_sources.erase(source_id)

func _on_light_area_entered(area: Area2D) -> void:
	if area == null:
		return
	for source_id in _active_light_sources.keys():
		var light_data: Dictionary = _active_light_sources[source_id]
		if light_data["area"] == area:
			if _processed_light_sources.has(source_id):
				return
			var remaining: float = light_data["remaining_time"]
			_processed_light_sources[source_id] = true
			light_counter += remaining
			light_counter = min(light_counter, light_counter_max)
			break

# ===== 虚弱/眩晕 =====
func _update_weak_state() -> void:
	var was_weak := weak
	weak = has_hp and (hp <= weak_hp) and hp > 0
	if weak and not was_weak:
		hp_locked = true
		weak_stun_t = weak_stun_time

func _restore_from_weak() -> void:
	hp = max_hp
	weak = false
	hp_locked = false
	weak_stun_t = 0.0
	reset_vanish_count()  # 重置泯灭计数
	_release_linked_chains()

func _release_linked_chains() -> void:
	# 释放所有链接的锁链
	var slots: Array[int] = _linked_slots.duplicate()
	_linked_slots.clear()
	_linked_slot = -1
	var p: Node = _linked_player
	_linked_player = null
	
	# 恢复Hurtbox碰撞层（关键修复！）
	if _hurtbox != null and _hurtbox_original_layer >= 0:
		_hurtbox.collision_layer = _hurtbox_original_layer
		_hurtbox_original_layer = -1
	
	# 通知Player溶解锁链
	if p == null or not is_instance_valid(p):
		return
	if not p.has_method("force_dissolve_chain"):
		return
	for s in slots:
		p.call("force_dissolve_chain", s)

func apply_stun(seconds: float, do_flash: bool = true) -> void:
	# 施加眩晕（使用可配置的stun_duration或传入的秒数）
	var stun_time: float = seconds
	if stun_time <= 0.0:
		stun_time = stun_duration  # 使用可配置的眩晕时间
	if stun_time <= 0.0:
		return
	if do_flash:
		_flash_once()
	stunned_t = max(stunned_t, stun_time)

# ===== 锁链交互 =====
func on_chain_hit(_player: Node, slot: int) -> int:
	# 被锁链命中时调用
	# 返回值：0=普通受击（会扣血）, 1=可链接（虚弱或眩晕状态）
	# 【问题6】眩晕时也可以被链接
	if weak or stunned_t > 0.0:
		_linked_player = _player
		# 不在这里调用on_chain_attached，让player_chain_system统一调用
		return 1
	take_damage(1)
	return 0

func on_chain_attached(slot: int) -> void:
	# 锁链连接时调用（由player_chain_system调用）
	# 第一条链连接时禁用Hurtbox碰撞层
	if _linked_slots.is_empty():
		if _hurtbox != null:
			_hurtbox_original_layer = _hurtbox.collision_layer
			_hurtbox.collision_layer = 0
	
	if not _linked_slots.has(slot):
		_linked_slots.append(slot)
	_linked_slot = slot
	
	# 延长虚弱/眩晕时间
	if weak:
		weak_stun_t += weak_stun_extend_time
	elif stunned_t > 0.0:
		stunned_t += weak_stun_extend_time
	
	_flash_once()

func on_chain_detached(slot: int) -> void:
	# 锁链断开时调用
	_linked_slots.erase(slot)
	
	# 所有链都断开时恢复Hurtbox碰撞层
	if _linked_slots.is_empty():
		_linked_slot = -1
		_linked_player = null
		if _hurtbox != null and _hurtbox_original_layer >= 0:
			_hurtbox.collision_layer = _hurtbox_original_layer
			_hurtbox_original_layer = -1  # 重置，避免重复恢复
	else:
		# 还有其他链，更新_linked_slot为剩余的第一条
		_linked_slot = _linked_slots[0]

# ===== 融合消失 =====
func set_fusion_vanish(v: bool) -> void:
	if v:
		if not _fusion_vanished:
			_saved_collision_layer = collision_layer
			_saved_collision_mask = collision_mask
			_fusion_vanished = true
		collision_layer = 0
		collision_mask = 0
	else:
		if _fusion_vanished:
			collision_layer = _saved_collision_layer
			collision_mask = _saved_collision_mask
			_fusion_vanished = false
	if sprite != null:
		sprite.visible = not v
