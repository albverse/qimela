## 召唤幽灵拔河拉玩家到近身 → 镰刀斩检测区 → 吸力停 → 镰刀斩
## GhostTug 生成在玩家附近（玩家到Boss方向偏移），面朝玩家
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
			# 生成在玩家→Boss方向的前方 60px 处
			var dir_to_boss: float = signf(boss.global_position.x - player.global_position.x)
			if dir_to_boss == 0.0:
				dir_to_boss = 1.0
			_tug_instance.global_position = Vector2(
				player.global_position.x + dir_to_boss * 60.0,
				player.global_position.y
			)
			boss.get_parent().add_child(_tug_instance)
			if _tug_instance.has_method("setup"):
				_tug_instance.call("setup", player, boss, boss.ghost_tug_pull_speed)
			print("[ACT_GHOST_TUG_DEBUG] spawned tug at %s dir_to_boss=%.1f (boss=%s, player=%s)" % [_tug_instance.global_position, dir_to_boss, boss.global_position, player.global_position])
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
				if Engine.get_physics_frames() % 20 == 0:
					print("[ACT_GHOST_TUG_DEBUG] pulling_check h_dist=%.2f reach=%.2f boss_x=%.2f player_x=%.2f tug_pos=%s" % [h_dist, scythe_reach_px, boss.global_position.x, player.global_position.x, _tug_instance.global_position if _tug_instance != null else Vector2.ZERO])
				if h_dist <= scythe_reach_px:
					print("[ACT_GHOST_TUG_DEBUG] pulling_check ENTER_SCYTHE_RANGE h_dist=%.2f reach=%.2f boss=%s player=%s" % [h_dist, scythe_reach_px, boss.global_position, player.global_position])
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
		if _tug_instance.has_method("begin_despawn"):
			_tug_instance.call("begin_despawn", 0.5)
		else:
			_tug_instance.queue_free()
		_tug_instance = null

func _set_cooldown(actor: Node, bb: Blackboard, key: String, cd: float) -> void:
	bb.set_value(key, Time.get_ticks_msec() + cd * 1000.0, str(actor.get_instance_id()))

func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var boss := actor as BossGhostWitch
	var player: Node2D = null
	var h_dist: float = -1.0
	if boss != null:
		player = boss.get_priority_attack_target()
		if player != null:
			h_dist = absf(player.global_position.x - boss.global_position.x)
	print("[ACT_GHOST_TUG_DEBUG] interrupt step=%d h_dist=%.2f boss=%s player=%s tug_valid=%s" % [_step, h_dist, boss.global_position if boss != null else Vector2.ZERO, player.global_position if player != null else Vector2.ZERO, _tug_instance != null and is_instance_valid(_tug_instance)])
	_destroy_tug()
	_step = Step.CAST
	super(actor, blackboard)
