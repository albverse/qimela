extends Node

## Spine 快速测试（Godot 4.5.1 专用）
## 使用方法：
## 1. 在 Player 场景的 _ready() 中临时调用：
##    SpineQuickTest.run($Visual/SpineSprite)
## 2. 运行游戏，查看控制台输出

class_name SpineQuickTest

static func run(spine_sprite: Node) -> void:
	if spine_sprite == null:
		print("[SpineTest] ERROR: SpineSprite is null!")
		return
	
	var sep: String = "=".repeat(60)
	print("\n" + sep)
	print("[SpineTest] Godot 4.5.1 Spine Plugin Test")
	print(sep)
	
	# 1. 基本信息
	print("\n1. Node Type: %s" % spine_sprite.get_class())
	
	# 2. 测试播放 API
	print("\n2. Testing Play APIs:")
	
	# API 1: get_animation_state().set_animation()
	var has_api1: bool = false
	if spine_sprite.has_method("get_animation_state"):
		var state = spine_sprite.get_animation_state()
		if state != null and state.has_method("set_animation"):
			has_api1 = true
			print("   [✓] get_animation_state().set_animation(track, name, loop)")
	
	if not has_api1:
		print("   [✗] get_animation_state().set_animation()")
	
	# API 2: set_animation()
	if spine_sprite.has_method("set_animation"):
		print("   [✓] set_animation() exists")
		# 检查参数
		var methods = spine_sprite.get_method_list()
		for m in methods:
			if m.name == "set_animation":
				print("      Args count: %d" % m.args.size())
				if m.args.size() > 0:
					var arg_names = []
					for arg in m.args:
						arg_names.append(arg.name)
					print("      Args: %s" % str(arg_names))
	else:
		print("   [✗] set_animation() not found")
	
	# API 3: play()
	if spine_sprite.has_method("play"):
		print("   [✓] play() exists")
	else:
		print("   [✗] play() not found")
	
	# 3. 测试清除 API
	print("\n3. Testing Clear APIs:")
	
	if spine_sprite.has_method("get_animation_state"):
		var state = spine_sprite.get_animation_state()
		if state != null and state.has_method("clear_track"):
			print("   [✓] get_animation_state().clear_track(track)")
		else:
			print("   [✗] get_animation_state().clear_track()")
	
	if spine_sprite.has_method("clear_track"):
		print("   [✓] clear_track(track)")
	else:
		print("   [✗] clear_track()")
	
	# 4. 测试信号
	print("\n4. Animation Signals:")
	
	if spine_sprite.has_signal("animation_finished"):
		print("   [✓] animation_finished")
	else:
		print("   [✗] animation_finished")
	
	if spine_sprite.has_signal("animation_completed"):
		print("   [✓] animation_completed")
	else:
		print("   [✗] animation_completed")
	
	if spine_sprite.has_signal("animation_complete"):
		print("   [✓] animation_complete")
	else:
		print("   [✗] animation_complete")
	
	# 5. 推荐方案
	print("\n5. RECOMMENDED API:")
	if has_api1:
		print("   → Use: get_animation_state().set_animation(track, name, loop)")
		print("   → Plugin Type: Official Spine Runtime")
	elif spine_sprite.has_method("set_animation"):
		print("   → Use: set_animation(name, loop, track)")
		print("   → Plugin Type: Community/Custom")
	else:
		print("   → WARNING: No standard play API found!")
	
	print("\n" + sep)
	print("[SpineTest] Test Complete")
	print(sep + "\n")
