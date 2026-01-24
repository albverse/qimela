extends Control

@export var max_hp: int = 5
@export var heart_full_texture: Texture2D
@export var heart_empty_texture: Texture2D
@export var heart_spacing: int = 6

# 尺寸一致但视觉仍偏时，用这个做 1~2px 微调（一般不需要）
@export var full_pixel_offset: Vector2 = Vector2.ZERO
@export var empty_pixel_offset: Vector2 = Vector2.ZERO

var _box: HBoxContainer
var _hp: int = 5

# 每个槽：slot(裁剪容器) + wrap(满心层) + min_h(用于布局未完成时兜底)
var _slots: Array[Dictionary] = []  # { "slot": Control, "wrap": Control, "min_h": float }

func _ready() -> void:
	_box = get_node_or_null(^"HeartsBox") as HBoxContainer
	if _box == null:
		push_error("[HeartsUI] Missing child node: HeartsBox (HBoxContainer).")
		return

	_box.add_theme_constant_override("separation", heart_spacing)
	_rebuild()
	# 布局可能还没完成，延后一帧应用 HP，避免 slot.size 为 0
	call_deferred("_apply_hp_instant", _hp)

func setup(new_max_hp: int, new_hp: int) -> void:
	if _box == null:
		_box = get_node_or_null(^"HeartsBox") as HBoxContainer
		if _box == null:
			push_error("[HeartsUI] Missing child node: HeartsBox (HBoxContainer).")
			return

	max_hp = max(new_max_hp, 1)
	_hp = clamp(new_hp, 0, max_hp)

	_rebuild()
	call_deferred("_apply_hp_instant", _hp)

func set_hp_instant(new_hp: int) -> void:
	_hp = clamp(new_hp, 0, max_hp)
	call_deferred("_apply_hp_instant", _hp)

func play_heal_fill(from_hp: int, to_hp: int, step_time: float = 0.18) -> void:
	from_hp = clamp(from_hp, 0, max_hp)
	to_hp = clamp(to_hp, 0, max_hp)

	if to_hp <= from_hp:
		set_hp_instant(to_hp)
		return

	# 先显示到 from_hp（延后一帧确保 slot.size 有值）
	set_hp_instant(from_hp)
	await get_tree().process_frame

	for i in range(from_hp, to_hp):
		if i >= _slots.size():
			break
		var slot: Control = _slots[i]["slot"]
		var wrap: Control = _slots[i]["wrap"]
		_animate_fill(slot, wrap, step_time)
		await get_tree().create_timer(step_time).timeout

	set_hp_instant(to_hp)

func _rebuild() -> void:
	if _box == null:
		return

	for c in _box.get_children():
		c.queue_free()
	_slots.clear()

	if heart_full_texture == null or heart_empty_texture == null:
		# 贴图没设置时不崩溃，只是不显示
		return

	var sz_full := Vector2(heart_full_texture.get_size())
	var sz_empty := Vector2(heart_empty_texture.get_size())
	var slot_sz := Vector2(maxf(sz_full.x, sz_empty.x), maxf(sz_full.y, sz_empty.y))

	for i in range(max_hp):
		# 裁剪槽
		var slot := Control.new()
		slot.custom_minimum_size = slot_sz
		slot.clip_contents = true

		# 空心：始终 FULL_RECT，跟随 slot 实际尺寸变化
		var empty := TextureRect.new()
		empty.texture = heart_empty_texture
		empty.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		empty.set_anchors_preset(Control.PRESET_FULL_RECT)
		# 像素偏移（保持大小不变，只平移）
		empty.offset_left = empty_pixel_offset.x
		empty.offset_right = empty_pixel_offset.x
		empty.offset_top = empty_pixel_offset.y
		empty.offset_bottom = empty_pixel_offset.y

		# wrap：满心层容器，也必须 FULL_RECT（关键修复点）
		var wrap := Control.new()
		wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
		wrap.offset_left = 0
		wrap.offset_right = 0
		wrap.offset_top = 0
		wrap.offset_bottom = 0

		# 满心：FULL_RECT + KEEP_CENTERED，和 empty 同一套对齐规则
		var full := TextureRect.new()
		full.texture = heart_full_texture
		full.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.offset_left = full_pixel_offset.x
		full.offset_right = full_pixel_offset.x
		full.offset_top = full_pixel_offset.y
		full.offset_bottom = full_pixel_offset.y

		wrap.add_child(full)
		slot.add_child(empty)
		slot.add_child(wrap)
		_box.add_child(slot)

		_slots.append({ "slot": slot, "wrap": wrap, "min_h": slot_sz.y })

func _apply_hp_instant(hp: int) -> void:
	for i in range(_slots.size()):
		var slot: Control = _slots[i]["slot"]
		var wrap: Control = _slots[i]["wrap"]
		var min_h: float = _slots[i]["min_h"]

		var h := slot.size.y
		if h <= 0.0:
			h = min_h

		wrap.position = Vector2(0, 0) if i < hp else Vector2(0, h)

func _animate_fill(slot: Control, wrap: Control, t: float) -> void:
	var h := slot.size.y
	if h <= 0.0:
		h = wrap.size.y
		if h <= 0.0:
			h = 32.0 # 兜底，不应触发

	wrap.position = Vector2(0, h)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(wrap, "position", Vector2(0, 0), t)
