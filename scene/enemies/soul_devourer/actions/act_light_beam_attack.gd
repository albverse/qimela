extends ActionLeaf
class_name ActSoulDevourerLightBeamAttack

## =============================================================================
## act_light_beam_attack — 光炮攻击（P8，full 状态）
## =============================================================================
## 播放 normal/light_beam → atk_hit_on/off 事件驱动判定
## → animation_completed → _is_full = false → 进入 CD
## =============================================================================

const COOLDOWN_KEY: StringName = &"sd_light_beam_cd_end"


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	print("[SD:P8] before_run: LIGHT BEAM, full=%s" % sd._is_full)
	sd.velocity.x = 0.0
	# 面向玩家（统一使用 _spine_sprite 翻转，不翻转 CharacterBody2D）
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		sd.face_toward_position(player.global_position.x)
	sd.anim_play(&"normal/light_beam", false)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	if sd.anim_is_finished(&"normal/light_beam"):
		sd._is_full = false
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY, SoulDevourer.now_sec() + sd.skill_cooldown_light_beam, actor_id)
		# 关闭 hitbox（事件驱动已关闭，保险起见再次关闭）
		sd._set_light_beam_hitbox_enabled(false)
		return SUCCESS

	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		sd._set_light_beam_hitbox_enabled(false)
		sd.velocity.x = 0.0
	super(actor, blackboard)
