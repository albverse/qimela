## 对话系统测试场景控制脚本
## 按下 "开始对话" 按钮后，自动播放一段含多种情绪的测试对话
## 完整测试：气泡推进 / 历史气泡 / 说话动画 / 情绪切换 / 强制推进
extends Node

# ── 对话序列 ──
## 每条记录：[role, emotion, use_talk, speaker_name, text]
const DIALOGUE_LINES: Array = [
	[&"other",  &"idle",  true,  "神秘人",  "终于出现了……我已经等候多时。"],
	[&"player", &"idle",  true,  "玩家",    "你是谁？为什么跟踪我？"],
	[&"other",  &"angry", true,  "神秘人",  "跟踪？哈！是你自己送上门来的。"],
	[&"other",  &"angry", true,  "神秘人",  "你以为这一切只是偶然吗？"],
	[&"player", &"angry", true,  "玩家",    "说清楚！否则别怪我动手！"],
	[&"other",  &"idle",  true,  "神秘人",  "冷静下来，孩子。我们在同一边。"],
	[&"player", &"idle",  false, "玩家",    "……"],
	[&"other",  &"idle",  true,  "神秘人",  "跟我来，一切都会有解释的。"],
]

var _current_line: int = 0
var _in_dialogue: bool = false

# ── 节点引用 ──
var _bubble_layer: DialogueBubbleLayer
var _player_portrait_ctrl: SpinePortraitController
var _other_portrait_ctrl: SpinePortraitController
var _start_btn: Button
var _next_btn: Button
var _status_label: Label


func _ready() -> void:
	_build_scene()
	_start_btn.pressed.connect(_on_start_pressed)
	_next_btn.pressed.connect(_on_next_pressed)


## ── 场景构建 ──

func _build_scene() -> void:
	# 背景
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 立绘层（Node2D）
	var portrait_root: Node2D = Node2D.new()
	portrait_root.name = "PortraitRoot"
	add_child(portrait_root)

	# 玩家立绘（左）
	var player_root: Node2D = _build_portrait_root(
		portrait_root,
		"PlayerPortrait",
		Vector2(300, 400),
		false,   # 不翻转
		&"type1" # 玩家用 type1 皮肤
	)
	_player_portrait_ctrl = player_root.get_node("PortraitController")

	# 对方立绘（右）
	var other_root: Node2D = _build_portrait_root(
		portrait_root,
		"OtherPortrait",
		Vector2(900, 400),
		true,    # 翻转（面向左侧）
		&"type2" # 对方用 type2 皮肤
	)
	_other_portrait_ctrl = other_root.get_node("PortraitController")

	# 对话层（CanvasLayer，始终在最上方）
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 10
	canvas.name = "DialogueCanvas"
	add_child(canvas)

	# BubbleLayer
	_bubble_layer = DialogueBubbleLayer.new()
	_bubble_layer.name = "BubbleLayer"
	_bubble_layer.player_current_pos = Vector2(50, 520)
	_bubble_layer.other_current_pos  = Vector2(760, 200)
	_bubble_layer.player_history_pos = Vector2(50, 370)
	_bubble_layer.other_history_pos  = Vector2(760, 60)
	_bubble_layer.player_display_name = "玩家"
	_bubble_layer.other_display_name  = "神秘人"
	_bubble_layer.bubble_width = 400.0
	_bubble_layer.bubble_font_size = 20
	# 加载对话框贴图
	var tex: Texture2D = load("res://art/dialogic_art/dialogic_text.png")
	_bubble_layer.bubble_texture = tex
	canvas.add_child(_bubble_layer)

	# 注册立绘控制器（deferred 保证 _bubble_layer._ready 已执行）
	call_deferred("_register_portraits")

	# HUD：按钮 + 状态提示
	var hud: CanvasLayer = CanvasLayer.new()
	hud.layer = 20
	add_child(hud)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.position = Vector2(20, 20)
	hud.add_child(hbox)

	_start_btn = Button.new()
	_start_btn.text = "▶ 开始对话"
	hbox.add_child(_start_btn)

	_next_btn = Button.new()
	_next_btn.text = "→ 下一句"
	_next_btn.disabled = true
	hbox.add_child(_next_btn)

	_status_label = Label.new()
	_status_label.position = Vector2(20, 60)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_status_label.text = "点击 [开始对话] 开始测试"
	hud.add_child(_status_label)


## 构建单个立绘根节点（含 SpineSprite + SpinePortraitController）
func _build_portrait_root(
		parent: Node2D,
		node_name: String,
		pos: Vector2,
		flip: bool,
		skin: StringName) -> Node2D:

	var root: Node2D = Node2D.new()
	root.name = node_name
	root.position = pos
	parent.add_child(root)

	var spine_sprite: SpineSprite = SpineSprite.new()
	spine_sprite.name = "SpineSprite"
	spine_sprite.scale = Vector2(0.35, 0.35)
	if flip:
		spine_sprite.scale = Vector2(-0.35, 0.35)

	# 加载 Spine 资源
	var skel_data: SpineSkeletonDataResource = load("res://art/dialogic_art/test_beast.tres")
	spine_sprite.skeleton_data_res = skel_data
	root.add_child(spine_sprite)

	# 立绘控制器
	var ctrl: SpinePortraitController = SpinePortraitController.new()
	ctrl.name = "PortraitController"
	ctrl.spine_sprite = spine_sprite
	ctrl.initial_skin = skin
	root.add_child(ctrl)

	return root


## ── 按钮处理 ──

func _register_portraits() -> void:
	_bubble_layer.register_portrait(&"player", _player_portrait_ctrl)
	_bubble_layer.register_portrait(&"other",  _other_portrait_ctrl)


func _on_start_pressed() -> void:
	_current_line = 0
	_in_dialogue = true
	_start_btn.disabled = true
	_next_btn.disabled = false
	_bubble_layer.clear_all()
	_play_current_line()


func _on_next_pressed() -> void:
	if not _in_dialogue:
		return
	# 强制推进：立即结束当前说话动画
	if _player_portrait_ctrl != null:
		_player_portrait_ctrl.on_force_advance()
	if _other_portrait_ctrl != null:
		_other_portrait_ctrl.on_force_advance()

	_current_line += 1
	if _current_line >= DIALOGUE_LINES.size():
		_end_dialogue()
		return
	_play_current_line()


## ── 内部 ──

func _play_current_line() -> void:
	var line: Array = DIALOGUE_LINES[_current_line]
	var role: StringName = line[0]
	var emotion: StringName = line[1]
	var use_talk: bool = line[2]
	var text: String = line[4]

	_status_label.text = "[%d/%d] %s: %s" % [
		_current_line + 1,
		DIALOGUE_LINES.size(),
		line[3],
		text
	]
	_bubble_layer.push_line(role, emotion, use_talk, text)


func _end_dialogue() -> void:
	_in_dialogue = false
	_start_btn.disabled = false
	_next_btn.disabled = true
	_status_label.text = "对话结束。点击 [开始对话] 重新测试。"
	# 立绘回到 idle
	if _player_portrait_ctrl != null:
		_player_portrait_ctrl.play_stable(&"idle")
	if _other_portrait_ctrl != null:
		_other_portrait_ctrl.play_stable(&"idle")
