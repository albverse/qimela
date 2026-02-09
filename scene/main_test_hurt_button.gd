extends Button
class_name MainTestHurtButton

@export var player_path: NodePath = ^"../../World/Player"
@export var hurt_damage: int = 1
@export var source_offset: Vector2 = Vector2(-20, 0)

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var player_node: Node = get_node_or_null(player_path)
	if player_node == null:
		push_warning("[MainTestHurtButton] Player not found: %s" % player_path)
		return
	if not player_node.has_method("apply_damage"):
		push_warning("[MainTestHurtButton] Player has no apply_damage()")
		return
	var src: Vector2 = Vector2.ZERO
	if player_node is Node2D:
		src = (player_node as Node2D).global_position + source_offset
	player_node.call("apply_damage", hurt_damage, src)
