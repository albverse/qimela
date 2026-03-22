extends ActionLeaf
class_name ActWGAttack

## 攻击玩家：播放 attack 动画，由 Spine 事件驱动 hitbox 启闭。

enum Step { START, WAIT_ANIM }

var _step: int = Step.START


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_step = Step.START


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE

	match _step:
		Step.START:
			ghost.velocity = Vector2.ZERO
			var player: Node2D = ghost.get_player_node()
			if player != null:
				ghost.face_toward(player)
			ghost._play_anim(&"attack", false)
			_step = Step.WAIT_ANIM
			return RUNNING
		Step.WAIT_ANIM:
			ghost.velocity = Vector2.ZERO
			# 轮询兜底（SPINE §2.3）
			if ghost.anim_is_finished(&"attack"):
				ghost.set_attack_hitbox_active(false)
				ghost._attack_cd_t = ghost.attack_cooldown
				return SUCCESS
			return RUNNING
	return FAILURE


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost != null:
		ghost.velocity = Vector2.ZERO
		ghost.set_attack_hitbox_active(false)
	_step = Step.START
	super(actor, blackboard)
