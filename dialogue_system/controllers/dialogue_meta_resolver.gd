extends RefCounted
class_name DialogueMetaResolver

## 对话元数据解析器
## 职责：从 DialogueLine.character 与 tags 解析结构化元数据
## 输出 DialogueLineMeta，不操作任何节点树

const LOG_PREFIX: String = "[DialogueMetaResolver]"
var debug_log: bool = false

## 角色名 → role 映射表（可在对话开始时配置）
var character_role_map: Dictionary = {}


func resolve(line: Object) -> DialogueLineMeta:
	var meta: DialogueLineMeta = DialogueLineMeta.new()

	var character: String = ""
	if line.has_method("get") or "character" in line:
		character = str(line.character) if line.character else ""

	meta.speaker_id = StringName(character)

	# 解析 tags
	var tags: PackedStringArray = _get_tags(line)
	var tag_map: Dictionary = _parse_tags_to_map(tags)

	# speaker_role：优先从 tag 取，其次从映射表
	if tag_map.has("role"):
		meta.speaker_role = StringName(tag_map["role"])
	elif character_role_map.has(character):
		meta.speaker_role = StringName(character_role_map[character])
	else:
		meta.speaker_role = &"other"

	# emotion
	if tag_map.has("emotion"):
		meta.emotion = StringName(tag_map["emotion"])

	# use_talk
	if tag_map.has("talk"):
		var talk_val: String = tag_map["talk"].to_lower()
		meta.use_talk = talk_val == "true" or talk_val == "1" or talk_val == "yes"
	else:
		meta.use_talk = true

	# after_text
	if tag_map.has("after"):
		meta.after_text = StringName(tag_map["after"])

	# skin_override
	if tag_map.has("skin"):
		meta.skin_override = StringName(tag_map["skin"])

	# bubble_style_override
	if tag_map.has("bubble_style"):
		meta.bubble_style_override = StringName(tag_map["bubble_style"])

	if debug_log:
		print("%s Resolved: role=%s, emotion=%s, talk=%s, after=%s, speaker=%s" % [
			LOG_PREFIX, meta.speaker_role, meta.emotion,
			str(meta.use_talk), meta.after_text, meta.speaker_id
		])

	return meta


func _get_tags(line: Object) -> PackedStringArray:
	if "tags" in line and line.tags is PackedStringArray:
		return line.tags as PackedStringArray
	return PackedStringArray()


func _parse_tags_to_map(tags: PackedStringArray) -> Dictionary:
	## 解析 tags 数组为 key=value 字典
	## 支持格式: "role=player", "emotion=angry", "talk=true"
	var result: Dictionary = {}
	for tag: String in tags:
		var stripped: String = tag.strip_edges()
		var eq_pos: int = stripped.find("=")
		if eq_pos > 0:
			var key: String = stripped.left(eq_pos).strip_edges()
			var value: String = stripped.substr(eq_pos + 1).strip_edges()
			result[key] = value
	return result
