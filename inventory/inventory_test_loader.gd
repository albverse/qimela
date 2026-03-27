class_name InventoryTestLoader
extends Node

## 调试用：游戏启动时自动给背包填入测试道具
## 挂到 MainTest 场景树中（或在 player.gd 中手动调用）
## 发布时删除此节点即可

@export var auto_load_on_ready: bool = true


func _ready() -> void:
	if auto_load_on_ready:
		call_deferred("_load_test_items")


func _load_test_items() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_warning("[InventoryTestLoader] No player found")
		return

	var player: Player = players[0] as Player
	if player == null or player.inventory == null:
		push_warning("[InventoryTestLoader] Player has no inventory")
		return

	var inv: PlayerInventory = player.inventory

	# 加载测试道具资源
	var heal_small: ItemData = load("res://inventory/items/heal_potion_small.tres") as ItemData
	var heal_large: ItemData = load("res://inventory/items/heal_potion_large.tres") as ItemData
	var sprite_bottle: ItemData = load("res://inventory/items/healing_sprite_bottle.tres") as ItemData
	var medallion: ItemData = load("res://inventory/items/key_old_medallion.tres") as ItemData

	# 填入背包
	if heal_small != null:
		inv.add_item(heal_small, 3)
		print("[InventoryTestLoader] Added: %s x3" % heal_small.display_name)
	if heal_large != null:
		inv.add_item(heal_large, 2)
		print("[InventoryTestLoader] Added: %s x2" % heal_large.display_name)
	if sprite_bottle != null:
		inv.add_item(sprite_bottle, 2)
		print("[InventoryTestLoader] Added: %s x2" % sprite_bottle.display_name)
	if medallion != null:
		inv.add_item(medallion)
		print("[InventoryTestLoader] Added: %s" % medallion.display_name)

	print("[InventoryTestLoader] Test items loaded. Total slots used: %d/%d" % [
		inv.get_item_count(), PlayerInventory.MAIN_CAPACITY])
