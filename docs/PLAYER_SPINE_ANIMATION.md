# Player Spine2D 动画系统接入文档

## 概述

本次更新为Player添加了完整的Spine2D动画支持，包括：
- 独立的动画控制器脚本 `player_animator.gd`
- 骨骼锚点位置获取（处理翻转）
- 行走/奔跑/跳跃动画
- 锁链发射/取消动画

## 文件改动

### 新增文件
| 文件 | 说明 |
|------|------|
| `scene/components/player_animator.gd` | 动画控制器（独立脚本） |

### 修改文件
| 文件 | 改动内容 |
|------|----------|
| `scene/player.gd` | 添加animator引用、run_speed_mult参数 |
| `scene/components/player_movement.gd` | 添加动画调用、双击奔跑、跳跃状态检测 |
| `scene/components/player_chain_system.gd` | 使用骨骼锚点、添加锁链动画调用 |
| `scene/Player.tscn` | 添加Animator节点 |

---

## 动画名称映射

### 基础动画
| 变量名 | 默认值 | 触发时机 |
|--------|--------|----------|
| `anim_idle` | `"idel"` | 静止站立 |
| `anim_walk` | `"walk"` | 行走时 |
| `anim_run` | `"run"` | 双击方向键奔跑时（1.3倍速） |

### 跳跃动画
| 变量名 | 默认值 | 触发时机 |
|--------|--------|----------|
| `anim_jump_up` | `"jump_up"` | 按下跳跃键瞬间 |
| `anim_jump_loop` | `"jump_loop"` | 空中下落循环 |
| `anim_jump_down` | `"jump_down"` | 落地瞬间（播完回idle） |

### 锁链发射动画
| 变量名 | 默认值 | 触发时机 |
|--------|--------|----------|
| `anim_chain_r` | `"chain_R"` | 右手发射锁链 |
| `anim_chain_l` | `"chain_L"` | 左手发射锁链 |
| `anim_chain_lr` | `"chain_LR"` | 0.2秒内连击双手发射 |

### 锁链取消动画
| 变量名 | 默认值 | 触发时机 |
|--------|--------|----------|
| `anim_chain_r_cancel` | `"chain_R_cancel"` | 按X取消右手锁链 |
| `anim_chain_l_cancel` | `"chain_L_cancel"` | 按X取消左手锁链 |
| `anim_chain_lr_cancel` | `"chain_LR_cancel"` | 按X取消双手锁链 |

---

## 骨骼锚点配置

### Spine中需要的骨骼
```
Root
├── Body
│   ├── ArmL → HandL → chain_anchor_l  ← 左手锁链发射点
│   └── ArmR → HandR → chain_anchor_r  ← 右手锁链发射点
```

### 翻转处理逻辑（已调整）
> 历史方案里做过“朝向翻转时左右骨骼交换”，该方案已被放弃。

当前实现改为：
- 始终按语义直接取骨骼：右手=`chain_anchor_r`、左手=`chain_anchor_l`；
- 角色朝向翻转由 `Visual.scale.x` 统一处理；
- 锁链锚点通过骨骼全局坐标接口获取，不再做左右骨骼名交换。

### Inspector配置
在 `Components/Animator` 节点的Inspector中可配置：
- `bone_chain_anchor_l`: 左手锚点骨骼名（默认 `chain_anchor_l`）
- `bone_chain_anchor_r`: 右手锚点骨骼名（默认 `chain_anchor_r`）

---

## 动画状态流程

### 地面移动
```
idle ←→ walk ←→ run
      ↑        ↑
      └────────┘
      松开按键
```

### 跳跃
```
[按W] → jump_up → [速度向下] → jump_loop → [落地] → jump_down → idle
```

### 锁链发射
```
[点击] → chain_R / chain_L / chain_LR → [播完] → idle
                    ↑
           (0.2秒内连击触发chain_LR)
```

### 锁链取消
```
[按X] → chain_R_cancel / chain_L_cancel / chain_LR_cancel → [播完] → idle
                    ↑
           (根据当前激活的链选择动画)
```

---

## 奔跑机制

- **触发**：0.25秒内双击同一方向键（AA 或 DD）
- **速度**：`move_speed * run_speed_mult`（默认1.3倍）
- **结束**：松开所有方向键

---

## API参考

### PlayerAnimator 公开方法

```gdscript
# 基础动画
func play_idle() -> void
func play_walk() -> void
func play_run() -> void

# 跳跃动画
func play_jump_up() -> void
func play_jump_loop() -> void
func play_jump_down() -> void

# 锁链动画
func play_chain_fire(slot: int, other_slot_state: int) -> void
func play_chain_fire_right() -> void
func play_chain_fire_left() -> void
func play_chain_fire_both() -> void

func play_chain_cancel(right_active: bool, left_active: bool) -> void
func play_chain_cancel_right() -> void
func play_chain_cancel_left() -> void
func play_chain_cancel_both() -> void

# 骨骼锚点
func get_chain_anchor_position(use_right_hand: bool) -> Vector2

# 状态查询
func get_current_anim() -> StringName
func is_playing(anim_name: StringName) -> bool
func has_spine() -> bool
```

---

## 扩展指南

### 添加新动画

1. **在animator脚本中添加变量**：
```gdscript
@export_group("新动画组")
@export var anim_hurt: StringName = &"hurt"
```

2. **添加播放方法**：
```gdscript
func play_hurt() -> void:
    _play(anim_hurt, false, 0, true)  # 一次性动画，播完回idle
```

3. **在需要的地方调用**：
```gdscript
if player.animator != null:
    player.animator.play_hurt()
```

### 使用多轨道

```gdscript
# 在track 1上叠加表情动画
_play(anim_smile, true, 1, false)
```

---

## 注意事项

1. **Spine朝右**：代码假设Spine默认朝右，`facing=1`时不翻转
2. **动画名称**：可在Inspector中覆盖，无需改代码
3. **骨骼名称**：确保Spine中存在 `chain_anchor_l` 和 `chain_anchor_r`
4. **Fallback**：如果骨骼不存在，会使用Marker2D（HandL/HandR）
