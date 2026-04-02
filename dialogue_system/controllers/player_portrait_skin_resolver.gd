extends RefCounted
class_name PlayerPortraitSkinResolver

## 玩家立绘皮肤解析器
## 职责：读取玩家当前 skin + 场景亮暗状态 → 输出立绘 skin id
## 不写入对话文本，不驱动气泡系统

const LOG_PREFIX: String = "[PlayerPortraitSkinResolver]"
var debug_log: bool = false

## 默认皮肤（当无法读取玩家小人时使用）
var default_skin: StringName = &"default"

## 亮暗后缀分隔符
var light_dark_separator: String = "_"

## 亮暗状态后缀映射
var light_suffix: String = ""         ## 亮状态不加后缀（或 "_bright"）
var dark_suffix: String = "_dark"


func resolve(player_node: Node, light_state: StringName) -> StringName:
	var base_skin: StringName = _read_player_skin(player_node)
	var final_skin: StringName = _combine_skin(base_skin, light_state)

	if debug_log:
		print("%s base_skin=%s, light_state=%s -> final=%s" % [
			LOG_PREFIX, base_skin, light_state, final_skin
		])

	return final_skin


func _read_player_skin(player_node: Node) -> StringName:
	if player_node == null:
		return default_skin

	# 尝试从玩家节点读取当前皮肤
	if player_node.has_method("get_current_skin"):
		var skin_name: Variant = player_node.get_current_skin()
		if skin_name is String or skin_name is StringName:
			return StringName(skin_name)

	# 尝试读取属性
	if "current_skin" in player_node:
		return StringName(str(player_node.current_skin))

	return default_skin


func _combine_skin(base_skin: StringName, light_state: StringName) -> StringName:
	var suffix: String = ""
	if light_state == &"dark":
		suffix = dark_suffix
	elif light_state == &"bright":
		suffix = light_suffix

	if suffix == "":
		return base_skin

	return StringName(str(base_skin) + suffix)
