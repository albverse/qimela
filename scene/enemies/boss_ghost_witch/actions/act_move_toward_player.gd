## Phase 2 移动兜底
## 定期返回 SUCCESS 让非响应式 Selector 重新评估技能条件
extends ActionLeaf
class_name ActMoveTowardPlayer

@export var move_speed: float = 80.0
## 每隔多少秒返回一次 SUCCESS，让 Selector 重新从头评估技能
@export var reeval_interval: float = 0.3

var _reeval_timer: float = 0.0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_reeval_timer = 0.0

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	var dt := get_physics_process_delta_time()
	var player := boss.get_priority_attack_target()
	if player == null:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase2/idle", true)
		return RUNNING

	var h_dist: float = absf(player.global_position.x - actor.global_position.x)
	if h_dist < 30.0:
		actor.velocity.x = 0.0
		boss.anim_play(&"phase2/idle", true)
	else:
		var dir := signf(player.global_position.x - actor.global_position.x)
		actor.velocity.x = dir * move_speed
		boss.face_toward(player)
		boss.anim_play(&"phase2/walk", true)

	# 定期返回 SUCCESS 让 Selector 从头评估技能
	_reeval_timer += dt
	if _reeval_timer >= reeval_interval:
		_reeval_timer = 0.0
		actor.velocity.x = 0.0
		return SUCCESS
	return RUNNING

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	if actor != null:
		actor.velocity.x = 0.0
	super(actor, blackboard)
