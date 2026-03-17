extends Node2D

signal phase3_gate_triggered

@onready var _btn_phase3: Button = $UI/BtnPhase3

func _ready() -> void:
	_btn_phase3.pressed.connect(_on_btn_phase3_pressed)
	phase3_gate_triggered.connect(_on_phase3_gate_triggered)


func _on_btn_phase3_pressed() -> void:
	phase3_gate_triggered.emit()


func _on_phase3_gate_triggered() -> void:
	var bosses: Array[Node] = get_tree().get_nodes_in_group("boss_ghost_witch")
	for boss: Node in bosses:
		if boss.has_method("trigger_phase3_transition"):
			boss.trigger_phase3_transition()
