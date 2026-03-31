## 表情过渡动画链自动解析器
## 根据上一稳定状态和本句目标情绪，自动生成动画播放序列
## 无需使用者手动编写完整动画链
class_name ExpressionTransitionResolver
extends RefCounted

## 动画链返回结构
## entries: 按顺序播放的 [anim_name, loop, track] 三元组数组
## stable_state: 文本结束后应停留的稳定状态
class AnimChain:
	var entries: Array[Array] = []  # [[anim_name, loop, track], ...]
	var stable_state: StringName = &"idle_loop"

	func add(anim_name: StringName, loop: bool, track: int = 0) -> void:
		entries.append([anim_name, loop, track])


## 支持的稳定状态列表（从动画名推导）
const STABLE_STATES: Array[StringName] = [
	&"idle_loop",
	&"angry_loop",
]

## 根据情绪名生成稳定状态动画名
## emotion "idle" → "idle_loop", emotion "angry" → "angry_loop"
static func emotion_to_stable(emotion: StringName) -> StringName:
	if emotion == &"" or emotion == &"idle":
		return &"idle_loop"
	return StringName(str(emotion) + "_loop")


## 生成从当前稳定状态到目标情绪的动画链
## from_stable: 当前稳定状态动画名，如 "idle_loop"
## target_emotion: 目标情绪，如 "angry" / "idle"
## use_talk: 本句是否需要说话动画
## has_anim_fn: Callable(anim_name: StringName) -> bool，用于检查动画是否存在
## 返回 AnimChain
static func resolve(
		from_stable: StringName,
		target_emotion: StringName,
		use_talk: bool,
		has_anim_fn: Callable) -> AnimChain:

	var chain := AnimChain.new()
	var target_stable: StringName = emotion_to_stable(target_emotion)

	# ── 情绪过渡 ──
	if from_stable != target_stable:
		# 尝试找 from_to_target 过渡动画
		# from "idle_loop" → emotion "idle"；需要从 stable 名推导 from emotion
		var from_emotion: StringName = _stable_to_emotion(from_stable)
		var transition_name := StringName(str(from_emotion) + "_to_" + str(target_emotion))
		if has_anim_fn.call(transition_name):
			chain.add(transition_name, false)
		# 没有过渡动画：跳过，直接进入目标状态（短混合由 SpinePortraitController 处理）

	# ── 说话动画 ──
	if use_talk:
		# 优先找 emotion_talk_loop（如 angry_talk_loop）
		var combined_talk := StringName(str(target_emotion) + "_talk_loop")
		if has_anim_fn.call(combined_talk):
			# 自含入场的说话循环（如 angry_talk_loop）
			chain.add(combined_talk, true)
		else:
			# 分段式：emotion_to_talk → talk_loop
			var enter_talk := StringName(str(target_emotion) + "_to_talk")
			if has_anim_fn.call(enter_talk):
				chain.add(enter_talk, false)
			elif has_anim_fn.call(&"idle_to_talk"):
				# idle 专用入场
				chain.add(&"idle_to_talk", false)
			chain.add(&"talk_loop", true)

	chain.stable_state = target_stable
	return chain


## 生成退出说话动画链（text_finished / force_advance 时调用）
## from_emotion: 当前情绪（退出 talk 后返回哪个 stable）
## was_combined_talk: 是否用的是 emotion_talk_loop（自含式）
static func resolve_exit_talk(
		from_emotion: StringName,
		was_combined_talk: bool,
		has_anim_fn: Callable) -> AnimChain:

	var chain := AnimChain.new()
	var target_stable: StringName = emotion_to_stable(from_emotion)

	if not was_combined_talk:
		# 分段式需要显式退出：talk_to_emotion 或 talk_to_idle
		var exit_anim := StringName("talk_to_" + str(from_emotion))
		if has_anim_fn.call(exit_anim):
			chain.add(exit_anim, false)
		elif has_anim_fn.call(&"talk_to_idle"):
			chain.add(&"talk_to_idle", false)

	# 落到稳定 loop
	chain.add(target_stable, true)
	chain.stable_state = target_stable
	return chain


## 从稳定状态名推导情绪名
## "idle_loop" → "idle", "angry_loop" → "angry"
static func _stable_to_emotion(stable: StringName) -> StringName:
	var s: String = str(stable)
	if s.ends_with("_loop"):
		return StringName(s.left(s.length() - 5))
	return stable
