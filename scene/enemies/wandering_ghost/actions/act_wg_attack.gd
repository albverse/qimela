extends ActionLeaf
class_name ActWGAttack

## 攻击玩家：播放 attack 动画，由 Spine 事件驱动 hitbox 启闭。
## 定时器兜底：若 Spine 事件未配置，代码在 0.15s~0.45s 窗口内开启 hitbox。

enum Step { START, WAIT_ANIM }

var _step: int = Step.START
var _elapsed: float = 0.0
var _hitbox_forced_on: bool = false

## 兜底窗口（秒）：Spine 事件若未触发则代码主动开关 hitbox
const FALLBACK_HIT_ON: float = 0.15
const FALLBACK_HIT_OFF: float = 0.45


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_step = Step.START
	_elapsed = 0.0
	_hitbox_forced_on = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var ghost: WanderingGhost = actor as WanderingGhost
	if ghost == null:
		return FAILURE

	var dt: float = actor.get_physics_process_delta_time()

	match _step:
		Step.START:
			ghost.velocity = Vector2.ZERO
			var player: Node2D = ghost.get_player_node()
			if player != null:
				ghost.face_toward(player)
			ghost._play_anim(&"attack", false)
			_elapsed = 0.0
			_hitbox_forced_on = false
			_step = Step.WAIT_ANIM
			return RUNNING
		Step.WAIT_ANIM:
			ghost.velocity = Vector2.ZERO
			_elapsed += dt
			# 定时器兜底：Spine 事件未触发时，代码主动控制 hitbox 窗口
			if not _hitbox_forced_on and _elapsed >= FALLBACK_HIT_ON and _elapsed < FALLBACK_HIT_OFF:
				ghost.set_attack_hitbox_active(true)
				_hitbox_forced_on = true
			elif _hitbox_forced_on and _elapsed >= FALLBACK_HIT_OFF:
				ghost.set_attack_hitbox_active(false)
				_hitbox_forced_on = false
			# 轮询兜底（SPINE §2.3）
			if ghost.anim_is_finished(&"attack"):
				ghost.set_attack_hitbox_active(false)
				_hitbox_forced_on = false
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
	_elapsed = 0.0
	_hitbox_forced_on = false
	super(actor, blackboard)
