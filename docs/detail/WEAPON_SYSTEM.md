# Weapon System -- 武器系统详解

> 源文件: `scene/components/weapon_controller.gd`
> 相关文件: `scene/components/player_animator.gd`, `scene/components/player_action_fsm.gd`, `scene/player.gd`, `scene/weapon_ui.gd`

---

## 1. 核心架构

`WeaponController` 是一个轻量级的武器管理节点, 职责边界清晰:

- **类名**: `WeaponController` (extends `Node`)
- **核心职责**: 管理武器切换、根据当前武器 + 上下文返回动画信息
- **关键约束**: WeaponController **不直接播放动画** -- 它只返回动画名与播放模式, 由 `PlayerAnimator` 统一播放

```
WeaponController          PlayerAnimator            Spine/Mock Driver
 (选择动画名)       -->   (裁决 + 播放)       -->   (底层驱动)
```

### 1.1 初始化

```gdscript
func setup(player: CharacterBody2D) -> void:
    _player = player
    _init_weapon_defs()
    current_weapon = WeaponType.CHAIN  # 默认武器: Chain
```

`setup()` 由 `Player` 在场景初始化时调用, 构建武器定义表 `_weapon_defs` 并将默认武器设为 `CHAIN`.

---

## 2. WeaponType 枚举

```gdscript
enum WeaponType { CHAIN, SWORD, KNIFE }
```

| 枚举值 | 整数值 | 说明 |
|--------|--------|------|
| `CHAIN` | 0 | 链条 -- 独立 Verlet 绳索系统, 双槽位 |
| `SWORD` | 1 | 剑 -- 轻攻击, 上下文感知动画 |
| `KNIFE` | 2 | 匕首 -- 轻攻击, 上下文感知动画 (验证扩展性的最小第三武器) |

---

## 3. 攻击模式 (AttackMode)

```gdscript
enum AttackMode {
    OVERLAY_UPPER,      # 上半身叠加 (Chain)
    OVERLAY_CONTEXT,    # 上半身叠加 + context 选择 (Sword/Knife)
    FULLBODY_EXCLUSIVE  # 全身独占 (重攻击/特殊武器)
}
```

| 模式 | 整数值 | Track 行为 | 适用武器 |
|------|--------|-----------|---------|
| `OVERLAY_UPPER` | 0 | Track1 叠加, 不影响 Track0 locomotion | Chain |
| `OVERLAY_CONTEXT` | 1 | Track1 叠加 + 根据上下文选择不同动画 | Sword, Knife |
| `FULLBODY_EXCLUSIVE` | 2 | 清空所有轨道, 全身动画替换 Track0 | 预留 (重攻击/特殊武器) |

这三种模式在 `PlayerAnimator` 中有对应的常量镜像 (避免循环依赖):

```gdscript
# player_animator.gd
const MODE_OVERLAY_UPPER: int = 0
const MODE_OVERLAY_CONTEXT: int = 1
const MODE_FULLBODY_EXCLUSIVE: int = 2
```

---

## 4. 武器分类架构 -- 设计哲学

这是添加新武器时**最重要的设计判断**:

### 4.1 适合 ActionFSM 的武器 (一次性动作武器)

**核心特征**: 一次性动作, 生命周期短, 有清晰的 开始 / 窗口 / 结束, 动画结束后不在世界中留下持续逻辑.

| 武器 | 攻击模式 | 动画选择 | lock_anim_until_end |
|------|---------|---------|---------------------|
| Sword | `OVERLAY_CONTEXT` | 根据 context 选择 (`ground_idle` / `ground_move` / `air`) | `false` -- 允许 context 变化时切换动画 |
| Knife | `OVERLAY_CONTEXT` | 根据 context 选择 (`ground_idle` / `ground_move` / `air`) | `true` -- 起手后锁定不变 |

**生命周期**: `输入 -> ActionFSM 状态切换 -> Animator 播放 -> 动画结束 -> ActionFSM 回到 None`

### 4.2 不适合 ActionFSM 的武器 (持续系统武器)

**核心原则**: "不是一次性动作, 而是持续存在的系统 / 独立实体 / 跨状态的长生命周期事物"

| 武器 | 攻击模式 | 特殊性 |
|------|---------|-------|
| Chain | `OVERLAY_UPPER` | 独立 Verlet 绳索系统, 双槽位 (R/L), LINKED 状态可无限期持续 |

Chain 的动画播放有两条路径:
1. **ActionFSM 路径**: 正常 `Attack_R` / `Attack_L` 状态触发 (通过 Animator tick)
2. **手动路径**: `PlayerChainSystem` 直接调用 `PlayerAnimator.play_chain_fire()`, 设置 `_manual_chain_anim = true` 标志, 使动画不受 ActionFSM 状态清理影响

### 4.3 新武器判断准则

> **当你要添加一个新武器时, 首先问自己这个问题:**
>
> "这个武器在动画结束时就结束了, 还是会在世界中持续存在?"
>
> - 动画结束即结束 --> **ActionFSM 武器** (像 Sword, Knife)
> - 持续存在 --> **需要独立系统**, 绕过 ActionFSM (像 Chain)

---

## 5. 武器定义表 (_weapon_defs)

`_init_weapon_defs()` 在 `setup()` 时构建, 是一个 `WeaponType -> Dictionary` 的映射:

### 5.1 Chain 定义

```gdscript
_weapon_defs[WeaponType.CHAIN] = {
    "name": "Chain",
    "attack_mode": AttackMode.OVERLAY_UPPER,
    "lock_anim_until_end": true,
    "anim_map": {
        # context -> side -> anim_name
        "ground_idle": { "R": "chain_R", "L": "chain_L" },
        "ground_move": { "R": "chain_R", "L": "chain_L" },
        "air":         { "R": "chain_R", "L": "chain_L" },
    },
    "cancel_anim": {
        "R": "anim_chain_cancel_R",
        "L": "anim_chain_cancel_L",
    }
}
```

**要点**:
- `anim_map` 结构为 `context -> side -> anim_name` (二层嵌套, 因为 Chain 区分左右手)
- 所有 context 下动画相同 -- Chain 的动画与移动状态无关, 只看左右手
- `lock_anim_until_end = true` -- 起手后不随 context 变化而切换
- `cancel_anim` 按 side 区分

### 5.2 Sword 定义

```gdscript
_weapon_defs[WeaponType.SWORD] = {
    "name": "Sword",
    "attack_mode": AttackMode.OVERLAY_CONTEXT,
    "lock_anim_until_end": false,
    "anim_map": {
        # context -> anim_name (无需 side)
        "ground_idle": "sword_light_idle",
        "ground_move": "sword_light_move",
        "air":         "sword_light_air",
    },
    "cancel_anim": {
        "any": "",  # Sword 暂无 cancel 动画
    }
}
```

**要点**:
- `anim_map` 结构为 `context -> anim_name` (单层, 不区分 side)
- `lock_anim_until_end = false` -- 允许 context 变化时动态切换动画 (例如从地面跳到空中, 动画跟随变化)
- 没有 cancel 动画

### 5.3 Knife 定义

```gdscript
_weapon_defs[WeaponType.KNIFE] = {
    "name": "Knife",
    "attack_mode": AttackMode.OVERLAY_CONTEXT,
    "lock_anim_until_end": true,
    "anim_map": {
        "ground_idle": "knife_light_idle",
        "ground_move": "knife_light_move",
        "air":         "knife_light_air",
    },
    "cancel_anim": {
        "any": "",  # Knife 暂无 cancel 动画
    }
}
```

**要点**:
- 结构与 Sword 完全一致 (验证扩展性)
- `lock_anim_until_end = true` -- 与 Sword 不同, 起手后锁定
- 作为最小第三武器, 验证了 WeaponController 的三武器扩展能力

---

## 6. 核心 API

### 6.1 attack(context, side) -> Dictionary

根据当前武器 + context + side 返回动画信息:

```gdscript
func attack(context: String, side: String = "R") -> Dictionary:
    # 返回: { "mode": AttackMode, "anim_name": String, "lock_anim": bool }
```

**内部逻辑**:

```
match mode:
    OVERLAY_UPPER:
        # Chain: anim_map[context][side] -- 二层查找
        anim_name = anim_map[context][side]

    OVERLAY_CONTEXT / FULLBODY_EXCLUSIVE:
        # Sword/Knife: anim_map[context] -- 单层查找
        anim_name = anim_map[context]
```

**调用方**: `PlayerAnimator.tick()` 在处理 `Attack_R` / `Attack_L` 状态时调用:

```gdscript
# player_animator.gd (tick 中)
elif action_state in [&"Attack_R", &"Attack_L"]:
    var context: String = _compute_context()
    var side: String = "R" if action_state == &"Attack_R" else "L"
    var result: Dictionary = _weapon_controller.attack(context, side)
```

### 6.2 cancel(side) -> Dictionary

获取当前武器的取消动画:

```gdscript
func cancel(side: String = "R") -> Dictionary:
    # 返回: { "anim_name": String }
```

**内部逻辑**:
- `OVERLAY_UPPER` 模式: 按 side 查 `cancel_anim` ("R" / "L")
- 其他模式: 查 `cancel_anim["any"]`

**调用方**: `PlayerAnimator.tick()` 在处理 `AttackCancel_R` / `AttackCancel_L` 状态时调用.

### 6.3 switch_weapon()

循环切换到下一个武器:

```gdscript
func switch_weapon() -> void:
    # Chain -> Sword -> Knife -> Chain (循环)
    match current_weapon:
        WeaponType.CHAIN: current_weapon = WeaponType.SWORD
        WeaponType.SWORD: current_weapon = WeaponType.KNIFE
        WeaponType.KNIFE: current_weapon = WeaponType.CHAIN
        _:                current_weapon = WeaponType.CHAIN
```

切换后通过 `_player.log_msg()` 记录日志. 注意: 此方法**只修改 `current_weapon`**, 不做任何清理 -- 清理工作由 `ActionFSM.on_weapon_switched()` 完成.

### 6.4 get_weapon_name() -> String

返回当前武器名称字符串 (用于日志和 UI):

```gdscript
func get_weapon_name() -> String:
    return _weapon_defs.get(current_weapon, {}).get("name", "?")
```

---

## 7. Context 计算 (_compute_context)

Context 由 `PlayerAnimator._compute_context()` 计算, 不在 WeaponController 中:

```gdscript
# player_animator.gd
func _compute_context() -> String:
    if not _player.is_on_floor():
        return "air"

    if _player.movement != null:
        var intent: int = _player.movement.move_intent
        if intent == 0:   # MoveIntent.NONE
            return "ground_idle"
        else:
            return "ground_move"

    return "ground_idle"
```

| 条件 | Context |
|------|---------|
| 玩家不在地面 | `"air"` |
| 在地面 + `MoveIntent.NONE` | `"ground_idle"` |
| 在地面 + `MoveIntent.WALK` 或 `MoveIntent.RUN` | `"ground_move"` |

---

## 8. 武器切换完整流程 (Z 键)

### 8.1 切换顺序

```
CHAIN (0) --> SWORD (1) --> KNIFE (2) --> CHAIN (0)
```

### 8.2 完整调用链

```
player._unhandled_input() -- Z 键按下
  |
  +--> weapon_controller.switch_weapon()
  |      修改 current_weapon (CHAIN -> SWORD -> KNIFE -> CHAIN)
  |      记录日志
  |
  +--> action_fsm.on_weapon_switched()
         |
         +-- [守卫] state == DIE 时直接返回, 不允许切换
         |
         +-- 清空 _pending_fire_side
         |
         +-- chain_sys.force_dissolve_all_chains()
         |     溶解所有链条 (包括 LINKED 状态的)
         |     相当于自动按了 X 键
         |
         +-- animator.force_stop_action()
         |     清空 _cur_action_anim
         |     停止 Track1 动画
         |
         +-- 清空 attack_side
         |
         +-- _do_transition(State.NONE, "weapon_switched", 99)
               硬切回 None 状态 (优先级 99, 几乎不会被阻止)
```

### 8.3 关键设计决策

**为什么要 dissolve 所有链条?**

切换武器时执行 `force_dissolve_all_chains()`, 包括处于 `LINKED` 状态的链条. 这等价于自动按了 X (取消键). 设计原因:

- 切换到 Sword/Knife 后, Chain 系统不再接收输入
- 残留的 LINKED 链条如果不清理, 会产生孤儿状态
- 这是最简单且最稳定的方案 (对应规范中的 "Q3: 选项A")

**为什么要 `force_stop_action()`?**

```gdscript
# player_animator.gd
func force_stop_action() -> void:
    _cur_action_anim = &""
    if _driver != null:
        _driver.stop(TRACK_ACTION)
```

防止切换武器后, Track1 上仍在播放旧武器的动画 (例如 `chain_R` 动画残留).

---

## 9. 动画结束事件映射

`PlayerAnimator` 中定义了所有武器动画的结束事件映射:

```gdscript
# player_animator.gd
const ACTION_END_MAP: Dictionary = {
    # Chain 动画
    &"chain_R":              &"anim_end_attack",
    &"chain_L":              &"anim_end_attack",
    &"anim_chain_cancel_R":  &"anim_end_attack_cancel",
    &"anim_chain_cancel_L":  &"anim_end_attack_cancel",
    # Sword 动画
    &"sword_light_idle":     &"anim_end_attack",
    &"sword_light_move":     &"anim_end_attack",
    &"sword_light_air":      &"anim_end_attack",
    # Knife 动画
    &"knife_light_idle":     &"anim_end_attack",
    &"knife_light_move":     &"anim_end_attack",
    &"knife_light_air":      &"anim_end_attack",
    # ...
}
```

所有攻击动画结束后都派发 `anim_end_attack`, 由 `ActionFSM.on_anim_end_attack()` 处理状态回归.

---

## 10. Chain 的手动动画机制 (_manual_chain_anim)

Chain 作为持续系统武器, 有一套独立于 ActionFSM 的动画播放路径:

### 10.1 play_chain_fire(slot_idx)

```gdscript
# player_animator.gd
func play_chain_fire(slot_idx: int) -> void:
    # 死亡态硬闸: 不允许触发 chain 动画覆盖 die
    if _player.get_action_state() == &"Die":
        return
    if _player.health != null and _player.health.hp <= 0:
        return

    var anim_name: StringName = &"chain_R" if slot_idx == 0 else &"chain_L"
    _driver.play(TRACK_ACTION, anim_name, false)
    _cur_action_anim = anim_name
    _cur_action_mode = MODE_OVERLAY_UPPER
    _manual_chain_anim = true  # 标记为手动播放, 防止 tick 清理
```

**`_manual_chain_anim` 标志的作用**:

在 `PlayerAnimator.tick()` 中, 当 `action_state == "None"` 时, 正常逻辑会清理 Track1. 但如果 `_manual_chain_anim == true`, 则跳过清理:

```gdscript
# player_animator.gd (tick 中)
if action_state == &"None":
    if _manual_chain_anim:
        pass  # chain 动画独立运行, 不受 ActionFSM 控制
    elif _cur_action_anim != &"":
        # 正常清理逻辑...
```

### 10.2 play_chain_cancel(right_active, left_active)

```gdscript
func play_chain_cancel(right_active: bool, left_active: bool) -> void:
    # 根据活跃的槽位选择 cancel 动画
    var anim_name: StringName = &""
    if right_active:
        anim_name = &"anim_chain_cancel_R"
    elif left_active:
        anim_name = &"anim_chain_cancel_L"

    _manual_chain_anim = true
    _driver.play(TRACK_ACTION, anim_name, false)
```

### 10.3 手动动画标志的清除时机

`_manual_chain_anim` 在以下时机被清除:

1. **动画自然结束**: `_on_anim_completed()` 中检测到 chain 相关动画完成
2. **Die 状态强制清除**: `tick()` 中 `action_state == "Die"` 时立即 `_manual_chain_anim = false`

```gdscript
# _on_anim_completed 中
if anim_name in [&"chain_R", &"chain_L", &"anim_chain_cancel_R", &"anim_chain_cancel_L"]:
    _manual_chain_anim = false
```

---

## 11. 武器 UI (WeaponUI)

`scene/weapon_ui.gd` 提供屏幕左上角的武器名称显示:

```gdscript
# weapon_ui.gd
class_name WeaponUI  # extends CanvasLayer

func update_display() -> void:
    var weapon_name: String = _player.weapon_controller.get_weapon_name()
    _weapon_label.text = "Weapon: %s" % weapon_name
```

- 每帧 `_process()` 中调用 `update_display()` 更新显示
- 自动查找 `player` 组中的 Player 节点
- 如果找不到 Label 节点, 会动态创建一个 (白色文字, 黑色描边, 字号 24)

---

## 12. 双轨播放架构 (Track0 / Track1)

武器动画的播放由 `PlayerAnimator` 的双轨架构支撑:

```
Track0 (TRACK_LOCO = 0): locomotion 动画, 永远跟随 locomotion_state
Track1 (TRACK_ACTION = 1): action overlay 动画, 武器攻击/取消等
```

### 12.1 各模式的轨道使用

| 模式 | Track0 | Track1 | 说明 |
|------|--------|--------|------|
| `OVERLAY_UPPER` | 正常播放 locomotion | 播放攻击动画 | 移动 + 攻击同时进行 |
| `OVERLAY_CONTEXT` | 正常播放 locomotion | 播放攻击动画 (根据 context) | 移动 + 攻击同时进行, 动画跟随状态 |
| `FULLBODY_EXCLUSIVE` | 被攻击动画替换 | 不使用 | 全身独占, locomotion 暂停 |

### 12.2 FULLBODY_EXCLUSIVE 的恢复

当 FULLBODY 动画结束后, `_on_anim_completed()` 负责恢复:

```gdscript
# 动画完成 -> 清空 action 状态 -> 让 tick 重新评估 loco
_cur_action_anim = &""
_cur_action_mode = -1
_cur_loco_anim = &""  # 强制下一帧重新播放 locomotion
```

---

## 13. Profile 系统 (未来规划)

> 参考: `docs/AI_Animation_Spec_Pack_/11_WEAPON_ANIM_PROFILE_SPEC（武器写法）.md`

当前代码中**尚未实现** Profile 系统. 以下是规划要点:

### 13.1 核心概念

Profile = "一套完整动作集 + 一套外观配置 + 一套切换策略"

```
profile_id: DEFAULT / KATANA / CHAIN / ...
  |- visual: skin_name, attachments
  |- loco_set: Idle/Walk/Run/Jump... -> anim_name (每武器一套)
  |- action_set: AttackLight/AttackHeavy/Guard... -> anim_name (每武器一套)
  |- policy: 切换策略
```

### 13.2 核心原则

1. Profile **不是状态机状态** -- LocomotionFSM / ActionFSM 不新增 "持刀Idle" 等状态
2. Profile **只影响 Animator 的映射选择**: `profile_id + locomotion_state -> anim_name`
3. **只有 Animator 播放动画** -- profile 切换只改变映射表来源
4. Hurt/Die 永远优先, profile 切换不得阻止 Hurt/Die

### 13.3 推荐切换策略: QUEUE_UNTIL_ACTION_END

Z 键切换在动作中会写入 `pending_profile_id`, 等 Action 结束时执行切换:

| 策略 | 行为 | 推荐度 |
|------|------|--------|
| `ONLY_WHEN_ACTION_NONE` | 动作中 Z 无效 | 最简单但手感硬 |
| `QUEUE_UNTIL_ACTION_END` | 动作中排队, 结束后切 | **推荐** |
| `FORCE_CANCEL_ACTION_THEN_SWITCH` | 强制取消当前动作再切 | 风险较高 |

### 13.4 预计代码改动点

- `weapon_controller.gd`: 新增 `current_profile_id`, `pending_profile_id`, `request_switch_profile()`
- `player_animator.gd`: `LOCO_ANIM` 升级为 `LOCO_ANIM_BY_PROFILE[profile_id][loco_state]`
- `player_action_fsm.gd`: Action 完成时应用 pending profile
- `player.gd`: Z 键改为调用 `request_switch_profile()`

---

## 14. 添加新武器的操作清单

### 步骤 1: 判断武器类型

- 动画结束即结束? --> ActionFSM 武器 (参考 Sword/Knife)
- 持续存在? --> 独立系统武器 (参考 Chain)

### 步骤 2: 在 WeaponType 枚举中添加

```gdscript
enum WeaponType { CHAIN, SWORD, KNIFE, NEW_WEAPON }
```

### 步骤 3: 在 _init_weapon_defs() 中添加定义

```gdscript
_weapon_defs[WeaponType.NEW_WEAPON] = {
    "name": "NewWeapon",
    "attack_mode": AttackMode.OVERLAY_CONTEXT,  # 或其他模式
    "lock_anim_until_end": true,
    "anim_map": {
        "ground_idle": "new_weapon_light_idle",
        "ground_move": "new_weapon_light_move",
        "air":         "new_weapon_light_air",
    },
    "cancel_anim": {
        "any": "",
    }
}
```

### 步骤 4: 更新切换循环

```gdscript
# switch_weapon() 中
match current_weapon:
    WeaponType.CHAIN:      current_weapon = WeaponType.SWORD
    WeaponType.SWORD:      current_weapon = WeaponType.KNIFE
    WeaponType.KNIFE:      current_weapon = WeaponType.NEW_WEAPON  # 插入
    WeaponType.NEW_WEAPON: current_weapon = WeaponType.CHAIN       # 回环
```

### 步骤 5: 在 PlayerAnimator 中注册动画结束映射

```gdscript
# player_animator.gd ACTION_END_MAP 中添加
&"new_weapon_light_idle": &"anim_end_attack",
&"new_weapon_light_move": &"anim_end_attack",
&"new_weapon_light_air":  &"anim_end_attack",
```

### 步骤 6: 验证

- 切换到新武器, 确认 UI 显示正确
- 在 ground_idle / ground_move / air 三种 context 下攻击, 确认动画正确
- 攻击中切换武器, 确认不残留旧动画
- 受击 / 死亡时确认 Hurt/Die 正常抢占
