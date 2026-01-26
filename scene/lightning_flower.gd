extends Node2D
class_name LightningFlower

const ENERGY_MAX: int = 5
const LIGHT_ENERGY_DELAY: float = 0.5

@export_range(0, 5, 1) var initial_energy: int = 0
@export var light_time_per_energy: float = 1.0
@export var debug_print: bool = true

@export var allow_chain_release: bool = true
@export var chain_release_requires_full: bool = false
@export var walk_stun_time: float = 2.0

@export var sprite_path: NodePath = ^"Sprite2D"
@export var glow_path: NodePath = ^"Glow"
@export var self_area_path: NodePath = ^"SelfArea"
@export var light_area_path: NodePath = ^"LightArea"
@export var hurt_area_path: NodePath = ^"HurtArea"

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
@export var glow_energy_per_charge: float = 0.6
@export var glow_flash_bonus: float = 10.0
@export var glow_flash_fade_time: float = 0.15
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
	if _is_emitting:
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

	_release_light_with_energy(ENERGY_MAX)

func on_chain_hit(_player: Node, _slot: int) -> int:
	if not allow_chain_release:
		return 0
	if chain_release_requires_full:
		if energy < ENERGY_MAX:
			return 0
		_release_light_with_energy(ENERGY_MAX)
		return 1  # ← 改为1
	else:
		if energy <= 0:
			return 0
		_release_light_with_energy(energy)
		return 1  # ← 改为1

var _emit_id: int = 0  # ← 在类顶部添加成员变量

func _release_light_with_energy(release_energy: int) -> void:
	# 删除 if _is_emitting: return
	
	release_energy = clamp(release_energy, 1, ENERGY_MAX)
	_is_emitting = true
	_emit_id += 1  # ← 新增
	var this_id: int = _emit_id  # ← 新增

	var light_time: float = float(release_energy) * light_time_per_energy

	var pre_glow: float = 0.0
	if _glow:
		pre_glow = float(energy) * glow_energy_per_charge

	energy = 0
	_apply_visual_state(true)

	_flash_glow(pre_glow)

	# 主动检测范围内的怪物并通知它们
	_notify_monsters_in_range(light_time)

	# 释放瞬间伤害
	_damage_targets_in_hurt_area()

	# 广播光照开始事件（给其他花用）
	EventBus.light_started.emit(_source_id, light_time, _light_area)

	if debug_print:
		print("[Flower ", _source_id, "] release_light energy=", release_energy, " time=", light_time)

	await get_tree().create_timer(light_time).timeout

	if this_id != _emit_id:  # ← 新增：被新释放覆盖，跳过
		return

	_is_emitting = false
	_apply_visual_state(false)
	EventBus.light_finished.emit(_source_id)

# 主动检测范围内的怪物
func _notify_monsters_in_range(light_time: float) -> void:
	if _light_area == null:
		return
	
	var areas = _light_area.get_overlapping_areas()
	
	for area in areas:
		if area.has_method("get_host"):
			var monster = area.call("get_host") as MonsterBase
			if monster:
				monster.on_light_exposure(light_time)

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
		_apply_visual_state(_is_emitting)
	)

# ✅ 关键修复：飞怪不受HurtArea伤害
func _damage_targets_in_hurt_area() -> void:
	if _hurt_area == null:
		return

	var bodies := _hurt_area.get_overlapping_bodies()
	for b in bodies:
		# 玩家受伤
		if b is Player:
			(b as Player).apply_damage(1, global_position)
			continue

		var m := b as MonsterBase
		if m != null:
			# ✅ 飞怪跳过（不受伤害、不眩晕）
			if b is MonsterFly or b.is_in_group("flying_monster"):
				if debug_print:
					print("[Flower ", _source_id, "] 飞怪 ", b.name, " 免疫HurtArea伤害")
				continue

			# Walk怪：不掉血，改眩晕
			if b is MonsterWalk:
				m.apply_stun(walk_stun_time, true)
				if debug_print:
					print("[Flower ", _source_id, "] Walk怪 ", b.name, " 眩晕 ", walk_stun_time, "秒")
				continue

			# 其他怪物：掉血
			m.take_damage(1)
			continue

func _on_light_started(source_id: int, _remaining_time: float, source_light_area: Area2D) -> void:
	if source_id == _source_id:
		return
	if _self_area == null or source_light_area == null:
		return
	if not source_light_area.overlaps_area(_self_area):
		return

	_apply_light_energy_after_delay(LIGHT_ENERGY_DELAY)

func _apply_light_energy_after_delay(delay_seconds: float) -> void:
	if delay_seconds > 0.0:
		await get_tree().create_timer(delay_seconds).timeout
	if not is_inside_tree():
		return

	if (not _is_emitting) and energy >= ENERGY_MAX:
		_release_light_with_energy(ENERGY_MAX)
		energy = min(energy + 1, ENERGY_MAX)
		_apply_visual_state(true)
		return

	energy = min(energy + 1, ENERGY_MAX)
	_apply_visual_state(_is_emitting)

func _on_light_finished(_any_source_id: int) -> void:
	pass

func _apply_visual_state(_emitting: bool) -> void:
	var idx: int = int(clamp(energy, 0, 5))
	_apply_energy_texture(idx)

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
