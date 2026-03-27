class_name InventoryUI
extends Control

## 背包 UI 主控制器
## 职责：管理展开/收回动画、格子高亮导航、说明框触发、输入路由
## 挂在 GameUI 下，通过 EventBus 与 PlayerInventory 通信

# ── 状态机（镜像 PlayerInventory.BagState）──
enum UIState { CLOSED, OPENING, OPEN, CLOSING }

# ── 配置 ──
const SLOT_COUNT: int = 10
const OPEN_DURATION: float = 0.18     # 展开动画时长
const CLOSE_DURATION: float = 0.15    # 收回动画时长
const TOOLTIP_HOVER_SEC: float = 3.0  # 高亮停留触发说明框的秒数
const SLOT_SIZE: float = 56.0
const SLOT_GAP: float = 4.0
const STAGGER_DELAY: float = 0.02     # 格子依次弹出的间隔

# ── 子节点 ──
var _bag_icon: TextureRect = null
var _count_badge: Label = null
var _panel: PanelContainer = null
var _slots_container: HBoxContainer = null
var _slots: Array = []  # Array[InventorySlotUI]
var _tooltip: ItemTooltipUI = null
var _dimmer: ColorRect = null  # 半透明背景遮罩

# ── 状态 ──
var _ui_state: int = UIState.CLOSED
var _selected_slot: int = 0
var _hover_elapsed: float = 0.0
var _tooltip_shown: bool = false
var _anim_tween: Tween = null
var _player_inventory: PlayerInventory = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_connect_signals()


func setup(inventory: PlayerInventory) -> void:
	_player_inventory = inventory


func _build_ui() -> void:
	# ── 半透明遮罩（背包打开时） ──
	_dimmer = ColorRect.new()
	_dimmer.color = Color(0.0, 0.0, 0.0, 0.3)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.visible = false
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dimmer)

	# ── 常驻背包小图标（右下角） ──
	_bag_icon = TextureRect.new()
	_bag_icon.custom_minimum_size = Vector2(36, 36)
	_bag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# 使用占位色块代替实际纹理（后续替换为美术资源）
	var icon_bg: ColorRect = ColorRect.new()
	icon_bg.color = Color(0.3, 0.25, 0.45, 0.85)
	icon_bg.custom_minimum_size = Vector2(36, 36)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_container: Control = Control.new()
	icon_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	icon_container.offset_left = -52.0
	icon_container.offset_top = -52.0
	icon_container.offset_right = -12.0
	icon_container.offset_bottom = -12.0
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_container)
	icon_container.add_child(icon_bg)
	icon_container.add_child(_bag_icon)

	# 计数角标
	_count_badge = Label.new()
	_count_badge.text = "0"
	_count_badge.add_theme_font_size_override("font_size", 10)
	_count_badge.add_theme_color_override("font_color", Color.WHITE)
	_count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_badge.position = Vector2(24, -2)
	icon_container.add_child(_count_badge)

	# ── 展开面板 ──
	_panel = PanelContainer.new()
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.05, 0.1, 0.88)
	panel_style.border_color = Color(0.5, 0.4, 0.8, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 水平居中，屏幕下部
	var total_width: float = SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP + 24.0
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -total_width * 0.5
	_panel.offset_right = total_width * 0.5
	_panel.offset_top = -90.0
	_panel.offset_bottom = -14.0
	_panel.scale = Vector2.ZERO
	_panel.pivot_offset = Vector2(total_width * 0.5, 38.0)
	_panel.visible = false
	add_child(_panel)

	# 格子容器
	_slots_container = HBoxContainer.new()
	_slots_container.add_theme_constant_override("separation", int(SLOT_GAP))
	_slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_slots_container)

	# 创建 10 个格子
	_slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		var slot_ui: InventorySlotUI = InventorySlotUI.new()
		slot_ui.slot_index = i
		slot_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slots_container.add_child(slot_ui)
		_slots[i] = slot_ui

	# ── 说明浮窗 ──
	_tooltip = ItemTooltipUI.new()
	add_child(_tooltip)


func _connect_signals() -> void:
	EventBus.inventory_opened.connect(_on_inventory_opened)
	EventBus.inventory_closed.connect(_on_inventory_closed)
	EventBus.inventory_selection_changed.connect(_on_selection_changed)
	EventBus.inventory_item_added.connect(_on_item_added)
	EventBus.inventory_item_removed.connect(_on_item_removed)
	EventBus.inventory_item_used.connect(_on_item_used)
	EventBus.inventory_item_failed.connect(_on_item_failed)
	EventBus.inventory_full.connect(_on_inventory_full)


func _process(dt: float) -> void:
	if _ui_state != UIState.OPEN:
		return

	# Tooltip 计时
	_hover_elapsed += dt
	if not _tooltip_shown and _hover_elapsed >= TOOLTIP_HOVER_SEC:
		_show_tooltip_for_selected()

	# 实时更新冷却显示
	_refresh_slots_display()


# ══════════════════════════════════════
#  EventBus 回调
# ══════════════════════════════════════

func _on_inventory_opened() -> void:
	_ui_state = UIState.OPENING
	_play_open_animation()


func _on_inventory_closed() -> void:
	_ui_state = UIState.CLOSING
	_hide_tooltip()
	_play_close_animation()


func _on_selection_changed(slot_idx: int) -> void:
	var old_idx: int = _selected_slot
	_selected_slot = slot_idx

	# 更新高亮
	for i in range(SLOT_COUNT):
		(_slots[i] as InventorySlotUI).set_highlighted(i == slot_idx)

	# 重置 hover 计时
	if old_idx != slot_idx:
		_hover_elapsed = 0.0
		_hide_tooltip()


func _on_item_added(slot_idx: int, item: Resource, count: int) -> void:
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	var item_data: ItemData = item as ItemData
	(_slots[slot_idx] as InventorySlotUI).set_slot_data(item_data, count, 0.0)
	_update_count_badge()


func _on_item_removed(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	(_slots[slot_idx] as InventorySlotUI).clear_slot()
	_update_count_badge()


func _on_item_used(_item_id: StringName, slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	(_slots[slot_idx] as InventorySlotUI).play_use_flash()


func _on_item_failed(_item_id: StringName, slot_idx: int, _err_code: int) -> void:
	if slot_idx < 0 or slot_idx >= SLOT_COUNT:
		return
	(_slots[slot_idx] as InventorySlotUI).play_fail_shake()


func _on_inventory_full() -> void:
	# 背包满时闪烁 bag icon
	if _count_badge != null:
		var tw: Tween = create_tween()
		_count_badge.add_theme_color_override("font_color", Color.RED)
		tw.tween_interval(0.5)
		tw.tween_callback(func() -> void:
			_count_badge.add_theme_color_override("font_color", Color.WHITE)
		)


# ══════════════════════════════════════
#  动画
# ══════════════════════════════════════

func _play_open_animation() -> void:
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()

	_dimmer.visible = true
	_dimmer.color.a = 0.0
	_panel.visible = true
	_panel.scale = Vector2.ZERO

	# 所有格子初始隐藏
	for i in range(SLOT_COUNT):
		(_slots[i] as InventorySlotUI).scale = Vector2.ZERO
		(_slots[i] as InventorySlotUI).modulate.a = 0.0

	_anim_tween = create_tween()
	_anim_tween.set_parallel(true)

	# 遮罩淡入
	_anim_tween.tween_property(_dimmer, "color:a", 0.3, OPEN_DURATION)

	# 面板弹出
	_anim_tween.tween_property(_panel, "scale", Vector2.ONE, OPEN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# 格子依次 stagger pop-in
	for i in range(SLOT_COUNT):
		var slot: InventorySlotUI = _slots[i] as InventorySlotUI
		var delay: float = OPEN_DURATION * 0.5 + i * STAGGER_DELAY
		_anim_tween.tween_property(slot, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(delay)
		_anim_tween.tween_property(slot, "modulate:a", 1.0, 0.08).set_delay(delay)

	_anim_tween.set_parallel(false)
	_anim_tween.tween_callback(_on_open_anim_done)


func _on_open_anim_done() -> void:
	_ui_state = UIState.OPEN
	_hover_elapsed = 0.0
	_refresh_slots_display()

	# 高亮默认格
	for i in range(SLOT_COUNT):
		(_slots[i] as InventorySlotUI).set_highlighted(i == _selected_slot)

	# 通知逻辑层动画完成
	if _player_inventory != null:
		_player_inventory.on_open_animation_finished()


func _play_close_animation() -> void:
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()

	_anim_tween = create_tween()

	# 格子同时缩小
	_anim_tween.set_parallel(true)
	for i in range(SLOT_COUNT):
		var slot: InventorySlotUI = _slots[i] as InventorySlotUI
		slot.set_highlighted(false)
		_anim_tween.tween_property(slot, "scale", Vector2.ZERO, CLOSE_DURATION * 0.6).set_ease(Tween.EASE_IN)
		_anim_tween.tween_property(slot, "modulate:a", 0.0, CLOSE_DURATION * 0.6)

	# 面板缩小
	_anim_tween.tween_property(_panel, "scale", Vector2.ZERO, CLOSE_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_anim_tween.tween_property(_dimmer, "color:a", 0.0, CLOSE_DURATION)

	_anim_tween.set_parallel(false)
	_anim_tween.tween_callback(_on_close_anim_done)


func _on_close_anim_done() -> void:
	_ui_state = UIState.CLOSED
	_panel.visible = false
	_dimmer.visible = false

	if _player_inventory != null:
		_player_inventory.on_close_animation_finished()


# ══════════════════════════════════════
#  Tooltip
# ══════════════════════════════════════

func _show_tooltip_for_selected() -> void:
	if _player_inventory == null:
		return
	var slot_data: Dictionary = _player_inventory.get_slot(_selected_slot)
	if slot_data.is_empty():
		return
	var item: ItemData = slot_data["item"] as ItemData
	var count: int = slot_data["count"] as int
	var slot_ui: InventorySlotUI = _slots[_selected_slot] as InventorySlotUI
	_tooltip.show_for_item(item, count, slot_ui.global_position)
	_tooltip_shown = true


func _hide_tooltip() -> void:
	if _tooltip_shown:
		_tooltip.hide_tooltip()
		_tooltip_shown = false


# ══════════════════════════════════════
#  数据刷新
# ══════════════════════════════════════

func _refresh_slots_display() -> void:
	if _player_inventory == null:
		return
	var snapshot: Array = _player_inventory.get_slots_snapshot()
	for i in range(SLOT_COUNT):
		var slot_ui: InventorySlotUI = _slots[i] as InventorySlotUI
		var data: Dictionary = snapshot[i] as Dictionary
		if data.is_empty():
			slot_ui.clear_slot()
		else:
			var item: ItemData = data["item"] as ItemData
			var count: int = data["count"] as int
			var cd: float = data["cooldown"] as float
			var cd_ratio: float = 0.0
			if item.cooldown_sec > 0.0 and cd > 0.0:
				cd_ratio = cd / item.cooldown_sec
			slot_ui.set_slot_data(item, count, cd_ratio)


func _update_count_badge() -> void:
	if _player_inventory == null:
		return
	_count_badge.text = str(_player_inventory.get_item_count())
