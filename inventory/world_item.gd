class_name WorldItem
extends Node2D

## 世界中的可拾取道具节点
## 功能：玩家靠近后出现交互提示，按 Space 拾取，道具飞向玩家后进入背包
## 由敌人死亡时 spawn，或关卡设计师手动放置

@export var item_resource: ItemData = null
@export var item_count: int = 1
@export var interact_range: float = 80.0    # 交互范围
@export var prompt_range: float = 120.0     # 显示提示范围
@export var fly_duration: float = 0.35      # 飞行动画时长
@export var bob_amplitude: float = 4.0      # 上下浮动幅度
@export var bob_speed: float = 2.5          # 上下浮动速度

# ── 状态 ──
enum State { IDLE, PROMPT, FLYING, COLLECTED }
var _state: int = State.IDLE
var _player: Player = null
var _sprite: Sprite2D = null
var _prompt_label: Label = null
var _bob_time: float = 0.0
var _base_y: float = 0.0
var _fly_tween: Tween = null


func _ready() -> void:
	_base_y = position.y

	# 图标精灵
	_sprite = Sprite2D.new()
	if item_resource != null and item_resource.drop_sprite != null:
		_sprite.texture = item_resource.drop_sprite
	else:
		# 占位：加载 icon.svg
		var tex: Texture2D = load("res://icon.svg") as Texture2D
		if tex != null:
			_sprite.texture = tex
	_sprite.scale = Vector2(0.4, 0.4)
	add_child(_sprite)

	# 交互提示
	_prompt_label = Label.new()
	_prompt_label.text = "[E]"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 11)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.7, 0.9))
	_prompt_label.position = Vector2(-24, -40)
	_prompt_label.visible = false
	add_child(_prompt_label)

	# 出生弹跳动画
	_play_spawn_bounce()


func setup(item: ItemData, count: int = 1) -> void:
	item_resource = item
	item_count = count
	if _sprite != null and item.drop_sprite != null:
		_sprite.texture = item.drop_sprite


func _process(dt: float) -> void:
	if _state == State.COLLECTED or _state == State.FLYING:
		return

	# 上下浮动
	_bob_time += dt
	if _sprite != null:
		_sprite.position.y = sin(_bob_time * bob_speed * TAU) * bob_amplitude

	# 找玩家
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			_set_prompt(false)
			return

	var dist: float = global_position.distance_to(_player.global_position)

	if dist <= interact_range:
		_set_prompt(true)
		_state = State.PROMPT
	elif dist <= prompt_range:
		_set_prompt(true)
		_state = State.PROMPT
	else:
		_set_prompt(false)
		_state = State.IDLE


func _unhandled_input(event: InputEvent) -> void:
	if _state != State.PROMPT:
		return
	if _player == null or not is_instance_valid(_player):
		return

	# E 键拾取（背包关闭时才响应，避免与背包内使用冲突）
	if event is InputEventKey:
		var ek: InputEventKey = event as InputEventKey
		if ek.pressed and not ek.echo and ek.physical_keycode == KEY_E:
			# 背包打开时不拦截
			if _player.inventory != null and _player.inventory.is_open():
				return
			var dist: float = global_position.distance_to(_player.global_position)
			if dist <= interact_range:
				_try_collect()
				get_viewport().set_input_as_handled()


func _try_collect() -> void:
	if item_resource == null:
		return
	if _player == null or _player.inventory == null:
		return

	# 按子分类路由：MATERIAL 进入 OtherItems，其余进入主背包
	if item_resource.sub_category == ItemData.SubCategory.MATERIAL:
		var ok: bool = _player.inventory.add_other_item(item_resource, item_count)
		if not ok:
			_play_reject_shake()
			return
	else:
		var slot_idx: int = _player.inventory.add_item(item_resource, item_count)
		if slot_idx < 0:
			# 背包满了 — 抖动提示
			_play_reject_shake()
			return

	# 开始飞行动画
	_state = State.FLYING
	_set_prompt(false)
	_play_fly_to_player()


func _play_fly_to_player() -> void:
	if _fly_tween != null and _fly_tween.is_valid():
		_fly_tween.kill()

	_fly_tween = create_tween()
	_fly_tween.set_parallel(true)

	# 飞向玩家位置（带弧线：先往上飘再落向玩家）
	var target_pos: Vector2 = _player.global_position + Vector2(0, -30)
	var mid_y: float = min(global_position.y, target_pos.y) - 60.0

	# 水平移动
	_fly_tween.tween_property(self, "global_position:x", target_pos.x, fly_duration).set_ease(Tween.EASE_IN)

	# 垂直：先上后下弧线
	_fly_tween.tween_property(self, "global_position:y", mid_y, fly_duration * 0.4).set_ease(Tween.EASE_OUT)
	_fly_tween.chain().tween_property(self, "global_position:y", target_pos.y, fly_duration * 0.6).set_ease(Tween.EASE_IN)

	# 缩小 + 淡出
	_fly_tween.tween_property(_sprite, "scale", Vector2(0.1, 0.1), fly_duration).set_ease(Tween.EASE_IN)
	_fly_tween.tween_property(_sprite, "modulate:a", 0.0, fly_duration * 0.8).set_delay(fly_duration * 0.2)

	_fly_tween.set_parallel(false)
	_fly_tween.tween_callback(_on_fly_done)


func _on_fly_done() -> void:
	_state = State.COLLECTED
	queue_free()


func _play_spawn_bounce() -> void:
	# 出生时从地面弹起的小动画
	var target_y: float = _base_y
	position.y = _base_y + 10.0
	if _sprite != null:
		_sprite.scale = Vector2.ZERO
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", target_y - 20.0, 0.2).set_ease(Tween.EASE_OUT)
	if _sprite != null:
		tw.tween_property(_sprite, "scale", Vector2(0.4, 0.4), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.set_parallel(false)
	tw.tween_property(self, "position:y", target_y, 0.15).set_ease(Tween.EASE_IN)


func _play_reject_shake() -> void:
	var tw: Tween = create_tween()
	var ox: float = position.x
	tw.tween_property(self, "position:x", ox + 3.0, 0.04)
	tw.tween_property(self, "position:x", ox - 3.0, 0.04)
	tw.tween_property(self, "position:x", ox + 1.5, 0.04)
	tw.tween_property(self, "position:x", ox, 0.04)


func _set_prompt(show: bool) -> void:
	if _prompt_label != null:
		_prompt_label.visible = show


func _find_player() -> Player:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Player
