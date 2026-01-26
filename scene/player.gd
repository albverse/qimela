class_name Player
extends CharacterBody2D

# =========================
# 节点路径（按你当前节点树默认）
# =========================
@export var visual_path: NodePath = ^"Visual"                 # 角色视觉节点（用于翻转）
@export var hand_l_path: NodePath = ^"Visual/HandL"           # 左手发射点
@export var hand_r_path: NodePath = ^"Visual/HandR"           # 右手发射点
@export var chain_line0_path: NodePath = ^"Chains/ChainLine0" # 锁链0的Line2D
@export var chain_line1_path: NodePath = ^"Chains/ChainLine1" # 锁链1的Line2D

@onready var movement = $Components/Movement
@onready var chain: PlayerChainSystem = $Components/ChainSystem as PlayerChainSystem
@onready var health: PlayerHealth = $Components/Health

# =========================
# Healing 精灵中心点（你会在Player场景创建 center1/2/3）
# =========================
@export var orbit_center1_path: NodePath = ^"Visual/center1"
@export var orbit_center2_path: NodePath = ^"Visual/center2"
@export var orbit_center3_path: NodePath = ^"Visual/center3"

@onready var orbit_center1: Marker2D = get_node_or_null(orbit_center1_path) as Marker2D
@onready var orbit_center2: Marker2D = get_node_or_null(orbit_center2_path) as Marker2D
@onready var orbit_center3: Marker2D = get_node_or_null(orbit_center3_path) as Marker2D

# 使用按键：优先 InputMap action（use_healing），否则回退 C
@export var action_use_healing: StringName = &"use_healing"  # C键（推荐在InputMap里也建同名action）

# =========================
# Healing 槽位（3只）
# =========================
const MAX_HEALING_SPRITES: int = 3
var healing_slots: Array[HealingSprite] = [null, null, null]

# =========================
# 融合 / 生成
# =========================
@export var action_fuse: StringName = &"fuse"                    # 空格：融合（可选InputMap）
@export var action_cancel_chains: StringName = &"cancel_chains"  # X：强制消失锁链
@export var fusion_lock_time: float = 0.5                        # 融合演出期间锁玩家
@export var fusion_chain_dissolve_time: float = 0.5              # 融合时两条链溶解用时（更快）
@export var chimera_scene: PackedScene                           # 指向 ChimeraA.tscn

# =========================
# 角色移动参数
# =========================
@export var move_speed: float = 260.0
@export var jump_speed: float = 520.0
@export var gravity: float = 1500.0
@export var facing_visual_sign: float = 1.0

# =========================
# 输入映射名（有就用，没有就读按键）
# 你要求：W跳跃（不再空格）
# =========================
@export var action_left: StringName = &"move_left"   # A
@export var action_right: StringName = &"move_right" # D
@export var action_jump: StringName = &"jump"        # W

# =========================
# 锁链行为参数
# =========================
@export var chain_speed: float = 1200.0
@export var chain_max_length: float = 550.0
@export var chain_max_fly_time: float = 0.2
@export var hold_time: float = 0.3
@export var burn_time: float = 0.5
@export var cancel_dissolve_time: float = 0.3
const DEFAULT_CHAIN_SHADER_PATH: String = "res://shaders/chain_sand_dissolve.gdshader"
@export var chain_shader_path: String = DEFAULT_CHAIN_SHADER_PATH
@export_flags_2d_physics var chain_hit_mask: int = 0xFFFFFFFF
@export_flags_2d_physics var chain_interact_mask: int = 0

# =========================
# Rope视觉（Verlet + 波动叠加）
# =========================
@export var rope_segments: int = 22
@export var rope_damping: float = 0.88
@export var rope_stiffness: float = 1.7
@export var rope_iterations: int = 13
@export var rope_gravity: float = 0.0

# =========================
# “自然抖动”参数
# =========================
@export var rope_wave_amp: float = 44.0
@export var rope_wave_freq: float = 10.0
@export var rope_wave_decay: float = 7.5
@export var rope_wave_hook_power: float = 2.2
@export var rope_wave_along_segments: float = 8.0
@export var end_motion_inject: float = 0.5
@export var hand_motion_inject: float = 0.15

# =========================
# 断裂预警：越接近最大长度越红
# =========================
@export var warn_start_ratio: float = 0.80
@export var warn_gamma: float = 1.6
@export var warn_color: Color = Color(1.0, 0.259, 0.475, 1.0)

# =========================
# 材质展开端点控制
# true：UV从钩子端开始 -> 缩进/展开只发生在手端（自然）
# =========================
@export var texture_anchor_at_hook: bool = true

# =========================
# Chimera 安全生成（A+B）
# =========================
@export var spawn_try_up_step: float = 16.0
@export var spawn_try_up_count: int = 10
@export var spawn_try_side: float = 24.0
@export var spawn_disable_collision_one_frame: bool = true

# -------------------------
# 薄壳运行时状态
# -------------------------
var facing: int = 1
var _player_locked: bool = false


func _ready() -> void:
	add_to_group("player")

	if chain == null:
		push_error("[Player] Components/ChainSystem missing or not PlayerChainSystem.")
		set_physics_process(false)
		set_process(false)
		return

	# 避免“外部类成员解析”问题：用 call
	if health != null and health.has_method("setup"):
		health.call("setup", self)


func is_player_locked() -> bool:
	return _player_locked


func set_player_locked(v: bool) -> void:
	_player_locked = v


func _physics_process(dt: float) -> void:
	# 1) 移动组件写 velocity
	movement.tick(dt)

	# 生命/无敌/击退等
	if health != null:
		health.tick(dt)

	# 2) 角色本体运动
	move_and_slide()

	# 3) 锁链组件更新（rope/溶解/融合等）
	chain.tick(dt)


# 给 Movement 用：水平输入是否锁定（击退锁水平；核心锁定仍然生效）
func is_horizontal_input_locked() -> bool:
	if is_player_locked():
		return true
	return health != null and health.is_knockback_active()


# 需求接口（文档要求）
func apply_damage(amount: int, source_global_pos: Vector2) -> void:
	if health != null:
		health.apply_damage(amount, source_global_pos)


func _unhandled_input(event: InputEvent) -> void:
	# 原有的锁链逻辑
	if chain != null:
		chain.handle_unhandled_input(event)

	# 使用回血精灵：优先 action，否则回退 C
	var action_name := String(action_use_healing)
	if InputMap.has_action(action_name):
		if event.is_action_pressed(action_use_healing):
			use_healing_sprite()
	else:
		if event is InputEventKey:
			var ek := event as InputEventKey
			if ek.pressed and ek.keycode == KEY_C:
				use_healing_sprite()


# 给 HealingSprite 调用：按槽位返回不同中心点（center1/2/3）
func get_healing_orbit_center_global(slot_index: int) -> Vector2:
	match slot_index:
		0:
			if orbit_center1 != null:
				return orbit_center1.global_position
		1:
			if orbit_center2 != null:
				return orbit_center2.global_position
		2:
			if orbit_center3 != null:
				return orbit_center3.global_position
	return global_position


# 尝试收集精灵（返回槽位 0..2，-1 表示已满）
# preferred_slot 来自链 slot（通常 0/1）；第三只会自动落到空槽
func try_collect_healing_sprite(sprite: HealingSprite, preferred_slot: int = -1) -> int:
	# 已经收集过：直接返回原槽位
	for i in range(MAX_HEALING_SPRITES):
		if healing_slots[i] == sprite:
			return i

	# 链 slot 通常只有 0/1：优先占对应槽（center1/center2）
	if preferred_slot >= 0 and preferred_slot < 2:
		if healing_slots[preferred_slot] == null:
			healing_slots[preferred_slot] = sprite
			return preferred_slot

	# 其余情况：找第一个空槽（包括第三槽位）
	for i in range(MAX_HEALING_SPRITES):
		if healing_slots[i] == null:
			healing_slots[i] = sprite
			return i

	return -1


# 使用回血精灵（优先消耗后槽位：2 -> 1 -> 0）
func use_healing_sprite() -> void:
	var idx: int = -1
	for i in range(MAX_HEALING_SPRITES - 1, -1, -1):
		if healing_slots[i] != null and is_instance_valid(healing_slots[i]):
			idx = i
			break
	if idx < 0:
		return

	var s: HealingSprite = healing_slots[idx]
	healing_slots[idx] = null

	heal(2) # 2颗心/只（整数）
	if s != null and is_instance_valid(s):
		s.consume()


# 精灵被销毁时清理引用
func remove_healing_sprite(sprite: Node2D) -> void:
	for i in range(MAX_HEALING_SPRITES):
		if healing_slots[i] == sprite:
			healing_slots[i] = null


func heal(amount: int) -> void:
	if health != null:
		health.heal(amount)


# 给 MonsterBase 用的对外接口：保持不变
func force_dissolve_chain(slot: int) -> void:
	if chain != null:
		chain.force_dissolve_chain(slot)


func force_dissolve_all_chains() -> void:
	if chain != null:
		chain.force_dissolve_all_chains()
