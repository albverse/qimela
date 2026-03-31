## 玩家立绘皮肤解析器
## 自动从玩家小人读取当前皮肤和场景亮暗状态，组合成立绘应使用的皮肤名
## 不依赖手动配置，对话开始时主动同步
class_name PlayerPortraitSkinResolver
extends RefCounted

## 解析并返回玩家立绘应使用的皮肤名
## 规则：base_skin + "_dark" / "_bright"（当 base_skin != "Default" 时）
## 当前：base_skin 固定为 "Default"（预留接口，未来从玩家小人读取）
static func resolve(scene_tree: SceneTree) -> StringName:
	var base_skin: StringName = _read_player_skin(scene_tree)

	# 预留接口：当 base_skin 仍是 Default 时，不拼接亮暗后缀
	if base_skin == &"Default" or base_skin == &"":
		return &"type1"  # 测试期间默认使用 type1

	# 读取场景亮暗状态（通过 SceneEnvironment autoload）
	var light: SceneEnvironment.LightState = SceneEnvironment.LightState.DARK
	var env_node: Node = scene_tree.root.get_node_or_null("/root/SceneEnvironment")
	if env_node != null and env_node.has_method("get_light_state"):
		light = env_node.get_light_state()

	if light == SceneEnvironment.LightState.DARK:
		return StringName(str(base_skin) + "_dark")
	return StringName(str(base_skin) + "_bright")


## 从玩家小人读取当前皮肤名（预留接口）
static func _read_player_skin(scene_tree: SceneTree) -> StringName:
	# 通过 "player" 组找到玩家节点
	var players: Array[Node] = scene_tree.get_nodes_in_group("player")
	if players.is_empty():
		return &"Default"
	var player: Node = players[0]
	# Player 类有 current_skin 属性（已预留）
	if "current_skin" in player:
		return player.current_skin
	return &"Default"
