extends RefCounted
class_name BubbleStyleController

## 气泡样式控制器
## 职责：根据 role / style_id / material_key / history state 应用样式资源
## 支持通过注册表注册多种气泡纹理和材质，由 dialogue tags 动态切换
## 不决定气泡何时迁移，不解析对话标签

const LOG_PREFIX: String = "[BubbleStyle]"
var debug_log: bool = false

## ── 纹理注册表 ──
## key → Texture2D 或 String（路径，首次使用时 load）
## 预置 key："default_player"、"default_other"
## 使用方通过 register_texture() 注册额外样式（如 "explosion"、"thinking"）
var _texture_registry: Dictionary = {}

## ── 材质注册表 ──
## key → Material 或 String（路径，首次使用时 load）
## 使用方通过 register_material() 注册气泡 shader（如 "explosion"、"thinking"）
var _material_registry: Dictionary = {}

## 历史态透明度
var history_opacity: float = 0.5


func _init() -> void:
	# 注册默认纹理（使用测试资源路径，正式项目应在 configure_session 中覆盖）
	_texture_registry["default_player"] = "res://dialogue_test/dialogic_art/dialogic_text_player.png"
	_texture_registry["default_other"] = "res://dialogue_test/dialogic_art/dialogic_text_character.png"


## ── 注册 API ──

func register_texture(style_id: String, texture_or_path: Variant) -> void:
	## 注册气泡纹理。texture_or_path 可为 Texture2D 实例或资源路径字符串
	_texture_registry[style_id] = texture_or_path
	if debug_log:
		print("%s Registered texture: %s" % [LOG_PREFIX, style_id])


func register_material(material_key: String, material_or_path: Variant) -> void:
	## 注册气泡材质。material_or_path 可为 Material 实例或资源路径字符串
	_material_registry[material_key] = material_or_path
	if debug_log:
		print("%s Registered material: %s" % [LOG_PREFIX, material_key])


func set_default_player_texture(path: String) -> void:
	_texture_registry["default_player"] = path


func set_default_other_texture(path: String) -> void:
	_texture_registry["default_other"] = path


## ── 查询 API ──

func get_bubble_texture(role: StringName, style_override: StringName = &"") -> Texture2D:
	## style_override 优先，其次按 role 返回默认纹理
	if style_override != &"":
		var override_key: String = str(style_override)
		if _texture_registry.has(override_key):
			return _resolve_texture(override_key)
		if debug_log:
			print("%s Style override '%s' not found in registry, falling back to role default" % [
				LOG_PREFIX, override_key
			])

	if role == &"player":
		return _resolve_texture("default_player")
	return _resolve_texture("default_other")


func get_bubble_material(material_key: StringName) -> Material:
	## 按 material_key 查找已注册的材质，未找到返回 null
	if material_key == &"":
		return null
	var key: String = str(material_key)
	if not _material_registry.has(key):
		if debug_log:
			print("%s Material key '%s' not found in registry" % [LOG_PREFIX, key])
		return null
	return _resolve_material(key)


## ── 应用 API ──

func apply_style_to_bubble(bubble_node: Control, role: StringName, style_override: StringName = &"", material_key: StringName = &"") -> void:
	## 应用完整样式（纹理 + 材质）到气泡
	var texture: Texture2D = get_bubble_texture(role, style_override)
	_apply_texture_to_bubble(bubble_node, texture)
	var mat: Material = get_bubble_material(material_key)
	_apply_material_to_bubble(bubble_node, mat)
	bubble_node.modulate.a = 1.0


func apply_history_style(bubble_node: Control, role: StringName, style_override: StringName = &"") -> void:
	## 应用历史态样式（降低透明度，保留当前纹理/材质）
	bubble_node.modulate.a = history_opacity


## ── 内部实现 ──

func _resolve_texture(key: String) -> Texture2D:
	if not _texture_registry.has(key):
		return null
	var entry: Variant = _texture_registry[key]
	if entry is Texture2D:
		return entry as Texture2D
	if entry is String:
		var loaded: Texture2D = load(entry) as Texture2D
		if loaded != null:
			_texture_registry[key] = loaded
		return loaded
	return null


func _resolve_material(key: String) -> Material:
	if not _material_registry.has(key):
		return null
	var entry: Variant = _material_registry[key]
	if entry is Material:
		return entry as Material
	if entry is String:
		var loaded: Material = load(entry) as Material
		if loaded != null:
			_material_registry[key] = loaded
		return loaded
	return null


func _apply_texture_to_bubble(bubble_node: Control, texture: Texture2D) -> void:
	if texture == null:
		return
	var bg_node: Node = bubble_node.get_node_or_null("BubbleBG")
	if bg_node is NinePatchRect:
		(bg_node as NinePatchRect).texture = texture
	elif bg_node is TextureRect:
		(bg_node as TextureRect).texture = texture


func _apply_material_to_bubble(bubble_node: Control, mat: Material) -> void:
	## 将材质应用到气泡背景节点。传 null 表示清除材质
	var bg_node: Node = bubble_node.get_node_or_null("BubbleBG")
	if bg_node is CanvasItem:
		(bg_node as CanvasItem).material = mat
