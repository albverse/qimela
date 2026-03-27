class_name PlayerInventory
extends Node

## 背包逻辑组件（挂在 Player/Components 下）
## 职责：管理 9 格主背包 + OtherItems 列表、冷却、使用分发、状态机
## UI 通过 EventBus 信号驱动，本组件不直接操作 UI 节点
## v0.2: 双列表分层（主背包 CONSUMABLE+KEY_ITEM / OtherItems MATERIAL）

# ── 错误码 ──
enum UseError {
	OK = 0,
	ERR_EMPTY_SLOT = 1,
	ERR_NO_COUNT = 2,
	ERR_COOLDOWN = 3,
	ERR_INVALID_TARGET = 4,
	ERR_STATE_BLOCKED = 5,
	ERR_FULL_HP = 6,
	ERR_INV_FULL = 7,
	ERR_DROP_FORBIDDEN = 8,
	ERR_INVALID_DROP_POS = 9,
}

# ── 背包状态机 ──
enum BagState {
	CLOSED,
	OPENING,
	OPEN_MAIN,
	OPEN_OTHER,
	CLOSING,
}

const MAIN_CAPACITY: int = 9              # 主背包格数（CONSUMABLE + KEY_ITEM）
const OTHER_ITEMS_MAX: int = 99           # OtherItems 总上限
const USE_INPUT_LOCK_SEC: float = 0.1     # 使用后短输入锁（防连按误消耗）

# ── 主背包槽位 ──
# 每个元素: { "item": ItemData, "count": int, "cooldown": float } 或 null
var _slots: Array = []

# ── OtherItems 列表（MATERIAL） ──
# 每个元素: { "item": ItemData, "count": int }
var _other_items: Array = []

# ── 状态 ──
var _state: int = BagState.CLOSED
var _selected_slot: int = 0
var _last_used_slot: int = 0  # 游标记忆
var _use_lock_timer: float = 0.0
var _player: Player = null
# OtherItems 面板选中索引
var _other_selected: int = 0


func _ready() -> void:
	_slots.resize(MAIN_CAPACITY)
	for i in range(MAIN_CAPACITY):
		_slots[i] = null


func setup(player: Player) -> void:
	_player = player


func tick(dt: float) -> void:
	# 冷却倒计时
	for i in range(MAIN_CAPACITY):
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
	return _state == BagState.OPEN_MAIN or _state == BagState.OPEN_OTHER


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
		BagState.OPEN_MAIN:
			_state = BagState.CLOSING
			EventBus.emit_inventory_closed()
		BagState.OPEN_OTHER:
			# 从 OtherItems 面板返回主背包
			_state = BagState.OPEN_MAIN
			EventBus.emit_inventory_close_other_items()
		# OPENING / CLOSING 期间忽略重复 toggle


func on_open_animation_finished() -> void:
	if _state == BagState.OPENING:
		_state = BagState.OPEN_MAIN


func on_close_animation_finished() -> void:
	if _state == BagState.CLOSING:
		_state = BagState.CLOSED


func force_close() -> void:
	## 被击/死亡/石化时强制关闭
	if _state == BagState.CLOSED:
		return
	_state = BagState.CLOSING
	EventBus.emit_inventory_closed()


func open_other_items() -> void:
	## 从主背包打开 OtherItems 面板
	if _state != BagState.OPEN_MAIN:
		return
	_state = BagState.OPEN_OTHER
	_other_selected = 0
	EventBus.emit_inventory_open_other_items()


func close_other_items() -> void:
	## 从 OtherItems 面板返回主背包
	if _state != BagState.OPEN_OTHER:
		return
	_state = BagState.OPEN_MAIN
	EventBus.emit_inventory_close_other_items()


# ══════════════════════════════════════
#  导航
# ══════════════════════════════════════

func get_selected_slot() -> int:
	return _selected_slot


func move_selection(dir: int) -> void:
	## dir: -1 = 左, +1 = 右
	## 导航范围 0..MAIN_CAPACITY（含 MAIN_CAPACITY 即第 10 格 "+" 按钮）
	if _state != BagState.OPEN_MAIN:
		return
	var total: int = MAIN_CAPACITY + 1  # 9 格 + 1 "+" = 10
	var new_idx: int = _selected_slot + dir
	# Wrap-around
	if new_idx < 0:
		new_idx = total - 1
	elif new_idx >= total:
		new_idx = 0
	if new_idx != _selected_slot:
		_selected_slot = new_idx
		EventBus.emit_inventory_selection_changed(_selected_slot)


func get_other_selected() -> int:
	return _other_selected


func move_other_selection(dir: int) -> void:
	## OtherItems 面板上下导航
	if _state != BagState.OPEN_OTHER:
		return
	if _other_items.is_empty():
		return
	var new_idx: int = _other_selected + dir
	if new_idx < 0:
		new_idx = _other_items.size() - 1
	elif new_idx >= _other_items.size():
		new_idx = 0
	_other_selected = new_idx


# ══════════════════════════════════════
#  主背包道具管理
# ══════════════════════════════════════

func add_item(item: ItemData, count: int = 1) -> int:
	## 添加道具到背包。返回放入的槽位索引，-1 = 满了
	## MATERIAL 自动路由到 OtherItems
	if item == null:
		return -1

	# MATERIAL 路由到 OtherItems
	if item.sub_category == ItemData.SubCategory.MATERIAL:
		var ok: bool = add_other_item(item, count)
		if ok:
			return -2  # 特殊值：已进入 OtherItems
		return -1

	# 先尝试叠加到已有同 id 槽位
	if item.max_stack > 1:
		for i in range(MAIN_CAPACITY):
			if _slots[i] == null:
				continue
			var slot: Dictionary = _slots[i] as Dictionary
			var slot_item: ItemData = slot["item"] as ItemData
			if slot_item.id == item.id and slot["count"] < item.max_stack:
				var can_add: int = item.max_stack - slot["count"]
				var to_add: int = count if count <= can_add else can_add
				slot["count"] += to_add
				EventBus.emit_inventory_item_added(i, item, slot["count"])
				_sort_main_slots()
				return i

	# 找空槽
	for i in range(MAIN_CAPACITY):
		if _slots[i] == null:
			_slots[i] = { "item": item, "count": count, "cooldown": 0.0 }
			EventBus.emit_inventory_item_added(i, item, count)
			_sort_main_slots()
			return i

	# 满了
	EventBus.emit_inventory_full()
	return -1


func remove_item(slot_index: int, count: int = 1) -> void:
	if slot_index < 0 or slot_index >= MAIN_CAPACITY:
		return
	if _slots[slot_index] == null:
		return
	var slot: Dictionary = _slots[slot_index] as Dictionary
	slot["count"] -= count
	if slot["count"] <= 0:
		_slots[slot_index] = null
		EventBus.emit_inventory_item_removed(slot_index)
		_sort_main_slots()
	else:
		EventBus.emit_inventory_item_added(slot_index, slot["item"] as ItemData, slot["count"])


func get_slot(index: int) -> Dictionary:
	## 返回 { "item": ItemData, "count": int, "cooldown": float } 或空 {}
	if index < 0 or index >= MAIN_CAPACITY:
		return {}
	if _slots[index] == null:
		return {}
	return _slots[index] as Dictionary


func get_slots_snapshot() -> Array:
	## 返回所有主背包槽位快照，供 UI 读取
	var result: Array = []
	result.resize(MAIN_CAPACITY)
	for i in range(MAIN_CAPACITY):
		if _slots[i] == null:
			result[i] = {}
		else:
			var slot: Dictionary = _slots[i] as Dictionary
			result[i] = slot.duplicate()
	return result


func is_full() -> bool:
	for i in range(MAIN_CAPACITY):
		if _slots[i] == null:
			return false
	return true


func get_item_count() -> int:
	var n: int = 0
	for i in range(MAIN_CAPACITY):
		if _slots[i] != null:
			n += 1
	return n


# ══════════════════════════════════════
#  OtherItems 管理（MATERIAL）
# ══════════════════════════════════════

func add_other_item(item: ItemData, count: int = 1) -> bool:
	## 添加 MATERIAL 到 OtherItems 列表
	if item == null:
		return false

	# 尝试叠加
	for i in range(_other_items.size()):
		var entry: Dictionary = _other_items[i] as Dictionary
		var entry_item: ItemData = entry["item"] as ItemData
		if entry_item.id == item.id:
			entry["count"] += count
			return true

	# 检查上限
	if _other_items.size() >= OTHER_ITEMS_MAX:
		EventBus.emit_inventory_pickup_failed(item.id, UseError.ERR_INV_FULL)
		return false

	# 新建条目
	_other_items.append({ "item": item, "count": count })
	return true


func remove_other_item(item_id: StringName, count: int = 1) -> bool:
	## 从 OtherItems 移除指定数量
	for i in range(_other_items.size()):
		var entry: Dictionary = _other_items[i] as Dictionary
		var entry_item: ItemData = entry["item"] as ItemData
		if entry_item.id == item_id:
			entry["count"] -= count
			if entry["count"] <= 0:
				_other_items.remove_at(i)
				# 修正选中索引
				if _other_selected >= _other_items.size() and _other_items.size() > 0:
					_other_selected = _other_items.size() - 1
				elif _other_items.is_empty():
					_other_selected = 0
			return true
	return false


func get_other_items_snapshot() -> Array:
	## 返回 OtherItems 快照供 UI 读取
	var result: Array = []
	for entry: Dictionary in _other_items:
		result.append(entry.duplicate())
	return result


func get_other_items_count() -> int:
	return _other_items.size()


func try_drop_other_item(other_index: int) -> int:
	## 尝试扔出 OtherItems 中的物品
	## 返回 UseError 码
	if other_index < 0 or other_index >= _other_items.size():
		return UseError.ERR_EMPTY_SLOT

	var entry: Dictionary = _other_items[other_index] as Dictionary
	var item: ItemData = entry["item"] as ItemData

	# 检查 can_drop
	if not item.can_drop:
		return UseError.ERR_DROP_FORBIDDEN

	var item_id: StringName = item.id
	var drop_count: int = 1

	# 扣减
	entry["count"] -= drop_count
	if entry["count"] <= 0:
		_other_items.remove_at(other_index)
		if _other_selected >= _other_items.size() and _other_items.size() > 0:
			_other_selected = _other_items.size() - 1
		elif _other_items.is_empty():
			_other_selected = 0

	EventBus.emit_inventory_drop_item(item_id, drop_count)
	return UseError.OK


# ══════════════════════════════════════
#  自动排序
# ══════════════════════════════════════

func _sort_main_slots() -> void:
	## 排序主背包：CONSUMABLE 优先 → KEY_ITEM → 空位
	## 排序后发信号通知 UI 刷新
	var filled: Array = []
	for i in range(MAIN_CAPACITY):
		if _slots[i] != null:
			filled.append(_slots[i])

	# 稳定排序：CONSUMABLE(0) < KEY_ITEM(1)
	filled.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var item_a: ItemData = a["item"] as ItemData
		var item_b: ItemData = b["item"] as ItemData
		return item_a.sub_category < item_b.sub_category
	)

	# 写回
	for i in range(MAIN_CAPACITY):
		if i < filled.size():
			_slots[i] = filled[i]
		else:
			_slots[i] = null

	EventBus.emit_inventory_slots_sorted()


# ══════════════════════════════════════
#  使用道具
# ══════════════════════════════════════

func try_use_selected() -> Dictionary:
	## 尝试使用当前选中格的道具
	## 返回 { "ok": bool, "err": UseError }
	if _state != BagState.OPEN_MAIN:
		return { "ok": false, "err": UseError.ERR_STATE_BLOCKED }
	if _use_lock_timer > 0.0:
		return { "ok": false, "err": UseError.ERR_COOLDOWN }
	# "+" 格不可使用
	if _selected_slot >= MAIN_CAPACITY:
		return { "ok": false, "err": UseError.ERR_EMPTY_SLOT }
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

	# 按 use_type 分发使用逻辑
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

	return result


func _dispatch_use(item: ItemData, slot_index: int) -> Dictionary:
	match item.use_type:
		ItemData.UseType.HEAL:
			return _use_heal(item, slot_index)
		ItemData.UseType.SUMMON_SPRITE:
			return _use_healing_sprite_item(item, slot_index)
		ItemData.UseType.ATTACK_MAGIC:
			return _use_attack_magic(item, slot_index)
		ItemData.UseType.DEPLOY_PROP:
			return _use_puzzle_prop(item, slot_index)
		ItemData.UseType.SUMMON_CHIMERA:
			return _use_chimera_capsule(item, slot_index)
		ItemData.UseType.NONE:
			# 关键道具 / 无效果道具：触发事件但不消耗
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
	return false
