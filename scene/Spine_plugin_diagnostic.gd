extends Node
class_name SpinePluginDiagnostic

## Spine 插件诊断工具
## 用于检测当前 Godot 项目中 Spine 插件的版本和可用 API
## 
## 使用方法：
## 1. 将此脚本添加为 SpineSprite 节点的子节点
## 2. 运行游戏
## 3. 查看控制台输出的诊断信息

@export var spine_sprite_path: NodePath = NodePath("..")

func _ready() -> void:
	var spine_sprite: Node = get_node_or_null(spine_sprite_path)
	if spine_sprite == null:
		print("[SpineDiag] ERROR: SpineSprite not found at path: %s" % spine_sprite_path)
		return
	
	var separator: String = "=".repeat(80)
	print(separator)
	print("[SpineDiag] Spine Plugin Diagnostic Report")
	print(separator)
	
	# 基本信息
	print("\n1. NODE INFO:")
	print("   Type: %s" % spine_sprite.get_class())
	print("   Script: %s" % spine_sprite.get_script())
	
	# 检查方法
	print("\n2. AVAILABLE METHODS:")
	var methods: Array = spine_sprite.get_method_list()
	
	var play_methods: Array = []
	var clear_methods: Array = []
	var state_methods: Array = []
	var anim_check_methods: Array = []
	
	for method: Dictionary in methods:
		var method_name: String = method.name
		if "animation" in method_name or "anim" in method_name or "play" in method_name:
			play_methods.append(method_name)
		if "clear" in method_name or "stop" in method_name:
			clear_methods.append(method_name)
		if "state" in method_name or "skeleton" in method_name:
			state_methods.append(method_name)
		if "has_animation" in method_name or "find" in method_name:
			anim_check_methods.append(method_name)
	
	print("\n   Play/Animation Methods:")
	for m in play_methods:
		print("     - %s" % m)
	
	print("\n   Clear/Stop Methods:")
	for m in clear_methods:
		print("     - %s" % m)
	
	print("\n   State/Skeleton Methods:")
	for m in state_methods:
		print("     - %s" % m)
	
	print("\n   Animation Check Methods:")
	for m in anim_check_methods:
		print("     - %s" % m)
	
	# 检查信号
	print("\n3. AVAILABLE SIGNALS:")
	var signals: Array = spine_sprite.get_signal_list()
	for sig: Dictionary in signals:
		print("   - %s (args: %s)" % [sig.name, sig.args])
	
	# 检查属性
	print("\n4. AVAILABLE PROPERTIES:")
	var properties: Array = spine_sprite.get_property_list()
	var relevant_props: Array = []
	for prop: Dictionary in properties:
		var prop_name: String = prop.name
		if "animation" in prop_name or "skeleton" in prop_name or "data" in prop_name:
			relevant_props.append("%s (%s)" % [prop_name, prop.type])
	
	for p in relevant_props:
		print("   - %s" % p)
	
	# API 兼容性测试
	print("\n5. API COMPATIBILITY TEST:")
	_test_api_compatibility(spine_sprite)
	
	print("\n" + separator)
	print("[SpineDiag] End of Report")
	print(separator)


func _test_api_compatibility(spine_sprite: Node) -> void:
	# 测试播放动画
	print("\n   Testing Play Animation APIs:")
	
	# 方法1：get_animation_state().set_animation()
	if spine_sprite.has_method("get_animation_state"):
		var anim_state = spine_sprite.get_animation_state()
		if anim_state != null and anim_state.has_method("set_animation"):
			print("     ✓ get_animation_state().set_animation(track, name, loop) - SUPPORTED")
		else:
			print("     ✗ get_animation_state().set_animation() - NOT SUPPORTED")
	else:
		print("     ✗ get_animation_state() - NOT SUPPORTED")
	
	# 方法2：直接 set_animation()
	if spine_sprite.has_method("set_animation"):
		print("     ✓ set_animation(name, loop, track) - SUPPORTED")
	else:
		print("     ✗ set_animation() - NOT SUPPORTED")
	
	# 方法3：play()
	if spine_sprite.has_method("play"):
		print("     ✓ play(name, loop) - SUPPORTED")
	else:
		print("     ✗ play() - NOT SUPPORTED")
	
	# 测试清除轨道
	print("\n   Testing Clear Track APIs:")
	
	if spine_sprite.has_method("get_animation_state"):
		var anim_state = spine_sprite.get_animation_state()
		if anim_state != null and anim_state.has_method("clear_track"):
			print("     ✓ get_animation_state().clear_track(track) - SUPPORTED")
		else:
			print("     ✗ get_animation_state().clear_track() - NOT SUPPORTED")
	
	if spine_sprite.has_method("clear_track"):
		print("     ✓ clear_track(track) - SUPPORTED")
	else:
		print("     ✗ clear_track() - NOT SUPPORTED")
	
	# 测试动画检查
	print("\n   Testing Animation Check APIs:")
	
	if spine_sprite.has_method("has_animation"):
		print("     ✓ has_animation(name) - SUPPORTED")
	else:
		print("     ✗ has_animation() - NOT SUPPORTED")
	
	# 测试信号
	print("\n   Testing Signals:")
	
	if spine_sprite.has_signal("animation_finished"):
		print("     ✓ animation_finished - SUPPORTED")
	else:
		print("     ✗ animation_finished - NOT SUPPORTED")
	
	if spine_sprite.has_signal("animation_completed"):
		print("     ✓ animation_completed - SUPPORTED")
	else:
		print("     ✗ animation_completed - NOT SUPPORTED")
