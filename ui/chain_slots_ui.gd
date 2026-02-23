extends Control
class_name ChainSlotsUI

@onready var slot_a: Control = $SlotA
@onready var slot_b: Control = $SlotB
@onready var connection_line: Control = $ConnectionLine
@onready var center_icon: TextureRect = $ConnectionLine/CenterIcon

var slot_states: Array[Dictionary] = [{}, {}]
var _cooldown_tweens: Array[Tween] = [null, null]
var _cooldown_duration: float = 0.5
var _cached_target_textures: Array[Texture2D] = [null, null]
var _burn_tweens: Array[Tween] = [null, null]
var _burn_duration: float = 0.5
var _burn_noise_texture: Texture2D
var _burn_curve_texture: Texture2D
var _player: Node
@export var ui_no: Texture2D = preload("res://art/UI_NO.png")
@export var ui_die: Texture2D = preload("res://art/UI_DIE.png")
@export var ui_yes: Texture2D = preload("res://art/UI_yes.png")
@export var cooldown_shader: Shader = preload("res://shaders/chain_cooldown_fill.gdshader")
@export var burn_shader: Shader = preload("res://shaders/fire_Burn_shader.gdshader")



func _ready() -> void:
	EventBus.slot_switched.connect(_on_slot_switched)
	EventBus.chain_fired.connect(_on_chain_fired)
	EventBus.chain_bound.connect(_on_chain_bound)
	EventBus.chain_released.connect(_on_chain_released)
	EventBus.chain_struggle_progress.connect(_on_chain_struggle_progress)

	EventBus.fusion_rejected.connect(_on_fusion_rejected)
	_update_active_indicator(1)
	connection_line.visible = false
	_resolve_cooldown_duration()
	_setup_burn_assets()
	_setup_slot_cooldown(slot_a)
	_setup_slot_cooldown(slot_b)

func _on_slot_switched(active_slot: int) -> void:
	_update_active_indicator(active_slot)

func _update_active_indicator(active_slot: int) -> void:
	var indicator_a: ColorRect = slot_a.get_node_or_null("ActiveIndicator") as ColorRect
	var indicator_b: ColorRect = slot_b.get_node_or_null("ActiveIndicator") as ColorRect
	if indicator_a:
		indicator_a.visible = (active_slot == 0)
	if indicator_b:
		indicator_b.visible = (active_slot == 1)

func _on_chain_fired(slot: int) -> void:
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var flash: ColorRect = slot_node.get_node_or_null("FlashOverlay") as ColorRect
	var monster_icon: TextureRect = slot_node.get_node_or_null("MonsterIcon") as TextureRect
	var anim: AnimationPlayer = slot_node.get_node_or_null(NodePath("Control/AnimationPlayer")) as AnimationPlayer
	
	# 停止正在进行的动画
	if anim != null:
		anim.stop()
	_stop_all_slot_animations(slot)
	
	# 立即清空monster icon
	_clear_monster_icon(monster_icon)
	
	# 清空slot状态
	slot_states[slot] = {}
	
	# 播放闪光效果
	if flash:
		flash.modulate.a = 1.0
		var tw: Tween = create_tween()
		tw.tween_property(flash, "modulate:a", 0.0, 0.2)
	
	# 立即开始cooldown
	_start_cooldown(slot)
	_check_fusion_available()

func _on_chain_bound(slot: int, target: Node, attribute: int, icon_id: int, is_chimera: bool, show_anim: bool) -> void:
	slot_states[slot] = {
		"target": target,
		"attribute": attribute,
		"icon": icon_id,
		"progress": 0.0,
		"is_chimera": is_chimera,
		"anim_played": "",  # 记录播放的动画名
		"anim_length": 0.0
	}
	
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	var monster_icon: TextureRect = slot_node.get_node_or_null("MonsterIcon") as TextureRect

	var anim_path: NodePath = NodePath("Control/AnimationPlayer")
	var anim: AnimationPlayer = slot_node.get_node_or_null(anim_path) as AnimationPlayer

	if icon:
		icon.visible = true
		_set_cooldown_progress(slot, 0.0)
	if monster_icon:
		monster_icon.texture = _resolve_target_icon(target)
		_cached_target_textures[slot] = monster_icon.texture
		monster_icon.visible = (monster_icon.texture != null)

	if anim and show_anim:
		var anim_name: String = ""
		if is_chimera:
			if anim.has_animation("chimera_animation"):
				anim_name = "chimera_animation"
		else:
			if anim.has_animation("appear"):
				anim_name = "appear"
		
		if anim_name != "":
			slot_states[slot]["anim_played"] = anim_name
			if anim_name == "appear":
				var anim_ref: Animation = anim.get_animation(anim_name)
				var anim_length: float = anim_ref.length if anim_ref != null else 0.0
				slot_states[slot]["anim_length"] = anim_length
				anim.play(anim_name)
				anim.pause()
				if anim_length > 0.0:
					anim.seek(anim_length, true)
			else:
				anim.play(anim_name)

	_shake_node(slot_node)
	_check_fusion_available()

func _on_chain_released(slot: int, _reason: StringName) -> void:
	var played_anim: String = slot_states[slot].get("anim_played", "")
	var had_target: bool = not slot_states[slot].is_empty() and slot_states[slot].get("target", null) != null
	var current_progress: float = slot_states[slot].get("progress", 1.0)  # 挣扎进度
	slot_states[slot] = {}
	_cached_target_textures[slot] = null  # ← 添加这一行
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	var monster_icon: TextureRect = slot_node.get_node_or_null("MonsterIcon") as TextureRect
	
	var anim_path: NodePath = NodePath("Control/AnimationPlayer")
	var anim: AnimationPlayer = slot_node.get_node_or_null(anim_path) as AnimationPlayer
	
	if icon:
		icon.visible = true
	
	# =================================================================
	# 没有绑定目标时 → 立即播放cooldown，无任何等待
	# =================================================================
	if not had_target:
		_clear_monster_icon(monster_icon)
		# 停止可能正在播放的动画
		if anim != null:
			anim.stop()
		_check_fusion_available()
		return
	
	# =================================================================
	# 有目标时：严格串行播放
	# 顺序：倒放动画剩余部分(完成后) → burn shader(完成后) → cooldown shader
	# =================================================================
	
	var has_anim: bool = (anim != null and played_anim != "" and anim.has_animation(played_anim))
	var should_burn: bool = monster_icon != null and monster_icon.texture != null and burn_shader != null
	
	# 获取动画时长和当前位置
	var anim_length: float = 0.0
	var current_anim_pos: float = 0.0
	if has_anim:
		var anim_ref: Animation = anim.get_animation(played_anim)
		anim_length = anim_ref.length if anim_ref != null else 0.0
		# 根据挣扎进度计算当前动画位置
		# progress=1.0时动画在末尾(anim_length)，progress=0.0时动画在开头(0)
		current_anim_pos = anim_length * (1.0 - current_progress)
	
	# 倒放剩余时间 = 当前位置到0的时间
	var reverse_duration: float = current_anim_pos
	
	var burn_duration: float = _burn_duration if should_burn else 0.0
	
	# 停止所有正在进行的相关tween和动画
	_stop_all_slot_animations(slot)
	
	# 使用单一tween严格串行控制所有步骤
	var tw: Tween = create_tween()
	_release_tweens[slot] = tw
	
	# ===== 步骤1：播放倒放动画（仅剩余部分）=====
	if has_anim and reverse_duration > 0.01:  # 大于10ms才播放
		# 从当前位置开始倒放
		anim.play_backwards(played_anim)
		anim.seek(current_anim_pos, true)
		# 等待倒放完成（只等剩余时间）
		tw.tween_interval(reverse_duration)
		# 动画结束后停止AnimationPlayer防止重复
		tw.tween_callback(func() -> void:
			if anim != null and is_instance_valid(anim):
				anim.stop()
		)
	elif anim != null:
		# 动画已经结束或很短，直接停止
		anim.stop()
	
	# ===== 步骤2：播放burn shader =====
	if should_burn and burn_duration > 0.0:
		# 初始化burn shader
		tw.tween_callback(func() -> void:
			_setup_burn_shader_on_icon(slot, monster_icon)
		)
		# 动画化burn progress参数（直接在主tween中）
		tw.tween_method(
			func(progress: float) -> void:
				_update_burn_progress(slot, monster_icon, progress),
			0.0, 2.0, burn_duration
		)
		# burn完成后清理图标
		tw.tween_callback(func() -> void:
			_clear_monster_icon(monster_icon)
		)
	else:
		# 无burn时直接清理图标
		tw.tween_callback(func() -> void:
			_clear_monster_icon(monster_icon)
		)
	
	# ===== 步骤3：播放cooldown shader =====
	tw.tween_callback(func() -> void:
		_start_cooldown(slot)
	)
	
	_check_fusion_available()

# =============================================================================
# 释放动画辅助函数
# =============================================================================

# 释放过程专用tween数组
var _release_tweens: Array[Tween] = [null, null]

# 保存burn shader材质引用
var _burn_materials: Array[ShaderMaterial] = [null, null]

func _stop_all_slot_animations(slot: int) -> void:
	# 停止release tween
	if _release_tweens[slot] != null:
		_release_tweens[slot].kill()
		_release_tweens[slot] = null
	
	# 停止burn tween
	if _burn_tweens[slot] != null:
		_burn_tweens[slot].kill()
		_burn_tweens[slot] = null
	
	# 停止cooldown tween
	_stop_cooldown_tween(slot)
	
	# 清理burn材质引用
	_burn_materials[slot] = null

func _clear_monster_icon(monster_icon: TextureRect) -> void:
	if monster_icon != null and is_instance_valid(monster_icon):
		monster_icon.visible = false
		monster_icon.texture = null
		monster_icon.material = null

func _setup_burn_shader_on_icon(slot: int, monster_icon: TextureRect) -> void:
	# 设置burn shader材质
	if monster_icon == null or not is_instance_valid(monster_icon):
		return
	if monster_icon.texture == null or burn_shader == null:
		return
	
	var mat := ShaderMaterial.new()
	mat.shader = burn_shader
	if _burn_noise_texture != null:
		mat.set_shader_parameter("noise", _burn_noise_texture)
	if _burn_curve_texture != null:
		mat.set_shader_parameter("colorCurve", _burn_curve_texture)
	mat.set_shader_parameter("timed", false)
	mat.set_shader_parameter("progress", 0.0)
	monster_icon.material = mat
	monster_icon.visible = true
	
	# 保存材质引用以便更新progress
	_burn_materials[slot] = mat
	_cached_target_textures[slot] = null

func _update_burn_progress(slot: int, monster_icon: TextureRect, progress: float) -> void:
	# 更新burn shader的progress参数
	if _burn_materials[slot] != null:
		_burn_materials[slot].set_shader_parameter("progress", progress)
	elif monster_icon != null and is_instance_valid(monster_icon):
		var mat: ShaderMaterial = monster_icon.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("progress", progress)

func _on_chain_struggle_progress(slot: int, t01: float) -> void:
	if slot_states[slot].is_empty():
		return
	slot_states[slot]["progress"] = t01
	var played_anim: String = slot_states[slot].get("anim_played", "")
	if played_anim != "appear":
		return
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var anim: AnimationPlayer = slot_node.get_node_or_null(NodePath("Control/AnimationPlayer")) as AnimationPlayer
	if anim and anim.has_animation(played_anim):
		var anim_length: float = slot_states[slot].get("anim_length", 0.0)
		if anim_length <= 0.0:
			var anim_ref: Animation = anim.get_animation(played_anim)
			anim_length = anim_ref.length if anim_ref != null else 0.0
		if anim_length > 0.0:
			anim.seek(anim_length * (1.0 - t01), true)

func _check_fusion_available() -> void:
	# 检查两个槽位是否都有目标
	if slot_states[0].is_empty() or slot_states[1].is_empty():
		connection_line.visible = false
		center_icon.visible = false
		return
	
	# 安全获取target - 使用Variant避免直接赋值错误
	var target0_variant = slot_states[0].get("target", null)
	var target1_variant = slot_states[1].get("target", null)
	
	# 检查是否为null
	if target0_variant == null or target1_variant == null:
		connection_line.visible = false
		center_icon.visible = false
		return
	
	# 检查实例是否有效
	if not is_instance_valid(target0_variant) or not is_instance_valid(target1_variant):
		# 清理无效引用
		if not is_instance_valid(target0_variant):
			slot_states[0].erase("target")
			_cached_target_textures[0] = null
		if not is_instance_valid(target1_variant):
			slot_states[1].erase("target")
			_cached_target_textures[1] = null
		connection_line.visible = false
		center_icon.visible = false
		return
	
	# 现在可以安全地转换为Node
	var target0: Node = target0_variant as Node
	var target1: Node = target1_variant as Node
	
	if target0 == null or target1 == null:
		connection_line.visible = false
		center_icon.visible = false
		return
	
	connection_line.visible = true
	
	# 相同目标 → 无法合成
	if target0 == target1:
		center_icon.texture = ui_no
		center_icon.visible = true
		return
	
	# 获取EntityBase
	var entity0: EntityBase = target0 as EntityBase
	var entity1: EntityBase = target1 as EntityBase
	
	if entity0 == null or entity1 == null:
		center_icon.texture = ui_no
		center_icon.visible = true
		return
	
	# 使用FusionRegistry检查融合结果
	var result: Dictionary = FusionRegistry.check_fusion(entity0, entity1)
	
	var result_type: int = result.get("type", -1)
	
	match result_type:
		FusionRegistry.FusionResultType.SUCCESS:
			center_icon.texture = ui_yes
		FusionRegistry.FusionResultType.REJECTED:
			center_icon.texture = ui_no
		_:
			# 其他类型（FAIL_HOSTILE, FAIL_VANISH等）
			center_icon.texture = ui_die
	
	center_icon.visible = true

func _on_fusion_rejected() -> void:
	if not slot_states[0].is_empty():
		_shake_node(slot_a)
	if not slot_states[1].is_empty():
		_shake_node(slot_b)

func _setup_slot_cooldown(slot_node: Control) -> void:
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	if icon == null or cooldown_shader == null:
		return
	icon.visible = true
	if icon.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = cooldown_shader
		icon.material = mat
	_set_icon_progress(icon, 1.0)

func _set_cooldown_progress(slot: int, t01: float) -> void:
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	if icon == null:
		return
	_set_icon_progress(icon, t01)

func _set_icon_progress(icon: TextureRect, t01: float) -> void:
	var mat: ShaderMaterial = icon.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("progress", clamp(t01, 0.0, 1.0))

func _process(_delta: float) -> void:
	for slot in range(2):
		if slot_states[slot].is_empty():
			continue
		
		# 安全获取target，避免访问已释放对象
		var target_variant = slot_states[slot].get("target", null)
		if target_variant == null:
			continue
		
		# 检查是否为有效的Node实例
		if not is_instance_valid(target_variant):
			# 清理已失效的target引用
			slot_states[slot].erase("target")
			continue
		
		var target: Node = target_variant as Node
		if target == null:
			continue
		
		var slot_node: Control = slot_a if slot == 0 else slot_b
		var monster_icon: TextureRect = slot_node.get_node_or_null("MonsterIcon") as TextureRect
		if monster_icon == null or not is_instance_valid(monster_icon):
			continue
		var next_texture: Texture2D = _resolve_target_icon(target)
		if next_texture != null and not is_instance_valid(next_texture):
			next_texture = null
		if next_texture != null and next_texture.get_rid().is_valid() == false:
			next_texture = null
		if next_texture != _cached_target_textures[slot]:
			var safe_texture: Texture2D = null
			if next_texture != null:
				var img: Image = next_texture.get_image()
				if img != null:
					safe_texture = ImageTexture.create_from_image(img)
				else:
					safe_texture = next_texture
			_cached_target_textures[slot] = safe_texture
			monster_icon.texture = safe_texture
			monster_icon.visible = (safe_texture != null)

func _resolve_target_icon(target: Node) -> Texture2D:
	if target != null and target.has_method("get_ui_icon"):
		var tex: Texture2D = target.call("get_ui_icon")
		if tex != null:
			return tex
	var sprite: Sprite2D = target.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		return sprite.texture
	return null

func _resolve_cooldown_duration() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	_player = players[0] as Node
	if _player == null:
		return
	var value: Variant = _player.get("burn_time")
	if typeof(value) == TYPE_FLOAT:
		_cooldown_duration = maxf(value, 0.0)
		_burn_duration = _cooldown_duration

func _setup_burn_assets() -> void:
	if burn_shader == null:
		return
	if _burn_noise_texture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 6.0
		var noise_tex := NoiseTexture2D.new()
		noise_tex.noise = noise
		noise_tex.width = 128
		noise_tex.height = 128
		noise_tex.generate_mipmaps = true
		_burn_noise_texture = noise_tex
	if _burn_curve_texture == null:
		var gradient := Gradient.new()
		gradient.add_point(0.0, Color(0.0, 0.0, 0.0, 0.0))
		gradient.add_point(0.2, Color(0.8, 0.2, 0.0, 0.9))
		gradient.add_point(0.6, Color(1.0, 0.6, 0.2, 1.0))
		gradient.add_point(1.0, Color(1.0, 1.0, 1.0, 0.0))
		var gradient_tex := GradientTexture1D.new()
		gradient_tex.gradient = gradient
		gradient_tex.width = 256
		_burn_curve_texture = gradient_tex

func _stop_cooldown_tween(slot: int) -> void:
	var tw: Tween = _cooldown_tweens[slot]
	if tw != null:
		tw.kill()
	_cooldown_tweens[slot] = null

func _start_cooldown(slot: int) -> void:
	_stop_cooldown_tween(slot)
	_set_cooldown_progress(slot, 0.0)
	if _cooldown_duration <= 0.0:
		_set_cooldown_progress(slot, 1.0)
		return
	var slot_node: Control = slot_a if slot == 0 else slot_b
	var icon: TextureRect = slot_node.get_node_or_null("Icon") as TextureRect
	if icon == null:
		return
	var mat: ShaderMaterial = icon.material as ShaderMaterial
	if mat == null:
		return
	var tw: Tween = create_tween()
	_cooldown_tweens[slot] = tw
	tw.tween_property(mat, "shader_parameter/progress", 1.0, _cooldown_duration)

func _shake_node(node: Control) -> void:
	var original_pos: Vector2 = node.position
	var tw: Tween = create_tween()
	tw.tween_property(node, "position:x", original_pos.x + 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x - 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x + 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x - 5, 0.05)
	tw.tween_property(node, "position:x", original_pos.x, 0.05)
