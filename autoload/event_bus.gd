extends Node


# 雷击
signal thunder_burst(add_seconds: float)

# 光照（例如打雷花的LightArea）
signal light_started(source_id: int, remaining_time: float, source_light_area: Area2D)
signal light_finished(source_id: int)

# 锁链UI最小事件
signal chain_fired(chain_id: int)
signal chain_bound(chain_id: int, target: Node, attribute_type: int, icon_id: int, is_chimera: bool, show_anim: bool)
signal chain_released(chain_id: int, reason: StringName)
signal chain_struggle_progress(chain_id: int, t01: float)
signal slot_switched(active_slot: int)
signal fusion_rejected()

# ——可选：统一出口（推荐用这些函数发事件，便于以后加日志/断点）
func emit_thunder_burst(add_seconds: float) -> void:
	thunder_burst.emit(add_seconds)

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
