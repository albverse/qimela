class_name ItemRegistry
extends Node

## 物品注册表（Autoload 单例）
## 启动时扫描 res://inventory/items/ 目录，加载所有 ItemData 并缓存
## 提供 get_def(id) 查询接口，供全局使用

const ITEMS_DIR: String = "res://inventory/items/"

# key: StringName (id), value: ItemData
var _defs: Dictionary = {}


func _ready() -> void:
	_scan_directory(ITEMS_DIR)
	_run_validation()


func get_def(id: StringName) -> ItemData:
	## 根据 id 获取物品定义，未找到返回 null
	if _defs.has(id):
		return _defs[id] as ItemData
	return null


func has_def(id: StringName) -> bool:
	return _defs.has(id)


func get_all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: StringName in _defs:
		ids.append(key)
	return ids


func get_def_count() -> int:
	return _defs.size()


func _scan_directory(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_warning("[ItemRegistry] Cannot open directory: %s" % path)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var full_path: String = path + file_name
			var res: Resource = load(full_path)
			if res == null:
				push_warning("[ItemRegistry] Failed to load: %s" % full_path)
			else:
				var item: ItemData = res as ItemData
				if item == null:
					push_warning("[ItemRegistry] Not an ItemData: %s" % full_path)
				elif item.id == &"":
					push_warning("[ItemRegistry] ItemData has empty id: %s" % full_path)
				else:
					if _defs.has(item.id):
						push_warning("[ItemRegistry] Duplicate id '%s' in %s" % [item.id, full_path])
					_defs[item.id] = item
		file_name = dir.get_next()
	dir.list_dir_end()

	print("[ItemRegistry] Loaded %d item definitions from %s" % [_defs.size(), path])


func _run_validation() -> void:
	var errors: PackedStringArray = ItemValidator.validate_all(_defs)
	if errors.is_empty():
		print("[ItemRegistry] All item definitions passed validation")
	else:
		for err: String in errors:
			push_warning("[ItemRegistry] Validation: %s" % err)
		push_warning("[ItemRegistry] %d validation issue(s) found" % errors.size())
