extends Node


# 雷击
signal thunder_burst(add_seconds: float)

# 治愈精灵大爆炸（全场光照事件）
signal healing_burst(light_energy: float)

# 光照（例如打雷花的LightArea）
signal light_started(source_id: int, remaining_time: float, source_light_area: Area2D)
signal light_finished(source_id: int)

# 锁链UI最小事件
signal chain_fired(chain_id: int)
signal chain_bound(chain_id: int, target: Node, attribute_type: int, icon_id: int, is_chimera: bool, show_anim: bool)
signal chain_released(chain_id: int, reason: StringName)
signal chain_struggle_progress(chain_id: int, t01: float)
@warning_ignore("unused_signal")
signal slot_switched(active_slot: int)
@warning_ignore("unused_signal")
signal fusion_rejected()

# ——可选：统一出口（推荐用这些函数发事件，便于以后加日志/断点）
func emit_thunder_burst(add_seconds: float) -> void:
	thunder_burst.emit(add_seconds)

func emit_healing_burst(light_energy: float) -> void:
	healing_burst.emit(light_energy)

func emit_light_started(source_id: int, remaining_time: float, source_light_area: Area2D) -> void:
	light_started.emit(source_id, remaining_time, source_light_area)

func emit_light_finished(source_id: int) -> void:
	light_finished.emit(source_id)

func emit_chain_fired(chain_id: int) -> void:
	chain_fired.emit(chain_id)

func emit_chain_bound(chain_id: int, target: Node, attribute_type: int, icon_id: int, is_chimera: bool = false, show_anim: bool = false) -> void:
	chain_bound.emit(chain_id, target, attribute_type, icon_id, is_chimera, show_anim)

func emit_chain_released(chain_id: int, reason: StringName) -> void:
	chain_released.emit(chain_id, reason)

func emit_chain_struggle_progress(chain_id: int, t01: float) -> void:
	chain_struggle_progress.emit(chain_id, clamp(t01, 0.0, 1.0))

func emit_slot_switched(active_slot: int) -> void:
	slot_switched.emit(active_slot)

func emit_fusion_rejected() -> void:
	fusion_rejected.emit()


# ── 背包事件 ──
@warning_ignore("unused_signal")
signal inventory_opened()
@warning_ignore("unused_signal")
signal inventory_closed()
@warning_ignore("unused_signal")
signal inventory_selection_changed(slot_idx: int)
@warning_ignore("unused_signal")
signal inventory_item_added(slot_idx: int, item: Resource, count: int)
@warning_ignore("unused_signal")
signal inventory_item_removed(slot_idx: int)
@warning_ignore("unused_signal")
signal inventory_item_used(item_id: StringName, slot_idx: int)
@warning_ignore("unused_signal")
signal inventory_item_failed(item_id: StringName, slot_idx: int, err_code: int)
@warning_ignore("unused_signal")
signal inventory_full()

func emit_inventory_opened() -> void:
	inventory_opened.emit()

func emit_inventory_closed() -> void:
	inventory_closed.emit()

func emit_inventory_selection_changed(slot_idx: int) -> void:
	inventory_selection_changed.emit(slot_idx)

func emit_inventory_item_added(slot_idx: int, item: Resource, count: int) -> void:
	inventory_item_added.emit(slot_idx, item, count)

func emit_inventory_item_removed(slot_idx: int) -> void:
	inventory_item_removed.emit(slot_idx)

func emit_inventory_item_used(item_id: StringName, slot_idx: int) -> void:
	inventory_item_used.emit(item_id, slot_idx)

func emit_inventory_item_failed(item_id: StringName, slot_idx: int, err_code: int) -> void:
	inventory_item_failed.emit(item_id, slot_idx, err_code)

func emit_inventory_full() -> void:
	inventory_full.emit()

# ── 背包扩展事件（v0.2 物品系统升级） ──
@warning_ignore("unused_signal")
signal inventory_pickup_failed(item_id: StringName, reason: int)
@warning_ignore("unused_signal")
signal inventory_open_other_items()
@warning_ignore("unused_signal")
signal inventory_close_other_items()
@warning_ignore("unused_signal")
signal inventory_drop_item(item_id: StringName, count: int)
@warning_ignore("unused_signal")
signal inventory_slots_sorted()

func emit_inventory_pickup_failed(item_id: StringName, reason: int) -> void:
	inventory_pickup_failed.emit(item_id, reason)

func emit_inventory_open_other_items() -> void:
	inventory_open_other_items.emit()

func emit_inventory_close_other_items() -> void:
	inventory_close_other_items.emit()

func emit_inventory_drop_item(item_id: StringName, count: int) -> void:
	inventory_drop_item.emit(item_id, count)

func emit_inventory_slots_sorted() -> void:
	inventory_slots_sorted.emit()
