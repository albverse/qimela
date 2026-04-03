extends RefCounted
class_name ExpressionTransitionResolver

## 表情过渡解析器
## 职责：根据"上一稳定态 + 本句目标态"输出动画链
## 不访问 UI 节点，不持有输入逻辑

const LOG_PREFIX: String = "[ExpressionTransitionResolver]"
var debug_log: bool = false

## 已知的可用动画名集合（由 SpinePortraitController 初始化时填入）
var available_animations: PackedStringArray = PackedStringArray()


## 动画链结果
class AnimationChain:
	var transition_anim: StringName = &""    ## 过渡动画（可空）
	var talk_anim: StringName = &""          ## 说话动画（可空）
	var stable_anim: StringName = &""        ## 最终稳定态动画
	var has_transition: bool = false


func resolve(
	current_stable: StringName,
	target_emotion: StringName,
	use_talk: bool,
	after_text: StringName
) -> AnimationChain:
	var chain: AnimationChain = AnimationChain.new()

	# 解析当前情绪（从 xxx_loop 提取基础情绪名）
	var from_emotion: StringName = _extract_emotion(current_stable)

	# 确定最终停留情绪
	var final_emotion: StringName = target_emotion
	if after_text != &"keep" and after_text != &"":
		final_emotion = after_text

	# 1. 过渡动画：从当前情绪到目标情绪
	if from_emotion != target_emotion:
		var transition_name: StringName = StringName(
			str(from_emotion) + "_to_" + str(target_emotion)
		)
		if _has_animation(transition_name):
			chain.transition_anim = transition_name
			chain.has_transition = true
		else:
			if debug_log:
				print("%s No transition '%s', will use short mix" % [
					LOG_PREFIX, transition_name
				])

	# 2. Talk 动画（蓝图 §5.2：统一用 emotion_talk_loop，不使用通用 talk_loop）
	if use_talk:
		var talk_name: StringName = StringName(str(target_emotion) + "_talk_loop")
		if _has_animation(talk_name):
			chain.talk_anim = talk_name
		else:
			if debug_log:
				print("%s No talk animation '%s', skipping talk" % [
					LOG_PREFIX, talk_name
				])

	# 3. 稳定态动画
	var stable_name: StringName = StringName(str(final_emotion) + "_loop")
	if _has_animation(stable_name):
		chain.stable_anim = stable_name
	else:
		# 兜底到 idle_loop
		chain.stable_anim = &"idle_loop"
		if debug_log:
			print("%s No stable '%s', fallback to idle_loop" % [
				LOG_PREFIX, stable_name
			])

	if debug_log:
		print("%s Chain: %s -> [%s] -> [%s] -> %s" % [
			LOG_PREFIX, current_stable,
			chain.transition_anim if chain.has_transition else "none",
			chain.talk_anim if chain.talk_anim != &"" else "none",
			chain.stable_anim
		])

	return chain


func _extract_emotion(anim_name: StringName) -> StringName:
	## 从 xxx_loop / xxx_talk_loop 等动画名中提取情绪基础名
	## 注意：_talk_loop 必须在 _loop 之前检查，因为 _talk_loop 也以 _loop 结尾
	var s: String = str(anim_name)
	if s.ends_with("_talk_loop"):
		return StringName(s.left(s.length() - 10))
	if s.ends_with("_loop"):
		return StringName(s.left(s.length() - 5))
	if s == "" or s == "none":
		return &"idle"
	return StringName(s)


func _has_animation(anim_name: StringName) -> bool:
	return str(anim_name) in available_animations
