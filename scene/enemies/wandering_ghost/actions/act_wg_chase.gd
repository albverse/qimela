extends ActionLeaf
class_name ActWGChase

## 追击玩家（FIX-V4-02：首次发现才触发 1 秒延迟）。

enum Phase { DELAY, CHASING }

var _chase_phase: int = Phase.DELAY
var _delay_timer: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return
	if ghost._has_started_chase_once:
		_chase_phase = Phase.CHASING
	else:
		_chase_phase = Phase.DELAY
		_delay_timer = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE

	var dt: float = ghost.get_physics_process_delta_time()

	match _chase_phase:
		Phase.DELAY:
			ghost.velocity = Vector2.ZERO
			ghost._play_anim(&"idle", true)
			_delay_timer += dt
			if _delay_timer >= ghost.chase_delay:
				ghost._has_started_chase_once = true
				_chase_phase = Phase.CHASING
			return RUNNING
		Phase.CHASING:
			var player: Node2D = ghost.get_player_node()
			if player == null:
				ghost.velocity = Vector2.ZERO
				ghost._play_anim(&"idle", true)
				return RUNNING
			var dx: float = player.global_position.x - ghost.global_position.x
			if absf(dx) <= ghost.FACE_DEAD_ZONE:
				# 已到达玩家附近，停止水平移动，保持当前朝向
				ghost.velocity = Vector2.ZERO
				ghost._play_anim(&"idle", true)
				return RUNNING
			var dir: float = signf(dx)
			ghost.velocity.x = dir * ghost.move_speed
			ghost.face_toward(player)
			ghost._play_anim(&"move", true)
			ghost.move_and_slide()
			return RUNNING
	return RUNNING


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost != null:
		ghost.velocity = Vector2.ZERO
	# 不重置 _has_started_chase_once（玩家离开后由 act_idle 重置）
	super(actor, blackboard)
