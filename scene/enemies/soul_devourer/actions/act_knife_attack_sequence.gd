extends ActionLeaf
class_name ActSoulDevourerKnifeAttackSequence

## =============================================================================
## act_knife_attack_sequence — has_knife 冲刺攻击序列（P7）
## =============================================================================
## 冲刺×2 → has_knife/change_to_normal（Spine 事件 throw_cleaver 生成刀）
## → animation_completed → 切换 normal/，进入 CD
## 超时 knife_attack_timeout → FAILURE
## =============================================================================

const COOLDOWN_KEY: StringName = &"sd_cleaver_pickup_cd_end"
const ATK_CD_KEY: StringName = &"sd_knife_atk_cd_end"

enum Phase {
	WAIT_CD,       # 攻击间隔 CD
	DASH_ATTACK,   # 冲刺攻击
	THROW_KNIFE,   # 甩刀动画
}

var _phase: int = Phase.WAIT_CD
var _timer: float = 0.0
var _dash_count: int = 0


func before_run(actor: Node, blackboard: Blackboard) -> void:
	_timer = 0.0
	_dash_count = 0

	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return
	# 检查攻击 CD
	var actor_id: String = str(sd.get_instance_id())
	var cd_end: float = blackboard.get_value(ATK_CD_KEY, 0.0, actor_id)
	if SoulDevourer.now_sec() < cd_end:
		_phase = Phase.WAIT_CD
	else:
		_phase = Phase.DASH_ATTACK
		_start_dash(sd)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd == null:
		return FAILURE

	var dt: float = get_physics_process_delta_time()
	_timer += dt

	# 超时兜底
	if _timer >= sd.knife_attack_timeout * 2.5:
		_cleanup(sd)
		return FAILURE

	match _phase:
		Phase.WAIT_CD:
			var actor_id: String = str(sd.get_instance_id())
			var cd_end: float = blackboard.get_value(ATK_CD_KEY, 0.0, actor_id)
			if SoulDevourer.now_sec() >= cd_end:
				_phase = Phase.DASH_ATTACK
				_start_dash(sd)
			return RUNNING

		Phase.DASH_ATTACK:
			return _tick_dash(sd, dt, blackboard)

		Phase.THROW_KNIFE:
			return _tick_throw(sd, blackboard)

	return RUNNING


func _start_dash(sd: SoulDevourer) -> void:
	_timer = 0.0
	print("[SD:P7] _start_dash #%d" % (_dash_count + 1))
	sd.anim_play(&"has_knife/knife_attack_run", false)
	# 面向玩家（统一使用 _spine_sprite 翻转，不翻转 CharacterBody2D）
	var player: Node2D = sd.get_priority_attack_target()
	if player != null:
		sd.face_toward_position(player.global_position.x)


func _tick_dash(sd: SoulDevourer, dt: float, blackboard: Blackboard) -> int:
	# 冲刺移动（方向基于 SpineSprite 朝向）
	var dir: float = 1.0
	if sd._spine_sprite != null and sd._spine_sprite.scale.x != 0.0:
		dir = sign(sd._spine_sprite.scale.x)
	sd.velocity.x = dir * sd.ground_run_speed * 2.5
	# 重力由 _physics_process 统一处理，此处不再重复施加

	if sd.anim_is_finished(&"has_knife/knife_attack_run") or _timer >= sd.knife_attack_timeout:
		_dash_count += 1
		sd.velocity.x = 0.0
		if _dash_count >= 2:
			# 两次冲刺完毕 → 甩刀
			print("[SD:P7] 2 dashes done → THROW_KNIFE (change_to_normal)")
			_phase = Phase.THROW_KNIFE
			_timer = 0.0
			sd.anim_play(&"has_knife/change_to_normal", false)
		else:
			# 第一次冲刺后短暂间隔再来一次
			print("[SD:P7] dash #1 done → WAIT_CD (%.1fs)" % sd.attack_cooldown_has_knife)
			var actor_id: String = str(sd.get_instance_id())
			blackboard.set_value(ATK_CD_KEY, SoulDevourer.now_sec() + sd.attack_cooldown_has_knife, actor_id)
			_phase = Phase.WAIT_CD
	return RUNNING


func _tick_throw(sd: SoulDevourer, blackboard: Blackboard) -> int:
	# throw_cleaver 事件已在 SoulDevourer._on_spine_event_throw_cleaver 处理
	if sd.anim_is_finished(&"has_knife/change_to_normal"):
		# 甩刀完毕，切换到 normal/，进入技能 CD
		var actor_id: String = str(sd.get_instance_id())
		blackboard.set_value(COOLDOWN_KEY, SoulDevourer.now_sec() + sd.skill_cooldown_has_knife, actor_id)
		sd.anim_play(&"normal/idle", true)
		return SUCCESS
	return RUNNING


func _cleanup(sd: SoulDevourer) -> void:
	sd.velocity.x = 0.0
	if sd._has_knife:
		sd.anim_play(&"has_knife/idle", true)
	else:
		sd.anim_play(&"normal/idle", true)


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var sd: SoulDevourer = actor as SoulDevourer
	if sd != null:
		_cleanup(sd)
	super(actor, blackboard)
