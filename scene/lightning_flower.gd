extends Node2D
class_name LightningFlower

const ENERGY_MAX: int = 5

@export_range(0, 5, 1) var initial_energy: int = 0
@export var light_time_per_energy: float = 1.0 # 自动释放：5*1.0=5秒
@export var debug_print: bool = true

# 让锁链命中花时是否允许手动释放
@export var allow_chain_release: bool = true
# 手动释放是否必须满能量（true=必须energy==5才释放；false=energy>0就能释放，时长=energy*per）
@export var chain_release_requires_full: bool = false
@export var walk_stun_time: float = 2.0 # MonsterWalk 被花波及时的眩晕秒数（可调）
@export var sprite_path: NodePath = ^"Sprite2D"
@export var glow_path: NodePath = ^"Glow"                 # PointLight2D，可选
@export var self_area_path: NodePath = ^"SelfArea"         # Area2D：被照判定点
@export var light_area_path: NodePath = ^"LightArea"       # Area2D：光照范围
@export var hurt_area_path: NodePath = ^"HurtArea"         # Area2D：伤害范围

# 能量贴图（0~5）
@export var energy_texture_paths: PackedStringArray = PackedStringArray([
	"res://art/lightflower/lightflower_0.png",
	"res://art/lightflower/lightflower_1.png",
	"res://art/lightflower/lightflower_2.png",
	"res://art/lightflower/lightflower_3.png",
	"res://art/lightflower/lightflower_4.png",
	"res://art/lightflower/lightflower_5.png",
])

var energy: int = 0
var _is_emitting: bool = false
var _flash_active: bool = false
var _flash_tween: Tween
var _source_id: int = 0
var _energy_textures: Array[Texture2D] = []

@onready var _sprite: Sprite2D = get_node_or_null(sprite_path) as Sprite2D
@onready var _glow: PointLight2D = get_node_or_null(glow_path) as PointLight2D
@export var glow_energy_per_charge: float = 0.6   # 每1点能量增加的亮度
@export var glow_flash_bonus: float = 10.0        # 释放瞬间额外+10
@export var glow_flash_fade_time: float = 0.15    # “立刻渐变到0”的时间
@onready var _self_area: Area2D = get_node_or_null(self_area_path) as Area2D
@onready var _light_area: Area2D = get_node_or_null(light_area_path) as Area2D
@onready var _hurt_area: Area2D = get_node_or_null(hurt_area_path) as Area2D

func _ready() -> void:
	_source_id = get_instance_id()
	energy = clamp(initial_energy, 0, ENERGY_MAX)

	_cache_energy_textures()

	if _self_area:
		_self_area.monitoring = true
		_self_area.monitorable = true
	if _light_area:
		_light_area.monitoring = true
		_light_area.monitorable = true
	if _hurt_area:
		_hurt_area.monitoring = true
		_hurt_area.monitorable = true

	EventBus.thunder_burst.connect(_on_thunder_burst)
	EventBus.light_started.connect(_on_light_started)
	EventBus.light_finished.connect(_on_light_finished)

	_apply_visual_state(false)

func _on_thunder_burst(_add_seconds: float) -> void:
	# 发光期间不再充能
	if _is_emitting:
		# 发光中也允许充能，但不在发光中触发新一轮释放
		if energy < ENERGY_MAX:
			energy += 1
			_apply_visual_state(true)
		return

	if energy < ENERGY_MAX:
		energy += 1
		if debug_print:
			print("[Flower ", _source_id, "] energy -> ", energy)
		_apply_visual_state(false)
		return

	# energy == 5：本次雷击触发自动释放（固定用满能量=5）
	_release_light_with_energy(ENERGY_MAX)

# 供锁链命中调用：手动释放（默认用当前energy，或要求满能量）
func on_chain_hit(_player: Node, _slot: int) -> int:
	if not allow_chain_release:
		return 0
	if _is_emitting:
		return 0
	if chain_release_requires_full:
		if energy < ENERGY_MAX:
			return 0
		_release_light_with_energy(ENERGY_MAX)
	else:
		if energy <= 0:
			return 0
		_release_light_with_energy(energy)
	return 0

func _release_light_with_energy(release_energy: int) -> void:
	if _is_emitting:
		return

	release_energy = clamp(release_energy, 1, ENERGY_MAX)
	_is_emitting = true

	var light_time: float = float(release_energy) * light_time_per_energy

	# 记录释放前的“当前发光度”（由能量决定）
	var pre_glow: float = 0.0
	if _glow:
		pre_glow = float(energy) * glow_energy_per_charge

	# 释放触发：立刻清零能量 + 贴图切0 + 基础亮度归0
	energy = 0
	_apply_visual_state(true)

	# 闪烁：当前亮度 + 10，然后立刻渐变到 0
	_flash_glow(pre_glow)

	# 释放瞬间伤害：玩家 + 非飞怪
	_damage_targets_in_hurt_area()

	# 广播光照开始（给其它花/怪物计数系统用）
	EventBus.light_started.emit(_source_id, light_time, _light_area)

	if debug_print:
		print("[Flower ", _source_id, "] release_light energy=", release_energy, " time=", light_time)

	await get_tree().create_timer(light_time).timeout

	_is_emitting = false
	_apply_visual_state(false)
	EventBus.light_finished.emit(_source_id)
func _flash_glow(pre_glow: float) -> void:
	if _glow == null:
		return

	_flash_active = true
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()

	_glow.energy = pre_glow + glow_flash_bonus

	_flash_tween = create_tween()
	_flash_tween.tween_property(_glow, "energy", 0.0, glow_flash_fade_time)
	_flash_tween.finished.connect(func() -> void:
		_flash_active = false
		# 闪光结束后，立刻用当前能量刷新一次灯光强度（以及贴图本来就会正确）
		_apply_visual_state(_is_emitting)
	)
func _damage_targets_in_hurt_area() -> void:
	if _hurt_area == null:
		return

	var bodies := _hurt_area.get_overlapping_bodies()
	for b in bodies:
		if b is Player:
			(b as Player).apply_damage(1, global_position)
			continue

		var m := b as MonsterBase
		if m != null:
			# 1) 飞怪不吃花的 Hurt（按你需求：除了飞怪以外）
			if b is MonsterFly or b.is_in_group("flying_monster"):
				continue

			# 2) Walk 怪：不掉血，改眩晕
			if b is MonsterWalk:
				m.apply_stun(walk_stun_time, true)
				continue

			# 3) 其他怪（如果你未来需要）：维持掉血
			m.take_damage(1)
			continue

func _on_light_started(source_id: int, _remaining_time: float, source_light_area: Area2D) -> void:
	# 自己的光不作用自己
	if source_id == _source_id:
		return
	if _self_area == null or source_light_area == null:
		return
	if not source_light_area.overlaps_area(_self_area):
		return

	# 规则：光照事件到来时，先判断是否要“因满能量而立刻释放”
	# 注意：发光中不允许再触发新一轮释放（防无限递归），但仍允许充能
	if (not _is_emitting) and energy >= ENERGY_MAX:
		# 先释放（这一步会把 energy 清零，并更新贴图为 0）
		_release_light_with_energy(ENERGY_MAX)

		# 你期望：花B释放的辐射也应该让花A立刻 +1 能量，形成连锁
		# 因为释放函数刚把 energy 清零，所以这里 +1 会变成 1，并立刻刷新贴图
		energy = min(energy + 1, ENERGY_MAX)
		_apply_visual_state(true) # true 表示目前处于 emitting 状态（你脚本里 glow/闪光逻辑会用到）
		return

	# 非满能量或正在发光：正常充能 +1（无延迟，立刻刷新贴图）
	energy = min(energy + 1, ENERGY_MAX)
	_apply_visual_state(_is_emitting)

func _on_light_finished(_any_source_id: int) -> void:
	pass

func _apply_visual_state(emitting: bool) -> void:
	# 贴图：严格按能量
	var idx: int = int(clamp(energy, 0, 5))
	_apply_energy_texture(idx)

	# 灯光：能量越高越亮；但闪光 tween 期间不要抢控制权
	if _glow:
		if not _flash_active:
			_glow.energy = float(energy) * glow_energy_per_charge
		
func _cache_energy_textures() -> void:
	_energy_textures.clear()
	_energy_textures.resize(6)

	for i in range(6):
		var p: String = energy_texture_paths[i] if i < energy_texture_paths.size() else ""
		if p.is_empty():
			continue
		if not ResourceLoader.exists(p):
			push_error("[LightningFlower] texture not found: %s" % p)
			continue
		_energy_textures[i] = load(p) as Texture2D

func _apply_energy_texture(index: int) -> void:
	if _sprite == null:
		return
	index = clamp(index, 0, 5)
	var tex: Texture2D = _energy_textures[index] if index < _energy_textures.size() else null
	if tex != null:
		_sprite.texture = tex
