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
@onready var chain = $Components/ChainSystem
@onready var health: PlayerHealth = $Components/Health
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
@export var burn_time: float = 1.0
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

@onready var _movement: Node = $Components/Movement
@onready var _chain: Node = $Components/ChainSystem

func _ready() -> void:
	if health != null:
		health.setup(self)

func is_player_locked() -> bool:
	return _player_locked

func set_player_locked(v: bool) -> void:
	_player_locked = v

func _physics_process(dt: float) -> void:
	# 1) 移动组件写 velocity
	movement.tick(dt)
	if health != null:
		health.tick(dt)

	# 2) 角色本体运动
	move_and_slide()

	# 3) 锁链组件更新（rope/溶解/融合等）
	chain.tick(dt)
	
# 给Movement用：水平输入是否锁定（击退锁水平；核心锁定仍然生效）
func is_horizontal_input_locked() -> bool:
	if is_player_locked():
		return true
	return health != null and health.is_knockback_active()
# 需求接口（文档要求）
func apply_damage(amount: int, source_global_pos: Vector2) -> void: # :contentReference[oaicite:5]{index=5}
	if health != null:
		health.apply_damage(amount, source_global_pos)
			
func _unhandled_input(event: InputEvent) -> void:
	_chain.call("handle_unhandled_input", event)
func heal(amount: int) -> void: # :contentReference[oaicite:6]{index=6}
	if health != null:
		health.heal(amount)
		
# 给 MonsterBase 用的对外接口：保持不变
func force_dissolve_chain(slot: int) -> void:
	_chain.call("force_dissolve_chain", slot)

func force_dissolve_all_chains() -> void:
	_chain.call("force_dissolve_all_chains")
