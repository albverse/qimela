extends ChimeraBase
class_name ChimeraTemplate
## ============================================================================
## 奇美拉模板脚本 - 使用说明
## ============================================================================
## 
## 【创建新奇美拉步骤】
## 1. 复制此脚本，重命名为 chimera_xxx.gd
## 2. 修改 class_name 为 ChimeraXxx
## 3. 在 _ready() 中设置 species_id、attribute_type 等属性
## 4. 根据需要重写行为方法
## 5. 复制 ChimeraTemplate.tscn，挂载新脚本，设置贴图和碰撞体
## 6. 在 fusion_registry.gd 中注册此奇美拉为融合产物
##
## 【奇美拉 vs 怪物】
## - 奇美拉由两个虚弱/眩晕怪物融合产生
## - 通常可被玩家链接并跟随
## - 可设置为不可攻击（友好单位）
## - 可提供特殊能力（如回血、攻击等）
##
## 【必填属性】
## - species_id: 物种ID（如 &"chimera_stone_snake"）
## - attribute_type: 属性类型
##
## 【奇美拉专属属性】
## - follow_player_when_linked: 链接时是否跟随玩家
## - can_be_linked: 是否可被锁链链接
## - follow_speed: 跟随速度
## ============================================================================


func _ready() -> void:
	# ========== 必填：物种ID ==========
	species_id = &"chimera_template"
	
	# ========== 必填：属性类型 ==========
	attribute_type = AttributeType.NORMAL
	
	# ========== 可选：尺寸 ==========
	size_tier = SizeTier.MEDIUM
	
	# ========== 可选：UI图标 ==========
	# ui_icon = preload("res://art/your_chimera_icon.png")
	
	# ========== 奇美拉专属设置 ==========
	
	# 链接时是否跟随玩家移动
	# true: 链接后会向玩家位置移动
	# false: 链接后保持原位
	# follow_player_when_linked = true
	
	# 跟随速度（像素/秒）
	# follow_speed = 170.0
	
	# 停止跟随的距离阈值（接近玩家多少像素时停止）
	# stop_threshold_x = 6.0
	
	# 必须调用父类_ready
	super._ready()


func on_chain_hit(_player: Node, _chain_index: int) -> int:
	## ========================================================================
	## 锁链命中时调用
	## ========================================================================
	## 返回值决定锁链行为：
	##   0 = 无法链接（锁链会溶解消失）
	##   1 = 可链接（进入LINKED状态，锁链保持连接）
	## 
	## 【常见模式】
	## 
	## 1. 始终可链接（友好奇美拉）：
	##    return 1
	## 
	## 2. 无法链接（敌对奇美拉，如ChimeraStoneSnake）：
	##    return 0
	## 
	## 3. 条件链接（需要虚弱才能链接）：
	##    return super.on_chain_hit(_player, _chain_index)
	## ========================================================================
	
	# 默认：调用父类逻辑（检查虚弱/眩晕状态）
	return super.on_chain_hit(_player, _chain_index)


## ============================================================================
## 可选重写方法
## ============================================================================

# func _do_move(dt: float) -> void:
#     ## 自定义移动逻辑
#     ## 注意：如果 follow_player_when_linked = true，链接时父类会处理跟随
#     super._do_move(dt)

# func on_chain_attached(slot: int) -> void:
#     ## 锁链成功链接时调用
#     super.on_chain_attached(slot)
#     # 自定义效果，如播放音效、特效等

# func on_chain_detached(slot: int) -> void:
#     ## 锁链断开时调用
#     super.on_chain_detached(slot)
#     # 自定义效果

# func on_player_interact(player: Player) -> void:
#     ## 玩家主动互动时调用（如按键使用）
#     ## 示例：回血奇美拉
#     if player.has_method("heal"):
#         player.call("heal", 2)
#     queue_free()  # 使用后消失


## ============================================================================
## 攻击型奇美拉示例（参考 ChimeraStoneSnake）
## ============================================================================
## 
## 如果需要创建会攻击玩家的奇美拉：
## 
## 1. 添加 DetectionArea (Area2D) 子节点用于检测玩家
##    - collision_layer = 0
##    - collision_mask = 2 (PlayerBody层)
## 
## 2. 在脚本中：
##    @export var attack_cooldown: float = 1.0
##    @export var bullet_speed: float = 400.0
##    var _attack_timer: float = 0.0
##    var _target_player: Player = null
##    
##    func _ready() -> void:
##        super._ready()
##        var detection = get_node_or_null("DetectionArea") as Area2D
##        if detection:
##            detection.body_entered.connect(_on_body_entered)
##            detection.body_exited.connect(_on_body_exited)
##    
##    func _on_body_entered(body: Node2D) -> void:
##        if body is Player:
##            _target_player = body as Player
##    
##    func _on_body_exited(body: Node2D) -> void:
##        if body == _target_player:
##            _target_player = null
##    
##    func _physics_process(dt: float) -> void:
##        super._physics_process(dt)
##        if _target_player and is_instance_valid(_target_player):
##            _attack_timer -= dt
##            if _attack_timer <= 0.0:
##                _fire_bullet()
##                _attack_timer = attack_cooldown
##    
##    func _fire_bullet() -> void:
##        # 创建子弹逻辑...
## ============================================================================
