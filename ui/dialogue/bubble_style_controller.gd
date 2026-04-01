## 气泡样式控制器
## 管理文字颜色，支持按角色独立设置
## 气泡背景由纹理图片提供，不再需要背景色管理
class_name BubbleStyleController
extends RefCounted

## 玩家气泡文字颜色
var player_text_color: Color = Color(0.82, 0.82, 0.82)
## 对方气泡文字颜色
var other_text_color: Color = Color(0.82, 0.82, 0.82)


## 根据 role 返回文字颜色
func get_text_color(role: StringName) -> Color:
	if role == &"player":
		return player_text_color
	return other_text_color
