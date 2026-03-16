## 在玩家位置召唤地狱之手 → 0.5s 逃跑窗口 → 未逃则僵直3秒
extends ActionLeaf
class_name ActCastImprison

enum Step { CAST_ANIM, WAIT_CAST, MONITOR, DONE }
var _step: int = Step.CAST_ANIM

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST_ANIM

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE

	match _step:
		Step.CAST_ANIM:
			boss.anim_play(&"phase3/imprison", false)
			_step = Step.WAIT_CAST
			return RUNNING
		Step.WAIT_CAST:
			if boss.anim_is_finished(&"phase3/imprison"):
				_spawn_hell_hand(boss)
				_step = Step.MONITOR
			return RUNNING
		Step.MONITOR:
			if boss._hell_hand_instance == null or not is_instance_valid(boss._hell_hand_instance):
				_set_cooldown(actor, blackboard, "cd_imprison", boss.p3_imprison_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _spawn_hell_hand(boss: BossGhostWitch) -> void:
	var player := boss.get_priority_attack_target()
	if player == null:
		return
	var hand: Node2D = boss._hell_hand_scene.instantiate()
	hand.add_to_group("hell_hand")
	if hand.has_method("setup"):
		hand.call("setup", player, boss, boss.p3_imprison_escape_time, boss.p3_imprison_stun_time)
	hand.global_position = player.global_position
	boss.get_parent().add_child(hand)
	boss._hell_hand_instance = hand

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_step = Step.CAST_ANIM
	super(actor, blackboard)
