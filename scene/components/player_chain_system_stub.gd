extends Node
class_name PlayerChainSystemStub

## ChainSystem Phase0 存根
## 只暴露 slot_R_available / slot_L_available
## fire(side)   — 占用 slot（slot → false）
## cancel(side) — 立即取消并恢复 slot（slot → true）
## release(side)— 链动画正常结束后释放 slot（slot → true）
##                模拟真实 ChainSystem 的 fire→dissolve→idle 生命周期
## Phase1+ 替换为完整 PlayerChainSystem

var slot_R_available: bool = true
var slot_L_available: bool = true

var _player: CharacterBody2D = null


func _ready() -> void:
	# 显式初始化，确保场景加载后 slot 状态正确
	slot_R_available = true
	slot_L_available = true


func setup(player: CharacterBody2D) -> void:
	_player = player
	# 再次确保 setup 后 slot 为 true（防御性）
	slot_R_available = true
	slot_L_available = true


func tick(_dt: float) -> void:
	pass  # Phase0: 无链物理


func fire(side: String) -> void:
	if side == "R":
		slot_R_available = false
	elif side == "L":
		slot_L_available = false

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("CHAIN", "fire(%s) sR=%s sL=%s" % [side, str(slot_R_available), str(slot_L_available)])


func cancel(side: String) -> void:
	## 取消：立即恢复 slot（链被回收）
	if side == "R":
		slot_R_available = true
	elif side == "L":
		slot_L_available = true

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("CHAIN", "cancel(%s) sR=%s sL=%s" % [side, str(slot_R_available), str(slot_L_available)])


func release(side: String) -> void:
	## 链动画正常结束后释放 slot
	## 模拟真实 ChainSystem 的 dissolve→idle 生命周期结束
	if side == "R":
		slot_R_available = true
	elif side == "L":
		slot_L_available = true

	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("CHAIN", "release(%s) sR=%s sL=%s" % [side, str(slot_R_available), str(slot_L_available)])
