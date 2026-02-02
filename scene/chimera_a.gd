extends ChimeraBase
class_name ChimeraA

# ChimeraA 特定属性已移至 ChimeraBase，这里只保留特例

func _ready() -> void:
	# 设置species_id
	species_id = &"chimera_a"
	attribute_type = AttributeType.NORMAL
	size_tier = SizeTier.MEDIUM
	
	# 设置图标
	if ui_icon == null:
		ui_icon = preload("res://yaoshi.png")
	
	super._ready()

# ===== 互动效果 =====
func on_player_interact(p: Player) -> void:
	if p.has_method("heal"):
		p.call("heal", 1)
	print("[ChimeraA] 玩家互动：回复1心")
