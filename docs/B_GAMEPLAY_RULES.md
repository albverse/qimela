# B_GAMEPLAY_RULES.md（玩法规则，2026-02-02更新）

> 只在 Router 触发 B 时阅读。

---

## 1. 输入系统

| 功能 | action名 | 按键 | 状态 |
|------|---------|------|------|
| 移动左 | move_left | A | ✅ |
| 移动右 | move_right | D | ✅ |
| 跳跃 | jump | W | ✅ |
| 发射锁链 | (鼠标事件) | 鼠标左键 | ✅ |
| 取消锁链 | cancel_chains | X | ✅ |
| 融合 | fuse | Space | ✅ |
| 使用回血精灵 | use_healing | C | ✅ |
| 治愈精灵大爆炸 | healing_burst | Q | ✅ |
| 武器切换 | (无action) | Z | ✅ |

---

## 2. 锁链系统 ✅

### 状态机
```
IDLE → FLYING → STUCK/LINKED → DISSOLVING → IDLE
```

### 视觉约束
- Line2D 的 width/texture/gradient 由 Inspector 控制，脚本不重置
- 溶解：tween `shader_parameter/burn`
- shader 路径：`res://shaders/chain_sand_dissolve.gdshader`

### 断裂预警
- 接近最大长度时颜色渐变为红色
- warn_start_ratio: 0.80
- warn_color: (1.0, 0.259, 0.475)

---

## 3. 状态系统 ✅

### weak（虚弱）
- 触发：HP ≤ weak_hp
- 表现：停止移动
- 锁链交互：可进入 LINKED 状态
- 结束：恢复移动 + HP 回满 + 所有链 slot 溶解

### stun（眩晕）
- 触发：被雷花 HurtArea 命中 / 被链命中
- 表现：停止移动
- 锁链交互：眩晕期间被链命中可链接
- 眩晕期间可融合
- 结束：恢复移动

---

## 4. 玩家HP系统 ✅

- 最大HP：5心
- UI：空心为底，满心裁剪层
- 受击：扣心 + 0.1s无敌 + 击退 + 短时禁输入

---

## 5. 回血精灵 ✅

### 收集
- 靠近自动吸附（150px范围）
- 锁链命中立即吸附
- 最多携带3只

### 使用
- 按 C 键消耗1只
- 每只回复2心

### 行为
- 状态机：IDLE_IN_WORLD → ACQUIRE → ORBIT → CONSUMED
- 环绕玩家，3只各有不同center点
- 跳跃时有0.3秒滞后

### 治愈精灵大爆炸（Q）
- 触发条件：必须满 3/3 治愈精灵
- 触发后：清空并消耗全部精灵
- 范围：Player/HealingBurstArea 内 MonsterBase 进入眩晕（按各怪 healing_burst_stun_time）
- 全局事件：`EventBus.healing_burst(light_energy)`，默认能量 5.0

---

## 6. 天气系统 ✅

### 雷击（thunder_burst）
- 定义为"一次事件"（非持续态）
- 触发点：动画 Call Method Track 调用 `anim_emit_thunder_burst()`
- 全局广播：EventBus.thunder_burst

### 雷花（LightningFlower）
- 能量：0-5格，每格对应不同贴图
- 雷击：能量+1
- 满能量：自动释放光照
- 锁链命中：释放当前能量的光照
- 光照时间 = 能量 × light_time_per_energy

---

## 7. 怪物光照系统 ✅

### 飞怪（MonsterFly）
- 隐身态：visible_time ≤ 0
  - 不可见
  - collision_layer = 0（不可被锁链命中）
  - 仍可移动、碰墙
- 显形：雷击/光照增加 visible_time
- visible_time 归零后立即隐身，断开所有链接

### LightReceiver
- 用于让隐身怪物仍能接收光照
- collision_layer/mask = 16 (ObjectSense)

---

## 8. 融合系统 ✅

### UI预览
- SUCCESS → ui_yes（绿色勾）
- REJECTED → ui_no（红色叉）
- 其他失败 → ui_die（骷髅）

### 融合条件
- 两条锁链都处于 LINKED 状态
- 链接目标都是 MonsterBase
- 两个目标都处于 weak 或 stun 状态
- 不是同一个目标

### 眩晕融合
- 眩晕状态的怪物可以参与融合
- 融合时检查 is_weak_or_stunned()

详见 D_FUSION_RULES.md

---

## 9. 奇美拉行为 ✅

> **注意：** 并非所有奇美拉都能被锁链链接或跟随玩家。
> 不同奇美拉有各自独立的行为规则，需分别定义。

### ChimeraA（跟随型）
- 可被锁链链接（on_chain_hit 返回 1）
- 链接后跟随玩家移动
- 被锁链命中：闪白 + 跟随链接槽对应的手

### ChimeraStoneSnake（攻击型，不可链接）
- **无法被锁链链接**（on_chain_hit 返回 0）
- **不跟随玩家**（follow_player_when_linked = false）
- 定时发射子弹攻击玩家
- 子弹命中玩家：造成僵直效果（Player.apply_stun），不扣血
- 属于具有攻击性的奇美拉，不适用"命中后跟随"的通用规则

### 奇美拉互动（计划中）
- 接口：`ChimeraBase.on_player_interact(player: Player)`
- 触发：当玩家活跃槽位链接了奇美拉时，左键优先触发互动
- 各子类需要重写此方法实现具体互动效果

---

## 10. HurtArea 伤害链路 ✅

雷花 HurtArea：
- 伤害玩家：1点
- Walk怪：眩晕（不掉血）
- Fly怪：免疫（不受伤害）
