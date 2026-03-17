## 召唤幽灵拔河拉玩家到近身 → 镰刀斩检测区 → 吸力停 → 镰刀斩
## GhostTug 生成在Boss身后（背靠魔女石像），面朝玩家方向
## 可被 ghostfist 打断
extends ActionLeaf
class_name ActGhostTug

enum Step { CAST, PULLING, SCYTHE_SLASH, DONE }
var _step: int = Step.CAST
var _tug_instance: Node2D = null

## 镰刀攻击范围（像素），用距离判定代替 Area2D.monitoring
@export var scythe_reach_px: float = 100.0

func before_run(actor: Node, _bb: Blackboard) -> void:
	_step = Step.CAST

func tick(actor: Node, blackboard: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0

	match _step:
		Step.CAST:
			boss.anim_play(&"phase2/ghost_tug_cast", false)
			var player := boss.get_priority_attack_target()
			if player == null:
				return FAILURE
			_tug_instance = boss._ghost_tug_scene.instantiate()
			_tug_instance.add_to_group("ghost_tug")
			if _tug_instance.has_method("setup"):
				_tug_instance.call("setup", player, boss, boss.ghost_tug_pull_speed)
			# 生成在 Boss 身后（远离玩家方向偏移 40px），背靠魔女石像
			var dir_to_player: float = signf(player.global_position.x - boss.global_position.x)
			var spawn_offset_x: float = -dir_to_player * 40.0  # Boss 身后
			_tug_instance.global_position = Vector2(
				boss.global_position.x + spawn_offset_x,
				boss.global_position.y
			)
			boss.get_parent().add_child(_tug_instance)
			print("[ACT_GHOST_TUG_DEBUG] spawned tug at %s (boss=%s, player=%s)" % [_tug_instance.global_position, boss.global_position, player.global_position])
			_step = Step.PULLING
			return RUNNING
		Step.PULLING:
			boss.anim_play(&"phase2/ghost_tug_loop", true)
			# 检查拔河是否被打断（ghostfist 击中）
			if _tug_instance == null or not is_instance_valid(_tug_instance):
				_set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
				return SUCCESS
			# 用水平距离判定玩家是否到达镰刀范围
			var player := boss.get_priority_attack_target()
			if player != null:
				var h_dist := absf(player.global_position.x - boss.global_position.x)
				if h_dist <= scythe_reach_px:
					_destroy_tug()
					_step = Step.SCYTHE_SLASH
			return RUNNING
		Step.SCYTHE_SLASH:
			boss.anim_play(&"phase2/scythe_slash", false)
			if boss.anim_is_finished(&"phase2/scythe_slash"):
				_set_cooldown(actor, blackboard, "cd_tug", boss.ghost_tug_cooldown)
				_set_cooldown(actor, blackboard, "cd_scythe", boss.scythe_slash_cooldown)
				return SUCCESS
			return RUNNING
	return FAILURE

func _destroy_tug() -> void:
	if _tug_instance != null and is_instance_valid(_tug_instance):
		_tug_instance.queue_free()
		_tug_instance = null

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	_destroy_tug()
	_step = Step.CAST
	super(actor, blackboard)
