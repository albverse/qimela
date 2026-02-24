extends Node2D

## 摄魂 VFX — 自播放 + 自销毁
## 挂到怪物节点下，播放一次性动画后 queue_free
## 路径: res://vfx/soul_extract_vfx.gd

@onready var _spine: SpineSprite = $SpineSprite


func _ready() -> void:
	# 播放一次性动画
	if _spine != null:
		var anim_state = _spine.get_animation_state()
		if anim_state != null:
			anim_state.set_animation("play", false, 0)
		# 连接完成回调 → 自销毁
		if _spine.has_signal("animation_completed"):
			_spine.animation_completed.connect(_on_complete)


func _enter_tree() -> void:
	# 备用：定时器兜底（信号不触发时安全网）
	var timer: SceneTreeTimer = get_tree().create_timer(1.5)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)


func _on_complete(_ss, _entry = null) -> void:
	queue_free()
