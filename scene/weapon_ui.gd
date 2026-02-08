extends CanvasLayer
class_name WeaponUI

## 武器UI指示器：显示当前武器名称

@export var weapon_label_path: NodePath = NodePath("WeaponLabel")
var _weapon_label: Label = null
var _player: Player = null


func _ready() -> void:
	_weapon_label = get_node_or_null(weapon_label_path) as Label
	if _weapon_label == null:
		# 如果场景中没有Label，动态创建一个
		_weapon_label = Label.new()
		_weapon_label.name = "WeaponLabel"
		add_child(_weapon_label)
		
		# 设置样式：左上角显示
		_weapon_label.position = Vector2(20, 20)
		_weapon_label.add_theme_font_size_override("font_size", 24)
		
		# 设置颜色：白色文字，黑色描边
		_weapon_label.add_theme_color_override("font_color", Color.WHITE)
		_weapon_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_weapon_label.add_theme_constant_override("outline_size", 2)
	
	# 查找Player
	_find_player()
	
	# 初始显示
	update_display()


func _find_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Player


func _process(_delta: float) -> void:
	# 每帧更新（也可以改成信号驱动）
	update_display()


func update_display() -> void:
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
