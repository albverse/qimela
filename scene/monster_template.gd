extends MonsterBase
class_name MonsterTemplate
## ============================================================================
## 怪物模板脚本 - 使用说明
## ============================================================================
## 
## 【创建新怪物步骤】
## 1. 复制此脚本，重命名为 monster_xxx.gd
## 2. 修改 class_name 为 MonsterXxx
## 3. 在 _ready() 中设置 species_id、attribute_type 等属性
## 4. 实现 _do_move() 自定义移动逻辑
## 5. 复制 MonsterTemplate.tscn，挂载新脚本，设置贴图和碰撞体
## 6. 在 fusion_registry.gd 中注册融合规则
##
## 【必填属性】
## - species_id: 物种ID，用于融合规则匹配（如 &"walk_dark"）
## - attribute_type: 属性类型（LIGHT/DARK/NORMAL）
##
## 【可选属性】
## - size_tier: 尺寸（SMALL/MEDIUM/LARGE），影响尺寸融合规则
## - ui_icon: UI显示图标
## - max_hp: 最大生命值
## - weak_hp: 进入虚弱状态的HP阈值
## - stun_duration: 眩晕持续时间（秒）
## ============================================================================


func _ready() -> void:
	# ========== 必填：物种ID ==========
	# 用于融合规则匹配，建议格式：种类_属性，如 walk_dark, fly_light
	species_id = &"template_monster"
	
	# ========== 必填：属性类型 ==========
	# LIGHT: 光属性（与暗属性组合产生特殊效果）
	# DARK: 暗属性
	# NORMAL: 普通属性
	attribute_type = AttributeType.NORMAL
	
	# ========== 可选：尺寸 ==========
	# SMALL: 小型（尺寸融合时可能被泯灭）
	# MEDIUM: 中型
	# LARGE: 大型（尺寸融合时可能掉血但存活）
	size_tier = SizeTier.SMALL
	
	# ========== 可选：UI图标 ==========
	# 锁链绑定时在UI槽位显示的图标
	# ui_icon = preload("res://art/your_icon.png")
	
	# ========== 可选：生命值设置 ==========
	# max_hp = 3        # 最大HP
	# weak_hp = 1       # HP <= weak_hp 时进入虚弱状态
	
	# ========== 可选：眩晕设置 ==========
	# stun_duration = 2.0  # 眩晕持续时间（秒）
	
	# 必须调用父类_ready
	super._ready()


func _do_move(dt: float) -> void:
	## ========================================================================
	## 自定义移动逻辑 - 每帧调用（非虚弱/眩晕状态时）
	## ========================================================================
	## 
	## 【重要】虚弱状态时应停止移动：
	## if weak:
	##     velocity = Vector2.ZERO
	##     move_and_slide()
	##     return
	##
	## 【常用移动模式】
	## 
	## 1. 地面巡逻（碰墙转向）：
	##    velocity.y += gravity * dt
	##    velocity.x = float(_dir) * move_speed
	##    move_and_slide()
	##    if is_on_wall():
	##        _dir *= -1
	##
	## 2. 飞行浮动：
	##    _t += dt
	##    velocity.x = float(_dir) * move_speed
	##    move_and_slide()
	##    global_position.y = _base_y + sin(_t * TAU * float_freq) * float_amp
	##
	## 3. 追踪玩家：
	##    var players = get_tree().get_nodes_in_group("player")
	##    if not players.is_empty():
	##        var player = players[0] as Node2D
	##        var dir = (player.global_position - global_position).normalized()
	##        velocity = dir * move_speed
	##        move_and_slide()
	## ========================================================================
	
	# 虚弱时停止移动
	if weak:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	# TODO: 在这里实现你的移动逻辑
	pass


## ============================================================================
## 可选重写方法
## ============================================================================

# func on_chain_hit(_player: Node, _chain_index: int) -> int:
#     ## 锁链命中时调用
#     ## 返回值：
#     ##   0 = 普通受击（扣血）
#     ##   1 = 可链接（虚弱/眩晕状态）
#     ##   其他 = 自定义处理
#     return super.on_chain_hit(_player, _chain_index)

# func take_damage(amount: int) -> void:
#     ## 受到伤害时调用
#     super.take_damage(amount)
#     # 自定义受伤效果...

# func apply_stun(seconds: float, do_flash: bool = true) -> void:
#     ## 进入眩晕状态时调用
#     super.apply_stun(seconds, do_flash)
#     # 自定义眩晕效果...
