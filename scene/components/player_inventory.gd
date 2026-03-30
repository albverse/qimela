class_name PlayerInventory
extends Node

## 背包逻辑组件（挂在 Player/Components 下）
## 职责：管理 10 格道具槽位、冷却、使用分发、状态机（开/关/动画中）
## UI 通过 EventBus 信号驱动，本组件不直接操作 UI 节点

# ── 错误码 ──
enum UseError {
	OK = 0,
	ERR_EMPTY_SLOT = 1,
	ERR_NO_COUNT = 2,
	ERR_COOLDOWN = 3,
	ERR_INVALID_TARGET = 4,
	ERR_STATE_BLOCKED = 5,
	ERR_FULL_HP = 6,
}

# ── 背包状态机 ──
enum BagState {
	CLOSED,
	OPENING,
	OPEN,
	CLOSING,
}

const CAPACITY: int = 10
const USE_INPUT_LOCK_SEC: float = 0.1  # 使用后短输入锁（防连按误消耗）

# ── 槽位数据 ──
# 每个元素: { "item": ItemData, "count": int, "cooldown": float } 或 null
var _slots: Array = []

# ── 状态 ──
var _state: int = BagState.CLOSED
var _selected_slot: int = 0
var _last_used_slot: int = 0  # 游标记忆
var _use_lock_timer: float = 0.0
var _player: Player = null


func _ready() -> void:
	_slots.resize(CAPACITY)
	for i in range(CAPACITY):
		_slots[i] = null


func setup(player: Player) -> void:
	_player = player


func tick(dt: float) -> void:
	# 冷却倒计时
	for i in range(CAPACITY):
		if _slots[i] == null:
			continue
		var slot: Dictionary = _slots[i] as Dictionary
		if slot["cooldown"] > 0.0:
			slot["cooldown"] -= dt
			if slot["cooldown"] < 0.0:
				slot["cooldown"] = 0.0

	# 使用输入锁倒计时
	if _use_lock_timer > 0.0:
		_use_lock_timer -= dt
		if _use_lock_timer < 0.0:
			_use_lock_timer = 0.0


# ══════════════════════════════════════
#  背包状态机
# ══════════════════════════════════════

func get_bag_state() -> int:
	return _state


func is_open() -> bool:
	return _state == BagState.OPEN


func toggle() -> void:
	## 按 B 切换背包开关
	if _is_state_blocked():
		return
	match _state:
		BagState.CLOSED:
			_state = BagState.OPENING
			_selected_slot = _last_used_slot
			EventBus.emit_inventory_opened()
			EventBus.emit_inventory_selection_changed(_selected_slot)
			EventBus.emit_inventory_sfx_open()
		BagState.OPEN:
			_state = BagState.CLOSING
			EventBus.emit_inventory_closed()
			EventBus.emit_inventory_sfx_close()
		# OPENING / CLOSING 期间忽略重复 toggle


func on_open_animation_finished() -> void:
	if _state == BagState.OPENING:
		_state = BagState.OPEN


func on_close_animation_finished() -> void:
	if _state == BagState.CLOSING:
		_state = BagState.CLOSED


func force_close() -> void:
	## 被击/死亡/石化时强制关闭
	if _state == BagState.CLOSED:
		return
	_state = BagState.CLOSING
	EventBus.emit_inventory_closed()


# ══════════════════════════════════════
#  导航
# ══════════════════════════════════════

func get_selected_slot() -> int:
	return _selected_slot


func move_selection(dir: int) -> void:
	## dir: -1 = 左, +1 = 右
	if _state != BagState.OPEN:
		return
	var new_idx: int = _selected_slot + dir
	# Wrap-around
	if new_idx < 0:
		new_idx = CAPACITY - 1
	elif new_idx >= CAPACITY:
		new_idx = 0
	if new_idx != _selected_slot:
		_selected_slot = new_idx
		EventBus.emit_inventory_selection_changed(_selected_slot)
		EventBus.emit_inventory_sfx_navigate()


# ══════════════════════════════════════
#  道具管理
# ══════════════════════════════════════

func add_item(item: ItemData, count: int = 1) -> int:
	## 添加道具到背包。返回首个放入的槽位索引，-1 = 满了（一个也放不下）
	if item == null:
		return -1

	var remaining: int = count
	var first_slot: int = -1

	# 先尝试叠加到已有同 id 槽位
	if item.max_stack > 1:
		for i in range(CAPACITY):
			if remaining <= 0:
				break
			if _slots[i] == null:
				continue
			var slot: Dictionary = _slots[i] as Dictionary
			var slot_item: ItemData = slot["item"] as ItemData
			if slot_item.id == item.id and slot["count"] < item.max_stack:
				var can_add: int = item.max_stack - slot["count"]
				var to_add: int = remaining if remaining <= can_add else can_add
				slot["count"] += to_add
				remaining -= to_add
				EventBus.emit_inventory_item_added(i, item, slot["count"])
				if first_slot < 0:
					first_slot = i

	# 剩余放入空槽
	while remaining > 0:
		var empty_idx: int = -1
		for i in range(CAPACITY):
			if _slots[i] == null:
				empty_idx = i
				break
		if empty_idx < 0:
			break
		var to_put: int = remaining if remaining <= item.max_stack else item.max_stack
		_slots[empty_idx] = { "item": item, "count": to_put, "cooldown": 0.0 }
		remaining -= to_put
		EventBus.emit_inventory_item_added(empty_idx, item, to_put)
		if first_slot < 0:
			first_slot = empty_idx

	if first_slot < 0:
		# 一个都没放进去
		EventBus.emit_inventory_full()
		EventBus.emit_inventory_sfx_bag_full()
		return -1

	# 至少放入了一部分
	EventBus.emit_inventory_sfx_pickup(item.id)

	if remaining > 0:
		# 部分放入，背包已满
		EventBus.emit_inventory_full()

	return first_slot


func remove_item(slot_index: int, count: int = 1) -> void:
	if slot_index < 0 or slot_index >= CAPACITY:
		return
	if _slots[slot_index] == null:
		return
	var slot: Dictionary = _slots[slot_index] as Dictionary
	slot["count"] -= count
	if slot["count"] <= 0:
		_slots[slot_index] = null
		EventBus.emit_inventory_item_removed(slot_index)
	else:
		EventBus.emit_inventory_item_added(slot_index, slot["item"] as ItemData, slot["count"])


func get_slot(index: int) -> Dictionary:
	## 返回 { "item": ItemData, "count": int, "cooldown": float } 或空 {}
	if index < 0 or index >= CAPACITY:
		return {}
	if _slots[index] == null:
		return {}
	return _slots[index] as Dictionary


func get_slots_snapshot() -> Array:
	## 返回所有槽位快照，供 UI 读取
	var result: Array = []
	result.resize(CAPACITY)
	for i in range(CAPACITY):
		if _slots[i] == null:
			result[i] = {}
		else:
			var slot: Dictionary = _slots[i] as Dictionary
			result[i] = slot.duplicate()
	return result


func is_full() -> bool:
	for i in range(CAPACITY):
		if _slots[i] == null:
			return false
	return true


func get_item_count() -> int:
	var n: int = 0
	for i in range(CAPACITY):
		if _slots[i] != null:
			n += 1
	return n


# ══════════════════════════════════════
#  使用道具
# ══════════════════════════════════════

func try_use_selected() -> Dictionary:
	## 尝试使用当前选中格的道具
	## 返回 { "ok": bool, "err": UseError }
	if _state != BagState.OPEN:
		return { "ok": false, "err": UseError.ERR_STATE_BLOCKED }
	if _use_lock_timer > 0.0:
		return { "ok": false, "err": UseError.ERR_COOLDOWN }
	return _use_item_at(_selected_slot)


func _use_item_at(slot_index: int) -> Dictionary:
	if _player == null:
		return { "ok": false, "err": UseError.ERR_STATE_BLOCKED }

	# 状态检查
	if _is_state_blocked():
		return { "ok": false, "err": UseError.ERR_STATE_BLOCKED }

	# 槽位检查
	if _slots[slot_index] == null:
		EventBus.emit_inventory_item_failed(&"", slot_index, UseError.ERR_EMPTY_SLOT)
		return { "ok": false, "err": UseError.ERR_EMPTY_SLOT }

	var slot: Dictionary = _slots[slot_index] as Dictionary
	var item: ItemData = slot["item"] as ItemData
	var count: int = slot["count"] as int

	if count <= 0:
		EventBus.emit_inventory_item_failed(item.id, slot_index, UseError.ERR_NO_COUNT)
		return { "ok": false, "err": UseError.ERR_NO_COUNT }

	# 冷却检查
	if slot["cooldown"] > 0.0:
		EventBus.emit_inventory_item_failed(item.id, slot_index, UseError.ERR_COOLDOWN)
		return { "ok": false, "err": UseError.ERR_COOLDOWN }

	# 按类别分发使用逻辑
	var result: Dictionary = _dispatch_use(item, slot_index)
	if result["ok"]:
		# 消耗
		if item.consume_on_use:
			remove_item(slot_index)
		# 冷却
		if item.cooldown_sec > 0.0 and _slots[slot_index] != null:
			(_slots[slot_index] as Dictionary)["cooldown"] = item.cooldown_sec
		# 输入锁
		_use_lock_timer = USE_INPUT_LOCK_SEC
		# 游标记忆
		_last_used_slot = slot_index
		EventBus.emit_inventory_item_used(item.id, slot_index)
		EventBus.emit_inventory_sfx_use(item.id)
	else:
		var err_code: int = result["err"] as int
		if err_code != UseError.OK:
			EventBus.emit_inventory_sfx_fail(item.id, err_code)

	return result


func _dispatch_use(item: ItemData, slot_index: int) -> Dictionary:
	match item.category:
		ItemData.ItemCategory.HEAL:
			return _use_heal(item, slot_index)
		ItemData.ItemCategory.HEALING_SPRITE:
			return _use_healing_sprite_item(item, slot_index)
		ItemData.ItemCategory.ATTACK_MAGIC:
			return _use_attack_magic(item, slot_index)
		ItemData.ItemCategory.PUZZLE_PROP:
			return _use_puzzle_prop(item, slot_index)
		ItemData.ItemCategory.CHIMERA_CAPSULE:
			return _use_chimera_capsule(item, slot_index)
		ItemData.ItemCategory.KEY_ITEM:
			# 关键道具不消耗，仅触发事件
			EventBus.emit_inventory_item_used(item.id, slot_index)
			return { "ok": false, "err": UseError.OK }

	return { "ok": false, "err": UseError.ERR_INVALID_TARGET }


func _use_heal(item: ItemData, slot_index: int) -> Dictionary:
	if _player.health == null:
		return { "ok": false, "err": UseError.ERR_STATE_BLOCKED }
	# 满血不可用
	if _player.health.hp >= _player.health.max_hp:
		EventBus.emit_inventory_item_failed(item.id, slot_index, UseError.ERR_FULL_HP)
		return { "ok": false, "err": UseError.ERR_FULL_HP }
	_player.heal(item.hp_restore)
	return { "ok": true, "err": UseError.OK }


func _use_healing_sprite_item(_item: ItemData, slot_index: int) -> Dictionary:
	# 检查玩家精灵槽是否有空位
	var sprite_count: int = _player.get_healing_sprite_count()
	if sprite_count >= _player.max_healing_sprites:
		EventBus.emit_inventory_item_failed(_item.id, slot_index, UseError.ERR_INVALID_TARGET)
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	# 实例化一只真实的 HealingSprite 并放在玩家身边，让它自动进入 ACQUIRE 状态
	var scene_res: Resource = load("res://scene/HealingSprite.tscn")
	if scene_res == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var packed: PackedScene = scene_res as PackedScene
	if packed == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var sprite: Node2D = packed.instantiate() as Node2D
	# 在玩家附近生成，距离小于 acquire_range(150) 让它自动飞向玩家
	sprite.global_position = _player.global_position + Vector2(0.0, -30.0)
	_player.get_parent().add_child(sprite)
	return { "ok": true, "err": UseError.OK }


func _use_attack_magic(item: ItemData, _slot_index: int) -> Dictionary:
	if item.use_scene_path == "":
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var scene_res: Resource = load(item.use_scene_path)
	if scene_res == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var packed: PackedScene = scene_res as PackedScene
	if packed == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var node: Node2D = packed.instantiate() as Node2D
	node.global_position = _player.global_position + Vector2(_player.facing * 80.0, -20.0)
	_player.get_parent().add_child(node)
	return { "ok": true, "err": UseError.OK }


func _use_puzzle_prop(item: ItemData, _slot_index: int) -> Dictionary:
	if item.deploy_scene_path == "":
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var scene_res: Resource = load(item.deploy_scene_path)
	if scene_res == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var packed: PackedScene = scene_res as PackedScene
	if packed == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var node: Node2D = packed.instantiate() as Node2D
	node.global_position = _player.global_position + Vector2(_player.facing * 60.0, 0.0)
	_player.get_parent().add_child(node)
	return { "ok": true, "err": UseError.OK }


func _use_chimera_capsule(item: ItemData, _slot_index: int) -> Dictionary:
	if item.chimera_scene_path == "":
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var scene_res: Resource = load(item.chimera_scene_path)
	if scene_res == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var packed: PackedScene = scene_res as PackedScene
	if packed == null:
		return { "ok": false, "err": UseError.ERR_INVALID_TARGET }
	var node: Node2D = packed.instantiate() as Node2D
	node.global_position = _player.global_position + Vector2(_player.facing * 40.0, -10.0)
	_player.get_parent().add_child(node)
	return { "ok": true, "err": UseError.OK }


# ══════════════════════════════════════
#  内部辅助
# ══════════════════════════════════════

func _is_state_blocked() -> bool:
	if _player == null:
		return true
	if _player.is_petrified():
		return true
	if _player.health != null and _player.health.hp <= 0:
		return true
	if _player.action_fsm != null:
		var s: int = _player.action_fsm.state
		if s == PlayerActionFSM.State.DIE or s == PlayerActionFSM.State.HURT:
			return true
		# 攻击/融合中禁止使用道具（防止打断攻击动画或变身流程）
		if s == PlayerActionFSM.State.ATTACK or s == PlayerActionFSM.State.ATTACK_CANCEL:
			return true
		if s == PlayerActionFSM.State.FUSE:
			return true
	return false
