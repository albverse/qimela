extends ChimeraBase
class_name ChimeraGhostHandL

## =============================================================================
## ChimeraGhostHandL - 幽灵手奇美拉·左（Beehave 行为树驱动）
## =============================================================================
## 由 石眼虫（空壳）+ 软体虫 融合产生。
## 被链接时跟随玩家操控移动（无重力）；攻击时冻结操控，出击结束后恢复。
## 受到伤害或超出链最大长度 → vanish → 回到玩家附近 → appear → idle。
## =============================================================================

# ===== 导出参数（策划可调）=====

@export var float_speed: float = 120.0
## 链接跟随速度（px/s）

@export var chain_overdist_threshold: float = 600.0
## 超出此距离时触发重置（px）

@export var attack_hitbox_radius: float = 40.0
## 攻击检测半径（px）

@export var attack_damage: int = 1
## 攻击伤害

@export var player_side_offset: float = 80.0
## 重置后贴近玩家的水平偏移（px）

# ===== 内部状态（BT 叶节点读写）=====

## 是否受到了伤害 → 触发重置
var took_damage: bool = false

## 是否超出链距离 → 触发重置
var over_chain_limit: bool = false

## 攻击是否被请求（玩家输入层写入）
var attack_requested: bool = false

## 攻击期间冻结玩家操控输入
var control_input_frozen: bool = false

## 幽灵攻击命中检测窗口（hit_on/off 等效，供 ForceCloseHitWindows 使用）
var atk_hit_window_open: bool = false

# ===== 动画状态追踪 =====

var _current_anim: StringName = &""
var _current_anim_finished: bool = false
var _current_anim_loop: bool = false

# ===== 动画驱动 =====

var _anim_driver: AnimDriverSpine = null
var _anim_mock: AnimDriverMock = null

@onready var _spine_sprite: Node = null
@onready var _attack_area: Area2D = get_node_or_null("AttackArea")

# ===== 生命周期 =====

func _ready() -> void:
	species_id = &"chimera_ghost_hand_l"
	attribute_type = AttributeType.NORMAL
	size_tier = SizeTier.MEDIUM
	is_flying = true
	# 禁用基类默认跟随：BT 的 Act_LinkedMove 负责位移
	follow_player_when_linked = false
	super._ready()
	add_to_group("chimera_ghost_hand_l")

	# AttackArea 检测 EnemyBody(3)+hazards(6)，不含 PlayerBody 防止误伤玩家
	if _attack_area != null:
		_attack_area.collision_mask = 4 | 32  # EnemyBody(3) + hazards(6)

	_spine_sprite = get_node_or_null("SpineSprite")
	if _spine_sprite and _spine_sprite.get_class() == "SpineSprite":
		_anim_driver = AnimDriverSpine.new()
		add_child(_anim_driver)
		_anim_driver.setup(_spine_sprite)
		_anim_driver.anim_completed.connect(_on_anim_completed)
	else:
		_anim_mock = AnimDriverMock.new()
		_setup_mock_durations()
		add_child(_anim_mock)
		_anim_mock.anim_completed.connect(_on_anim_completed)


func _physics_process(dt: float) -> void:
	# 链距超限检测
	if is_linked() and _player != null and is_instance_valid(_player):
		var dist := global_position.distance_to(_player.global_position)
		if dist > chain_overdist_threshold:
			over_chain_limit = true

	# Mock 驱动需要手动 tick
	if _anim_mock:
		_anim_mock.tick(dt)

	# 移动和 BT 逻辑由叶节点（+ BeehaveTree tick）驱动
	# 基类 _physics_process 不调用（is_flying=true，gravity 由 BT 管理）


# =============================================================================
# 动画接口（BT 叶节点统一调用）
# =============================================================================

func anim_play(anim_name: StringName, loop: bool, _interruptible: bool = true) -> void:
	if _current_anim == anim_name and not _current_anim_finished and _current_anim_loop == loop:
		return
	_current_anim = anim_name
	_current_anim_finished = false
	_current_anim_loop = loop
	if _anim_driver:
		_anim_driver.play(0, anim_name, loop, AnimDriverSpine.PlayMode.REPLACE_TRACK)
	elif _anim_mock:
		_anim_mock.play(0, anim_name, loop)


func anim_is_playing(anim_name: StringName) -> bool:
	return _current_anim == anim_name and not _current_anim_finished


func anim_is_finished(anim_name: StringName) -> bool:
	return _current_anim == anim_name and _current_anim_finished


func _on_anim_completed(_track: int, anim_name: StringName) -> void:
	if anim_name == _current_anim:
		_current_anim_finished = true


# =============================================================================
# 伤害接口（受到任意伤害 → 触发重置）
# =============================================================================

func force_close_hit_windows() -> void:
	## 强制关闭幽灵攻击命中检测窗口（见 0.1 节）
	atk_hit_window_open = false


func on_damage_received() -> void:
	## 由攻击命中回调或 EventBus 调用，触发断链重置
	took_damage = true


# =============================================================================
# 辅助方法
# =============================================================================

func get_player_node() -> Node2D:
	if _player != null and is_instance_valid(_player):
		return _player
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


func teleport_to_player_side() -> void:
	## 重置时传送到玩家附近
	var p := get_player_node()
	if p == null:
		return
	# 检查朝向，偏移到玩家左侧（L 手在左）
	global_position = p.global_position + Vector2(-player_side_offset, -40.0)


func request_attack() -> void:
	## 玩家输入层调用：请求攻击
	attack_requested = true


func resolve_hit_on_targets() -> void:
	## 检测攻击区域内的目标并处理命中效果
	if _attack_area == null:
		return
	var bodies := _attack_area.get_overlapping_bodies()
	for body in bodies:
		if not is_instance_valid(body):
			continue
		# 命中 StoneMaskBirdFaceBullet → 反弹（不走 apply_hit）
		if body is StoneMaskBirdFaceBullet:
			body.reflect()
			continue  # 子弹处理完毕，不再走下面的 apply_hit
		# 命中带壳石眼虫（NORMAL 态）→ 触发弹翻（不走 apply_hit，弹翻本身即为伤害效果）
		if body is StoneEyeBug:
			var seb := body as StoneEyeBug
			if seb.mode == StoneEyeBug.Mode.NORMAL:
				seb.mode = StoneEyeBug.Mode.FLIPPED
				seb._flash_once()
			continue  # StoneEyeBug 统一在此处理，不再走下面的 apply_hit
		# 命中其他实体 → 普通伤害
		if body.has_method("apply_hit"):
			var hit := HitData.create(attack_damage, get_player_node(), &"chimera_ghost_hand_l")
			body.call("apply_hit", hit)


static func now_ms() -> int:
	return Time.get_ticks_msec()


# =============================================================================
# Mock 驱动时长
# =============================================================================

func _setup_mock_durations() -> void:
	_anim_mock._durations[&"idle_float"] = 1.0
	_anim_mock._durations[&"move_float"] = 0.6
	_anim_mock._durations[&"attack"] = 0.5
	_anim_mock._durations[&"vanish"] = 0.4
	_anim_mock._durations[&"appear"] = 0.4
