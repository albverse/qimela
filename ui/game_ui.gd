extends CanvasLayer
class_name GameUI

## 游戏UI统一管理器
## 整合 HeartsUI、ChainSlotsUI、WeaponLabel

@export var hearts_ui_path: NodePath = NodePath("SafeFrame/VBox/TopRow/HeartsUI")
@export var chain_slots_ui_path: NodePath = NodePath("SafeFrame/VBox/ChainSlotsUI")
@export var weapon_label_path: NodePath = NodePath("SafeFrame/VBox/TopRow/WeaponLabel")

var _hearts_ui: Control = null
var _chain_slots_ui: Control = null
var _weapon_label: Label = null
var _player: Player = null


func _ready() -> void:
	# 获取子UI组件引用
	_hearts_ui = get_node_or_null(hearts_ui_path)
	_chain_slots_ui = get_node_or_null(chain_slots_ui_path)
	_weapon_label = get_node_or_null(weapon_label_path) as Label
	
	# 延迟初始化，等待Player加载
	call_deferred("_init_with_player")


func _init_with_player() -> void:
	_find_player()
	if _player == null:
		push_warning("[GameUI] Player not found")
		return
	
	# 初始化HeartsUI
	if _hearts_ui != null and _hearts_ui.has_method("setup"):
		var max_hp: int = 5
		var current_hp: int = 5
		
		if _player.health != null:
			max_hp = _player.health.max_hp
			current_hp = _player.health.hp
		
		_hearts_ui.call("setup", max_hp, current_hp)
		
		# 连接血量变化信号（受伤/治疗都更新）
		if _player.health != null and _player.health.has_signal("hp_changed"):
			_player.health.hp_changed.connect(_on_player_hp_changed)
		elif _player.health != null and _player.health.has_signal("damage_applied"):
			_player.health.damage_applied.connect(_on_player_damage_applied)
	
	# 初始化武器显示
	_update_weapon_label()


func _find_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Player


func _process(_delta: float) -> void:
	# 每帧更新武器显示
	_update_weapon_label()


func _update_weapon_label() -> void:
	if _weapon_label == null:
		return
	
	if _player == null:
		_find_player()
		if _player == null:
			_weapon_label.text = "Weapon: ?"
			return
	
	if _player.weapon_controller == null:
		_weapon_label.text = "Weapon: ?"
		return
	
	var weapon_name: String = _player.weapon_controller.get_weapon_name()
	_weapon_label.text = "Weapon: %s" % weapon_name


func _on_player_damage_applied(_amount: int, _source_pos: Vector2) -> void:
	# 更新血量显示
	if _hearts_ui != null and _hearts_ui.has_method("set_hp_instant") and _player != null and _player.health != null:
		_hearts_ui.call("set_hp_instant", _player.health.hp)


func _on_player_hp_changed(new_hp: int, old_hp: int) -> void:
	if _hearts_ui == null or not _hearts_ui.has_method("set_hp_instant"):
		return
	if new_hp > old_hp and _hearts_ui.has_method("play_heal_fill"):
		_hearts_ui.call("play_heal_fill", old_hp, new_hp)
		return
	_hearts_ui.call("set_hp_instant", new_hp)
