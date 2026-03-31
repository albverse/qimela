## 场景环境状态管理（预留接口，当前硬编码 DARK）
## 后续由场景主动调用 set_light_state() 切换亮暗
class_name SceneEnvironment
extends Node

enum LightState {
	BRIGHT,
	DARK,
}

## 当前场景亮暗状态，默认暗（未来由场景主动设置）
var light_state: LightState = LightState.DARK


## 读取当前亮暗状态
func get_light_state() -> LightState:
	return light_state


## 场景主动设置亮暗状态（预留接口）
func set_light_state(new_state: LightState) -> void:
	light_state = new_state
