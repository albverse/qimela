extends ActionLeaf
class_name ActSoulDevourerMoveToPartner

## =============================================================================
## act_move_to_partner — 合体移动（向 partner 靠拢）（P3）
## =============================================================================
## 到达接触距离后：记录 HP，双方 queue_free，中点生成 TwoHeadedSoulDevourer。
## =============================================================================

const TWO_HEADED_SCENE_PATH: String = "res://scene/enemies/soul_devourer/two_headed_soul_devourer/TwoHeadedSoulDevourer.tscn"
const MERGE_CONTACT_DIST: float = 20.0

var _two_headed_scene: PackedScene = null


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	if _two_headed_scene == null and ResourceLoader.exists(TWO_HEADED_SCENE_PATH):
		_two_headed_scene = load(TWO_HEADED_SCENE_PATH) as PackedScene
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	sd.anim_play(&"normal/float_move", true)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	if not sd._merging:
		return SUCCESS

	var partner: SoulDevourer = sd._get_merge_partner()
	if partner == null:
		sd._merging = false
		return FAILURE

	var dir: Vector2 = (partner.global_position - sd.global_position)
	var dist: float = dir.length()

	if dist <= MERGE_CONTACT_DIST:
		# 合体！
		_do_merge(sd, partner)
		return SUCCESS

	sd.velocity = dir.normalized() * sd.merge_move_speed
	# move_and_slide 由 _physics_process 统一调用
	return RUNNING


func _do_merge(sd: SoulDevourer, partner: SoulDevourer) -> void:
	var mid_pos: Vector2 = (sd.global_position + partner.global_position) * 0.5
	var combined_hp: int = sd.hp + partner.hp

	# 双方退出
	sd._merging = false
	partner._merging = false

	# 生成双头犬
	if _two_headed_scene != null:
		var scene_parent: Node = sd.get_parent()
		var two_headed: Node2D = (_two_headed_scene as PackedScene).instantiate() as Node2D
		if two_headed != null:
			two_headed.global_position = mid_pos
			if two_headed.has_method("init_from_merge"):
				two_headed.call("init_from_merge", combined_hp, sd, partner)
			scene_parent.add_child(two_headed)

	# 双方隐藏（让双头犬控制分离后恢复）
	sd.visible = false
	partner.visible = false
	sd._death_rebirth_started = true  # 防止接受新命中
	partner._death_rebirth_started = true


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd._merging = false
		sd.velocity = Vector2.ZERO
	super(actor, blackboard)
