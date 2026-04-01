extends RefCounted
class_name BubbleStyleController

## 气泡样式控制器
## 职责：根据 role / style_id / history state 应用样式资源
## 不决定气泡何时迁移，不解析对话标签

const LOG_PREFIX: String = "[BubbleStyle]"
var debug_log: bool = false

## 默认气泡样式纹理路径
var player_bubble_texture_path: String = "res://dialogue_test/dialogic_art/dialogic_text_player.png"
var other_bubble_texture_path: String = "res://dialogue_test/dialogic_art/dialogic_text_character.png"

## 历史态参数
var history_opacity: float = 0.5

## 缓存的纹理
var _player_texture: Texture2D = null
var _other_texture: Texture2D = null


func get_bubble_texture(role: StringName, style_override: StringName = &"") -> Texture2D:
	# 如果有 override，可在此扩展
	if role == &"player":
		if _player_texture == null:
			_player_texture = load(player_bubble_texture_path) as Texture2D
		return _player_texture
	else:
		if _other_texture == null:
			_other_texture = load(other_bubble_texture_path) as Texture2D
		return _other_texture


func apply_current_style(bubble_node: Control, role: StringName, style_override: StringName = &"") -> void:
	## 应用当前态样式（完全不透明）
	var texture: Texture2D = get_bubble_texture(role, style_override)
	_apply_texture_to_bubble(bubble_node, texture)
	bubble_node.modulate.a = 1.0


func apply_history_style(bubble_node: Control, role: StringName, style_override: StringName = &"") -> void:
	## 应用历史态样式（降低透明度）
	var texture: Texture2D = get_bubble_texture(role, style_override)
	_apply_texture_to_bubble(bubble_node, texture)
	bubble_node.modulate.a = history_opacity


func _apply_texture_to_bubble(bubble_node: Control, texture: Texture2D) -> void:
	if texture == null:
		return
	# 查找 NinePatchRect 或 TextureRect 子节点
	var bg_node: Node = bubble_node.get_node_or_null("BubbleBG")
	if bg_node == null:
		bg_node = bubble_node.get_node_or_null("Background")
	if bg_node is NinePatchRect:
		(bg_node as NinePatchRect).texture = texture
	elif bg_node is TextureRect:
		(bg_node as TextureRect).texture = texture
