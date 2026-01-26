extends Control
class_name ChainSlotsUI

@onready var slot_a: Control = $SlotA
@onready var slot_b: Control = $SlotB
@onready var connection_line: Control = $ConnectionLine
@onready var center_icon: TextureRect = $ConnectionLine/CenterIcon

var slot_states: Array[Dictionary] = [{}, {}]
var slot_anim_playing: Array[bool] = [false, false]  # 追踪动画状态
var _cooldown_tweens: Array[Tween] = [null, null]
var _cooldown_duration: float = 0.5
@export var ui_no: Texture2D = preload("res://art/UI_NO.png")
@export var ui_die: Texture2D = preload("res://art/UI_DIE.png")
@export var ui_yes: Texture2D = preload("res://art/UI_yes.png")
@export var cooldown_shader: Shader = preload("res://shaders/chain_cooldown_fill.gdshader")



func _ready() -> void:
	EventBus.slot_switched.connect(_on_slot_switched)
	EventBus.chain_fired.connect(_on_chain_fired)
	EventBus.chain_bound.connect(_on_chain_bound)
	EventBus.chain_released.connect(_on_chain_released)
	EventBus.chain_struggle_progress.connect(_on_chain_struggle_progress)

	EventBus.fusion_rejected.connect(_on_fusion_rejected)
	_update_active_indicator(1)
	connection_line.visible = false
	_resolve_cooldown_duration()
	_setup_slot_cooldown(slot_a)
	_setup_slot_cooldown(slot_b)

func _on_slot_switched(active_slot: int) -> void:
	_update_active_indicator(active_slot)

func _update_active_indicator(active_slot: int) -> void:
	var indicator_a: ColorRect = slot_a.get_node_or_null("ActiveIndicator") as ColorRect
	var indicator_b: ColorRect = slot_b.get_node_or_null("ActiveIndicator") as ColorRect
	if indicator_a:
		indicator_a.visible = (active_slot == 0)
	if indicator_b:
		indicator_b.visible = (active_slot == 1)

func _on_chain_fired(slot: int) -> void:
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var flash: ColorRect = slot_node.get_node_or_null("FlashOverlay") as ColorRect
	if flash:
		flash.modulate.a = 1.0
		var tw: Tween = create_tween()
		tw.tween_property(flash, "modulate:a", 0.0, 0.2)
	_set_cooldown_progress(slot, 0.0)
	_stop_cooldown_tween(slot)

func _on_chain_bound(slot: int, target: Node, attribute: int, icon_id: int, is_chimera: bool, show_anim: bool) -> void:
	slot_states[slot] = {
		"target": target,
		"attribute": attribute,
		"icon": icon_id,
		"progress": 0.0,
		"is_chimera": is_chimera,
		"anim_played": "",  # 记录播放的动画名
		"anim_length": 0.0
	}
	
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect

	var anim_path: NodePath = NodePath("Control/AnimationPlayer")
	var anim: AnimationPlayer = slot_node.get_node_or_null(anim_path) as AnimationPlayer

	if icon:
		icon.visible = true
		_set_cooldown_progress(slot, 0.0)

	if anim and show_anim:
		var anim_name: String = ""
		if is_chimera:
			# 尝试两个可能的名字
			if anim.has_animation("chimera_animation"):
				anim_name = "chimera_animation"
			elif anim.has_animation("chimera_animation "):
				anim_name = "chimera_animation "
		else:
			if anim.has_animation("appear"):
				anim_name = "appear"
		
		if anim_name != "":
			slot_states[slot]["anim_played"] = anim_name
			if anim_name == "appear":
				var anim_ref: Animation = anim.get_animation(anim_name)
				var anim_length: float = anim_ref.length if anim_ref != null else 0.0
				slot_states[slot]["anim_length"] = anim_length
				anim.play(anim_name)
				anim.pause()
				if anim_length > 0.0:
					anim.seek(anim_length, true)
			else:
				anim.play(anim_name)

	_shake_node(slot_node)
	_check_fusion_available()

func _on_chain_released(slot: int, _reason: StringName) -> void:
	var played_anim: String = slot_states[slot].get("anim_played", "")
	slot_states[slot] = {}
	
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	
	var anim_path: NodePath = NodePath("Control/AnimationPlayer")
	var anim: AnimationPlayer = slot_node.get_node_or_null(anim_path) as AnimationPlayer
	
	if icon:
		icon.visible = true
	_start_cooldown(slot)
	
	if anim and played_anim != "" and anim.has_animation(played_anim):
		if played_anim == "appear":
			anim.stop()
		else:
			anim.stop()
			anim.play_backwards(played_anim)
	
	_check_fusion_available()

func _on_chain_struggle_progress(slot: int, t01: float) -> void:
	if slot_states[slot].is_empty():
		return
	slot_states[slot]["progress"] = t01
	var played_anim: String = slot_states[slot].get("anim_played", "")
	if played_anim != "appear":
		return
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var anim: AnimationPlayer = slot_node.get_node_or_null(NodePath("Control/AnimationPlayer")) as AnimationPlayer
	if anim and anim.has_animation(played_anim):
		var anim_length: float = slot_states[slot].get("anim_length", 0.0)
		if anim_length <= 0.0:
			var anim_ref: Animation = anim.get_animation(played_anim)
			anim_length = anim_ref.length if anim_ref != null else 0.0
		if anim_length > 0.0:
			anim.seek(anim_length * (1.0 - t01), true)

func _check_fusion_available() -> void:
	if slot_states[0].is_empty() or slot_states[1].is_empty():
		connection_line.visible = false
		return
	
	connection_line.visible = true
	
	var target0: Node = slot_states[0].target
	var target1: Node = slot_states[1].target
	var attr0: int = slot_states[0].attribute
	var attr1: int = slot_states[1].attribute
	
	if target0 == target1:
		center_icon.texture = ui_no
	elif (attr0 == 1 and attr1 == 2) or (attr0 == 2 and attr1 == 1):
		center_icon.texture = ui_die
	else:
		center_icon.texture = ui_yes
	
	center_icon.visible = true

func _on_fusion_rejected() -> void:
	if not slot_states[0].is_empty():
		_shake_node(slot_a)
	if not slot_states[1].is_empty():
		_shake_node(slot_b)

func _setup_slot_cooldown(slot_node: Control) -> void:
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	if icon == null or cooldown_shader == null:
		return
	icon.visible = true
	if icon.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = cooldown_shader
		icon.material = mat
	_set_icon_progress(icon, 1.0)

func _set_cooldown_progress(slot: int, t01: float) -> void:
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	if icon == null:
		return
	_set_icon_progress(icon, t01)

func _set_icon_progress(icon: TextureRect, t01: float) -> void:
	var mat: ShaderMaterial = icon.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("progress", clamp(t01, 0.0, 1.0))

func _resolve_cooldown_duration() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node = players[0] as Node
	if player == null:
		return
	var value: Variant = player.get("burn_time")
	if typeof(value) == TYPE_FLOAT:
		_cooldown_duration = maxf(value, 0.0)

func _stop_cooldown_tween(slot: int) -> void:
	var tw: Tween = _cooldown_tweens[slot]
	if tw != null:
		tw.kill()
	_cooldown_tweens[slot] = null

func _start_cooldown(slot: int) -> void:
	_stop_cooldown_tween(slot)
	_set_cooldown_progress(slot, 0.0)
	if _cooldown_duration <= 0.0:
		_set_cooldown_progress(slot, 1.0)
		return
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	if icon == null:
		return
	var mat: ShaderMaterial = icon.material as ShaderMaterial
	if mat == null:
		return
	var tw: Tween = create_tween()
	_cooldown_tweens[slot] = tw
	tw.tween_property(mat, "shader_parameter/progress", 1.0, _cooldown_duration)

func _shake_node(node: Control) -> void:
	var original_pos: Vector2 = node.position
	var tw: Tween = create_tween()
	tw.tween_property(node, "position:x", original_pos.x + 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x - 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x + 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x - 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x, 0.05)
