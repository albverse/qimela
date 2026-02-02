extends Node

# =============================================================================
# FusionRegistry - 融合规则注册表（单例Autoload）
# 
# 功能说明：
# 1. 管理所有怪物/奇美拉的融合规则
# 2. 检查两个实体是否可以融合
# 3. 执行融合并处理结果（生成新实体/泯灭/爆炸等）
# 4. 处理"泯灭融合次数"机制（虚弱实体需要多次融合才会死亡）
# =============================================================================

# ===== 融合结果类型枚举 =====
enum FusionResultType {
	SUCCESS = 0,       # 成功融合：生成新的奇美拉
	FAIL_HOSTILE = 1,  # 失败-敌对：生成敌对怪物（无法进入虚弱状态）
	FAIL_VANISH = 2,   # 失败-泯灭：双方尝试泯灭，生成治愈精灵
	FAIL_EXPLODE = 3,  # 失败-爆炸：双方爆炸+生成烂泥（仅奇美拉+奇美拉）
	HEAL_LARGE = 4,    # 型号不同：大型实体回血或掉血，小型实体消失
	REJECTED = 5,      # 拒绝融合：不满足融合条件（同种族/无规则等）
	WEAKEN_BOSS = 6    # 特殊-削弱Boss：对Boss造成固定百分比伤害
}

# ===== 融合规则表 =====
# 格式：{ "species_a + species_b": { 规则数据 } }
# 键会自动按字母序排列，确保A+B和B+A匹配同一规则
var _rules: Dictionary = {}

# =============================================================================
# 信号定义
# =============================================================================

signal fusion_started(entity_a: Node, entity_b: Node)
# 融合开始时发出
# 用途：播放融合开始的动画/音效

signal fusion_completed(result_type: int, result_entity: Node)
# 融合完成时发出
# result_type: FusionResultType枚举值
# result_entity: 生成的新实体（失败时为null）

signal vanish_progress_updated(entity: Node, current: int, required: int)
# 泯灭进度更新时发出
# entity: 被泯灭的实体
# current: 当前泯灭次数
# required: 需要的总次数
# 用途：UI显示泯灭进度条

# =============================================================================
# 初始化
# =============================================================================

func _ready() -> void:
	# 加载融合规则表
	_load_rules()

# =============================================================================
# 融合规则定义
# 在此处添加/修改所有融合规则
# =============================================================================

func _load_rules() -> void:
	# =================================================================
	# 融合规则说明
	# - 键: "species_a + species_b"（自动按字母序排列）
	# - result_scene: 成功时生成的场景路径
	# - result_type: 融合结果类型
	# =================================================================
	
	_rules = {
		# =================================================================
		# 成功融合规则（SUCCESS）
		# =================================================================
		
		"fly_light + walk_dark": {
			# 飞怪(光属性) + 走怪(暗属性) → 奇美拉A
			# 光暗组合但有特殊规则允许融合
			"result_scene": "res://scene/ChimeraA.tscn",
			"result_type": FusionResultType.SUCCESS
		},
		
		"fly_light + neutral_small": {
			# 飞怪(光属性) + 无属性怪 → 奇美拉A
			# 无属性可与任何属性融合
			"result_scene": "res://scene/ChimeraA.tscn",
			"result_type": FusionResultType.SUCCESS
		},
		
		"neutral_small + walk_dark": {
			# 无属性怪 + 走怪(暗属性) → 奇美拉A
			# 无属性可与任何属性融合
			"result_scene": "res://scene/ChimeraA.tscn",
			"result_type": FusionResultType.SUCCESS
		},"fly_light + hand_light": {
			# 飞怪(光属性) + 走怪(暗属性) → 奇美拉A
			# 光暗组合但有特殊规则允许融合
			"result_scene": "res://scene/Chimera_StoneSnake.tscn",
			"result_type": FusionResultType.SUCCESS
		},
		
		# =================================================================
		# 失败规则 - 泯灭（FAIL_VANISH）
		# 同属性同型号无规则时触发
		# =================================================================
		
		# 注意：同species_id会被check_fusion自动拒绝
		# 光+光（不同variant）可能导致VANISH
		# 暗+暗（不同variant）可能导致VANISH
		
		# =================================================================
		# 失败规则 - 敌对怪物（FAIL_HOSTILE）
		# =================================================================
		
		"fly_light + fly_light_b": {
			# 两只光属性飞怪（不同variant）→ 失败，生成敌对怪
			"result_type": FusionResultType.FAIL_HOSTILE,
			"hostile_scene": "res://scene/MonsterHostile.tscn"
		},
		
		"walk_dark + walk_dark_b": {
			# 两只暗属性走怪（不同variant）→ 失败，生成敌对怪
			"result_type": FusionResultType.FAIL_HOSTILE,
			"hostile_scene": "res://scene/MonsterHostile.tscn"
		},
	}

# =============================================================================
# 工具函数
# =============================================================================

func _make_key(species_a: StringName, species_b: StringName) -> String:
	# 生成规则键（确保A+B和B+A生成相同的键）
	# 参数：
	#   species_a: 第一个物种ID
	#   species_b: 第二个物种ID
	# 返回：按字母序排列的键字符串
	var a := String(species_a)
	var b := String(species_b)
	if a > b:
		return b + " + " + a
	return a + " + " + b

# =============================================================================
# 融合检查
# =============================================================================

func check_fusion(entity_a: EntityBase, entity_b: EntityBase) -> Dictionary:
	# 检查两个实体是否可以融合
	# 参数：
	#   entity_a: 第一个实体
	#   entity_b: 第二个实体
	# 返回：包含融合结果类型和相关数据的字典
	#   - type: FusionResultType枚举值
	#   - 其他字段根据类型而定
	
	# -----------------------------------------------------------------
	# 检查1：同一实例
	# 不能自己和自己融合
	# -----------------------------------------------------------------
	if entity_a == entity_b:
		return { "type": FusionResultType.REJECTED, "reason": "same_instance" }
	
	# -----------------------------------------------------------------
	# 检查2：同种族
	# species_id相同的实体不能融合
	# -----------------------------------------------------------------
	if entity_a.species_id == entity_b.species_id:
		return { "type": FusionResultType.REJECTED, "reason": "same_species" }
	
	var attr_a: int = entity_a.attribute_type
	var attr_b: int = entity_b.attribute_type
	var size_a: int = entity_a.size_tier
	var size_b: int = entity_b.size_tier
	
	# -----------------------------------------------------------------
	# 检查3：光暗属性冲突
	# 光+暗组合会触发特殊规则
	# -----------------------------------------------------------------
	var is_light_dark := (attr_a == EntityBase.AttributeType.LIGHT and attr_b == EntityBase.AttributeType.DARK) or \
						 (attr_a == EntityBase.AttributeType.DARK and attr_b == EntityBase.AttributeType.LIGHT)
	
	if is_light_dark:
		# 先检查是否有特殊规则覆盖
		var key := _make_key(entity_a.species_id, entity_b.species_id)
		if _rules.has(key):
			var rule: Dictionary = _rules[key]
			return {
				"type": rule.get("result_type", FusionResultType.SUCCESS),
				"scene": rule.get("result_scene", ""),
				"rule": rule,
				"entity_a": entity_a,
				"entity_b": entity_b
			}
		
		# 无特殊规则，按默认光暗冲突处理
		# 型号相同 → 必定失败（泯灭/敌对/爆炸）
		if size_a == size_b:
			return _resolve_fail_type(entity_a, entity_b)
		# 型号不同
		else:
			var larger: EntityBase = entity_a if size_a > size_b else entity_b
			var smaller: EntityBase = entity_a if size_a < size_b else entity_b
			# 大型处于虚弱 → 也算失败
			if larger.weak:
				return _resolve_fail_type(entity_a, entity_b)
			# 大型健康 → 大型掉血，小型尝试泯灭
			return {
				"type": FusionResultType.HEAL_LARGE,
				"larger": larger,
				"smaller": smaller,
				"damage_percent": larger.fusion_damage_percent,
				"is_damage": true,
				"entity_a": entity_a,
				"entity_b": entity_b
			}
	
	# -----------------------------------------------------------------
	# 检查4：查找具体融合规则
	# -----------------------------------------------------------------
	var key := _make_key(entity_a.species_id, entity_b.species_id)
	if _rules.has(key):
		var rule: Dictionary = _rules[key]
		return {
			"type": rule.get("result_type", FusionResultType.SUCCESS),
			"scene": rule.get("result_scene", ""),
			"rule": rule,
			"entity_a": entity_a,
			"entity_b": entity_b
		}
	
	# -----------------------------------------------------------------
	# 检查5：通用规则（同属性或含无属性）
	# -----------------------------------------------------------------
	var attr_compatible := (attr_a == attr_b) or \
						   (attr_a == EntityBase.AttributeType.NORMAL) or \
						   (attr_b == EntityBase.AttributeType.NORMAL)
	
	if attr_compatible:
		# 型号不同 → 大型回血
		if size_a != size_b:
			var larger: EntityBase = entity_a if size_a > size_b else entity_b
			var smaller: EntityBase = entity_a if size_a < size_b else entity_b
			var heal_pct := 0.10 if attr_a == attr_b else 0.05
			return {
				"type": FusionResultType.HEAL_LARGE,
				"larger": larger,
				"smaller": smaller,
				"heal_percent": heal_pct,
				"is_damage": false,
				"entity_a": entity_a,
				"entity_b": entity_b
			}
		# 型号相同但无具体规则
		return { "type": FusionResultType.REJECTED, "reason": "no_rule_defined" }
	
	return { "type": FusionResultType.REJECTED, "reason": "incompatible" }

func _resolve_fail_type(a: EntityBase, b: EntityBase) -> Dictionary:
	# 决定融合失败的具体类型
	# 参数：
	#   a: 第一个实体
	#   b: 第二个实体
	# 返回：包含失败类型的字典
	
	var fail_a: int = a.fusion_fail_type
	var fail_b: int = b.fusion_fail_type
	
	var final_fail: int = EntityBase.FailType.RANDOM
	
	# 优先使用实体自身设定的非随机类型
	if fail_a != EntityBase.FailType.RANDOM:
		final_fail = fail_a
	elif fail_b != EntityBase.FailType.RANDOM:
		final_fail = fail_b
	else:
		# 都是随机，则随机选择
		var can_explode: bool = (a.entity_type == EntityBase.EntityType.CHIMERA and \
								 b.entity_type == EntityBase.EntityType.CHIMERA)
		var options: Array[int] = [EntityBase.FailType.HOSTILE, EntityBase.FailType.VANISH]
		if can_explode:
			options.append(EntityBase.FailType.EXPLODE)
		final_fail = options[randi() % options.size()]
	
	var result_type: int
	match final_fail:
		EntityBase.FailType.HOSTILE:
			result_type = FusionResultType.FAIL_HOSTILE
		EntityBase.FailType.VANISH:
			result_type = FusionResultType.FAIL_VANISH
		EntityBase.FailType.EXPLODE:
			result_type = FusionResultType.FAIL_EXPLODE
		_:
			result_type = FusionResultType.FAIL_VANISH
	
	return { "type": result_type, "entity_a": a, "entity_b": b }

# =============================================================================
# 融合执行
# =============================================================================

func execute_fusion(result: Dictionary, player: Player) -> Node:
	# 执行融合操作
	# 参数：
	#   result: check_fusion返回的结果字典
	#   player: 玩家节点引用
	# 返回：生成的新实体节点（失败时返回null）
	
	var entity_a: EntityBase = result.get("entity_a") as EntityBase
	var entity_b: EntityBase = result.get("entity_b") as EntityBase
	
	# 让两个实体在视觉上消失（开始融合动画）
	if entity_a != null and is_instance_valid(entity_a):
		if entity_a.has_method("set_fusion_vanish"):
			entity_a.call("set_fusion_vanish", true)
	if entity_b != null and is_instance_valid(entity_b):
		if entity_b.has_method("set_fusion_vanish"):
			entity_b.call("set_fusion_vanish", true)
	
	# 发出融合开始信号
	fusion_started.emit(entity_a, entity_b)
	
	var spawned: Node = null
	var should_destroy_a: bool = true
	var should_destroy_b: bool = true
	
	# 根据融合结果类型执行不同逻辑
	match result.type:
		FusionResultType.SUCCESS:
			spawned = _execute_success(result, player)
			
		FusionResultType.FAIL_HOSTILE:
			spawned = _execute_fail_hostile(result, player)
			
		FusionResultType.FAIL_VANISH:
			var survivors := _execute_fail_vanish(result, player)
			should_destroy_a = not (entity_a in survivors)
			should_destroy_b = not (entity_b in survivors)
			
		FusionResultType.FAIL_EXPLODE:
			_execute_fail_explode(result, player)
			
		FusionResultType.HEAL_LARGE:
			var survivors := _execute_heal_large(result, player)
			should_destroy_a = not (entity_a in survivors)
			should_destroy_b = not (entity_b in survivors)
			
		FusionResultType.WEAKEN_BOSS:
			_execute_weaken_boss(result, player)
	
	# 清理应该销毁的实体
	if should_destroy_a and entity_a != null and is_instance_valid(entity_a):
		entity_a.queue_free()
	if should_destroy_b and entity_b != null and is_instance_valid(entity_b):
		entity_b.queue_free()
	
	# 发出融合完成信号
	fusion_completed.emit(result.type, spawned)
	return spawned

# =============================================================================
# 各类融合结果的执行函数
# =============================================================================

func _execute_success(result: Dictionary, player: Player) -> Node:
	# 执行成功融合：生成新的奇美拉
	# 参数：
	#   result: 融合结果字典（包含scene路径）
	#   player: 玩家节点
	# 返回：生成的奇美拉节点
	
	var scene_path: String = result.get("scene", "")
	
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("[FusionRegistry] 场景不存在: %s" % scene_path)
		return null
	
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		return null
	
	var entity: Node = scene.instantiate()
	if entity is Node2D:
		(entity as Node2D).global_position = player.global_position
	
	player.get_parent().add_child(entity)
	
	if entity.has_method("setup"):
		entity.call("setup", player)
	
	print("[FusionRegistry] SUCCESS: 生成 %s" % scene_path)
	return entity

func _execute_fail_hostile(result: Dictionary, player: Player) -> Node:
	# 执行失败-敌对：生成敌对怪物
	# 敌对怪物特点：无法进入虚弱状态，被杀死后掉落治愈精灵
	# 参数：
	#   result: 融合结果字典
	#   player: 玩家节点
	# 返回：生成的敌对怪物节点（暂未实现返回null）
	
	var entity_a: EntityBase = result.get("entity_a") as EntityBase
	var entity_b: EntityBase = result.get("entity_b") as EntityBase
	
	print("[FusionRegistry] FAIL_HOSTILE: 生成敌对怪物")
	print("  原料: %s + %s" % [
		entity_a.species_id if entity_a else "null",
		entity_b.species_id if entity_b else "null"
	])
	
	# TODO: 实现敌对怪物生成
	# var hostile_scene: PackedScene = load("res://scene/monster/FailHostile.tscn")
	# var hostile = hostile_scene.instantiate()
	# hostile.global_position = player.global_position
	# hostile.weak_hp = 0  # 无法进入虚弱
	# player.get_parent().add_child(hostile)
	# return hostile
	
	return null

func _execute_fail_vanish(result: Dictionary, player: Player) -> Array[EntityBase]:
	# 执行失败-泯灭：处理泯灭融合次数机制
	# 每个实体需要承受足够次数的泯灭融合才会真正死亡
	# 参数：
	#   result: 融合结果字典
	#   player: 玩家节点
	# 返回：存活下来的实体数组
	
	var entity_a: EntityBase = result.get("entity_a") as EntityBase
	var entity_b: EntityBase = result.get("entity_b") as EntityBase
	var survivors: Array[EntityBase] = []
	
	print("[FusionRegistry] FAIL_VANISH: 泯灭融合")
	
	for ent in [entity_a, entity_b]:
		if ent == null or not is_instance_valid(ent):
			continue
		
		# 调用泯灭融合（增加计数）
		var should_die: bool = ent.apply_vanish_fusion()
		
		# 发送进度信号
		vanish_progress_updated.emit(ent, ent.vanish_fusion_count, ent.vanish_fusion_required)
		
		if should_die:
			# 达到泯灭阈值，生成治愈精灵
			_spawn_healing_sprites(ent, player)
			print("  [%s] 泯灭完成 (%d/%d) → 死亡" % [
				ent.name, ent.vanish_fusion_count, ent.vanish_fusion_required
			])
		else:
			# 未达到阈值，存活
			survivors.append(ent)
			if ent.has_method("set_fusion_vanish"):
				ent.call("set_fusion_vanish", false)
			print("  [%s] 泯灭进度 (%d/%d) → 存活" % [
				ent.name, ent.vanish_fusion_count, ent.vanish_fusion_required
			])
	
	return survivors

func _execute_fail_explode(result: Dictionary, player: Player) -> void:
	# 执行失败-爆炸：双方爆炸，伤害周围
	# 仅奇美拉+奇美拉融合失败时可能触发
	# 参数：
	#   result: 融合结果字典
	#   player: 玩家节点
	
	var entity_a: EntityBase = result.get("entity_a") as EntityBase
	var entity_b: EntityBase = result.get("entity_b") as EntityBase
	
	print("[FusionRegistry] FAIL_EXPLODE: 爆炸")
	
	var explosion_radius := 100.0  # 爆炸伤害半径
	var explosion_damage := 1  # 爆炸伤害值
	
	for ent in [entity_a, entity_b]:
		if ent == null or not is_instance_valid(ent):
			continue
		var pos: Vector2 = ent.global_position
		
		# 伤害玩家
		if player.global_position.distance_to(pos) < explosion_radius:
			if player.has_method("apply_damage"):
				player.call("apply_damage", explosion_damage, pos)
				print("  玩家受到爆炸伤害")
		
		# TODO: 生成爆炸特效和烂泥

func _execute_heal_large(result: Dictionary, _player: Player) -> Array[EntityBase]:
	# 执行型号不同的融合：大型回血/掉血，小型尝试泯灭
	# 参数：
	#   result: 融合结果字典（包含larger/smaller引用）
	#   _player: 玩家节点
	# 返回：存活的实体数组
	
	var larger: EntityBase = result.get("larger") as EntityBase
	var smaller: EntityBase = result.get("smaller") as EntityBase
	var heal_percent: float = result.get("heal_percent", 0.0)
	var damage_percent: float = result.get("damage_percent", 0.0)
	var is_damage: bool = result.get("is_damage", false)
	
	var survivors: Array[EntityBase] = []
	
	# 处理大型实体
	if larger != null and is_instance_valid(larger):
		if is_damage and damage_percent > 0.0:
			# 光暗冲突 → 掉血
			var dmg: int = int(ceil(float(larger.max_hp) * damage_percent))
			larger.hp = max(larger.hp - dmg, 1)
			larger._flash_once()
			print("[FusionRegistry] HEAL_LARGE: %s 损失 %.0f%% HP" % [larger.name, damage_percent * 100])
		elif not is_damage and heal_percent > 0.0:
			# 同属性/无属性 → 回血
			larger.heal_percent(heal_percent)
			print("[FusionRegistry] HEAL_LARGE: %s 回复 %.0f%% HP" % [larger.name, heal_percent * 100])
		
		# 大型存活，恢复视觉
		survivors.append(larger)
		if larger.has_method("set_fusion_vanish"):
			larger.call("set_fusion_vanish", false)
	
	# 处理小型实体（尝试泯灭）
	if smaller != null and is_instance_valid(smaller):
		var should_die: bool = smaller.apply_vanish_fusion()
		vanish_progress_updated.emit(smaller, smaller.vanish_fusion_count, smaller.vanish_fusion_required)
		
		if should_die:
			_spawn_healing_sprites(smaller, _player)
			print("  [%s] 被吸收泯灭 (%d/%d) → 死亡" % [
				smaller.name, smaller.vanish_fusion_count, smaller.vanish_fusion_required
			])
		else:
			survivors.append(smaller)
			if smaller.has_method("set_fusion_vanish"):
				smaller.call("set_fusion_vanish", false)
			print("  [%s] 被吸收但存活 (%d/%d)" % [
				smaller.name, smaller.vanish_fusion_count, smaller.vanish_fusion_required
			])
	
	return survivors

func _execute_weaken_boss(result: Dictionary, _player: Player) -> void:
	# 执行削弱Boss：对Boss造成固定百分比伤害
	# 参数：
	#   result: 融合结果字典（包含rule数据）
	#   _player: 玩家节点
	
	var entity_a: EntityBase = result.get("entity_a") as EntityBase
	var entity_b: EntityBase = result.get("entity_b") as EntityBase
	var rule: Dictionary = result.get("rule", {})
	
	var hp_reduce: float = rule.get("hp_reduce_percent", 0.02)
	
	# 找出Boss（species_id以"boss_"开头）
	var boss: EntityBase = null
	if entity_a != null and String(entity_a.species_id).begins_with("boss_"):
		boss = entity_a
	elif entity_b != null and String(entity_b.species_id).begins_with("boss_"):
		boss = entity_b
	
	if boss != null and is_instance_valid(boss):
		var dmg: int = int(ceil(float(boss.max_hp) * hp_reduce))
		boss.hp = max(boss.hp - dmg, 1)
		boss._flash_once()
		print("[FusionRegistry] WEAKEN_BOSS: %s 损失 %.0f%% HP" % [boss.name, hp_reduce * 100])

# =============================================================================
# 辅助函数
# =============================================================================

func _spawn_healing_sprites(ent: EntityBase, player: Player) -> void:
	# 根据实体型号生成治愈精灵
	# 参数：
	#   ent: 被泯灭的实体
	#   player: 玩家节点
	# 生成数量：小型1只，中型2只，大型3只
	
	var healing_scene: PackedScene = load("res://scene/HealingSprite.tscn") as PackedScene
	
	if healing_scene == null:
		push_error("[FusionRegistry] 治愈精灵场景不存在")
		return
	
	var count: int = 1
	match ent.size_tier:
		EntityBase.SizeTier.SMALL:
			count = 1
		EntityBase.SizeTier.MEDIUM:
			count = 2
		EntityBase.SizeTier.LARGE:
			count = 3
	
	for i in range(count):
		var h: Node = healing_scene.instantiate()
		if h is Node2D:
			var offset := Vector2(randf_range(-30, 30), randf_range(-30, 30))
			(h as Node2D).global_position = ent.global_position + offset
		player.get_parent().add_child(h)
	
	print("  生成 %d 只治愈精灵" % count)

# =============================================================================
# 规则管理API
# =============================================================================

func add_rule(species_a: StringName, species_b: StringName, rule: Dictionary) -> void:
	# 添加融合规则
	# 参数：
	#   species_a: 第一个物种ID
	#   species_b: 第二个物种ID
	#   rule: 规则数据字典
	var key := _make_key(species_a, species_b)
	_rules[key] = rule
	print("[FusionRegistry] 添加规则: %s" % key)

func remove_rule(species_a: StringName, species_b: StringName) -> void:
	# 移除融合规则
	var key := _make_key(species_a, species_b)
	_rules.erase(key)
	print("[FusionRegistry] 移除规则: %s" % key)

func has_rule(species_a: StringName, species_b: StringName) -> bool:
	# 检查是否存在融合规则
	var key := _make_key(species_a, species_b)
	return _rules.has(key)

func get_all_rules() -> Dictionary:
	# 获取所有融合规则（调试用）
	return _rules.duplicate()

func print_all_rules() -> void:
	# 打印所有规则到控制台（调试用）
	print("[FusionRegistry] 当前规则列表:")
	for key in _rules.keys():
		print("  %s → %s" % [key, _rules[key]])
