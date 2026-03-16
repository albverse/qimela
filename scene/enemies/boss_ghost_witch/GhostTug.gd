## 幽灵拔河：生成在玩家位置，持续拉玩家靠近 Boss
## 动画流程：appear → move_loop（循环）→ hit（被 ghostfist 击中后消失）
## 拉力在 _physics_process 中每帧执行（不依赖 Spine 事件，保证可靠性）
extends MonsterBase
class_name GhostTug

@export var pull_speed: float = 400.0
var _player: Node2D = null
var _boss: Node2D = null
var _dying: bool = false
var _pulling: bool = false  # appear 完成后开始拉扯

var _spine: Node = null

func _ready() -> void:
	species_id = &"ghost_tug"
	has_hp = false
	super._ready()
	add_to_group("ghost_tug")

	_spine = get_node_or_null("SpineSprite")
	if _spine != null:
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_anim_completed_raw)
	# 播放出现动画
	_spine_play(&"appear", false)
	# 兜底：0.5 秒后强制开始拉扯（防止 appear 动画不存在/不触发完成信号）
	get_tree().create_timer(0.5).timeout.connect(_force_start_pull)


func setup(player: Node2D, boss: Node2D, pull_speed_override: float = -1.0) -> void:
	_player = player
	_boss = boss
	if pull_speed_override > 0.0:
		pull_speed = pull_speed_override


func apply_hit(hit: HitData) -> bool:
	if _dying:
		return false
	if hit == null or hit.weapon_id != &"ghost_fist":
		return false
	_dying = true
	_pulling = false
	_release_player()
	_spine_play(&"hit", false)
	# 兜底：0.5 秒后强制释放（防止 hit 动画不触发完成信号）
	get_tree().create_timer(0.5).timeout.connect(queue_free)
	return true


func _physics_process(_dt: float) -> void:
	if _dying or not _pulling:
		return
	if _player == null or _boss == null:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_boss):
		return
	# 冻结玩家输入
	if _player.has_method("set_external_control_frozen"):
		_player.call("set_external_control_frozen", true)
	# 拉向 Boss
	if "velocity" in _player:
		var dir := signf(_boss.global_position.x - _player.global_position.x)
		_player.velocity.x = dir * pull_speed


func _force_start_pull() -> void:
	if not _dying and not _pulling:
		_pulling = true
		_spine_play(&"move_loop", true)


func _on_anim_completed_raw(a1 = null, a2 = null, a3 = null) -> void:
	var anim_name := _extract_completed_anim_name(a1, a2, a3)
	if anim_name == &"appear" and not _pulling and not _dying:
		_pulling = true
		_spine_play(&"move_loop", true)
	elif anim_name == &"hit":
		queue_free()


func _release_player() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.has_method("set_external_control_frozen"):
			_player.call("set_external_control_frozen", false)


func _exit_tree() -> void:
	_release_player()


# ═══ Spine 播放 + 动画名提取 ═══

func _spine_play(anim_name: StringName, loop: bool) -> void:
	if _spine == null:
		return
	var anim_state: Object = null
	if _spine.has_method("get_animation_state"):
		anim_state = _spine.get_animation_state()
	if anim_state != null and anim_state.has_method("set_animation"):
		anim_state.set_animation(String(anim_name), loop, 0)


func _extract_completed_anim_name(a1 = null, a2 = null, a3 = null) -> StringName:
	var entry: Object = null
	for a in [a1, a2, a3]:
		if a == null:
			continue
		if a is Object and a.has_method("get_animation"):
			entry = a
			break
	if entry == null:
		return &""
	var anim: Object = null
	if entry.has_method("get_animation"):
		anim = entry.get_animation()
	if anim == null:
		return &""
	var name_str: String = ""
	if anim.has_method("get_name"):
		name_str = anim.get_name()
	elif anim.has_method("getName"):
		name_str = anim.getName()
	if name_str == "":
		return &""
	return StringName(name_str)
