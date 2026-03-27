class_name ItemDropHelper
extends Node

## 道具掉落管理器（Autoload 单例）
## 完全解耦：不修改任何怪物脚本，通过 tree_exiting 信号监听怪物死亡。
## 新怪物只需在 _drop_table 中注册 species_id → 掉落表 即可。

# ── 掉落表注册 ──
# key: species_id (StringName), value: { "items": Array[String], "chance": float }
var _drop_table: Dictionary = {}

# ── 已监听的实体集合（防重复连接） ──
var _watched: Dictionary = {}


func _ready() -> void:
	# 注册默认掉落表
	register_drop_table(&"chimera_nun_snake", [
		"res://inventory/items/heal_potion_small.tres",
		"res://inventory/items/heal_potion_large.tres",
		"res://inventory/items/healing_sprite_bottle.tres",
	], 1.0)

	register_drop_table(&"wandering_ghost", [
		"res://inventory/items/heal_potion_small.tres",
		"res://inventory/items/key_old_medallion.tres",
	], 1.0, true)  # 仅玩家击杀时掉落


var _scan_timer: float = 0.0
const SCAN_INTERVAL: float = 0.5  # 每 0.5 秒扫描一次（非每帧）

func _process(dt: float) -> void:
	_scan_timer += dt
	if _scan_timer < SCAN_INTERVAL:
		return
	_scan_timer = 0.0
	# 定期扫描场景中的新怪物并挂载监听
	_scan_group("monster")
	_scan_group("ghost")


func register_drop_table(species_id: StringName, item_paths: Array, chance: float = 1.0, player_kill_only: bool = false) -> void:
	## player_kill_only: 仅玩家击杀时掉落（如 WanderingGhost 被噬魂犬吃不掉落）
	_drop_table[species_id] = { "items": item_paths, "chance": chance, "player_kill_only": player_kill_only }


func _scan_group(group_name: String) -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		var node_id: int = node.get_instance_id()
		if _watched.has(node_id):
			continue
		# 检查是否有 species_id 属性
		if not ("species_id" in node):
			continue
		var sid: StringName = node.species_id as StringName
		if not _drop_table.has(sid):
			continue
		# 连接 tree_exiting 信号
		node.tree_exiting.connect(_on_entity_dying.bind(node, sid))
		_watched[node_id] = true


func _on_entity_dying(entity: Node, species_id: StringName) -> void:
	if entity == null:
		return
	# 清理监听记录
	var eid: int = entity.get_instance_id()
	_watched.erase(eid)

	if not _drop_table.has(species_id):
		return

	var table: Dictionary = _drop_table[species_id] as Dictionary
	var items: Array = table["items"] as Array
	var chance: float = table["chance"] as float
	var player_kill_only: bool = table.get("player_kill_only", false) as bool

	if items.is_empty():
		return

	# 仅玩家击杀掉落检查：读取 _dying 标志（如 WanderingGhost 被噬魂犬吃时不掉）
	if player_kill_only:
		if "_dying" in entity:
			if not entity._dying:
				return
		elif "_being_hunted" in entity:
			if entity._being_hunted:
				return

	if randf() > chance:
		return

	# 获取实体位置
	var pos: Vector2 = Vector2.ZERO
	if entity is Node2D:
		pos = (entity as Node2D).global_position

	# 随机选择道具
	var idx: int = randi() % items.size()
	var item_path: String = items[idx] as String
	var item_res: ItemData = load(item_path) as ItemData
	if item_res == null:
		push_warning("[ItemDropHelper] Failed to load: %s" % item_path)
		return

	# 延迟 spawn（entity 正在被删除）
	call_deferred("_spawn_world_item", item_res, pos)


func _spawn_world_item(item: ItemData, pos: Vector2) -> void:
	var world_item: WorldItem = WorldItem.new()
	world_item.global_position = pos + Vector2(0, -10)
	world_item.setup(item, 1)

	var root: Node = get_tree().current_scene
	if root != null:
		root.add_child(world_item)
		print("[ItemDropHelper] Dropped '%s' at %s" % [item.display_name, str(pos)])
