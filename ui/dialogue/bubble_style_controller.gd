## 气泡样式控制器
## 管理玩家和对方的气泡背景样式，支持编辑器设置和运行时 override
class_name BubbleStyleController
extends RefCounted

## 玩家气泡背景色
var player_modulate: Color = Color(0.15, 0.18, 0.25, 0.92)
## 对方气泡背景色
var other_modulate: Color = Color(0.08, 0.06, 0.12, 0.92)
## 历史气泡叠加颜色（变暗）
var history_tint: Color = Color(0.6, 0.6, 0.6, 1.0)

## 玩家气泡文字颜色
var player_text_color: Color = Color(0.9, 0.85, 0.75)
## 对方气泡文字颜色
var other_text_color: Color = Color(0.75, 0.85, 0.9)


## 根据 role 返回对应气泡底色
func get_bubble_modulate(role: StringName, is_history: bool) -> Color:
	var base: Color
	if role == &"player":
		base = player_modulate
	else:
		base = other_modulate
	if is_history:
		return Color(base.r * history_tint.r, base.g * history_tint.g, base.b * history_tint.b, base.a * 0.5)
	return base


## 根据 role 返回文字颜色
func get_text_color(role: StringName) -> Color:
	if role == &"player":
		return player_text_color
	return other_text_color
