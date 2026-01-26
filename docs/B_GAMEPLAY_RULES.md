# B_GAMEPLAY_RULES.md（玩法规则模块，2026-01-26）

> 只在 Router 触发 C 时阅读。  
> 这里写的都是“必须保持”的规则，避免模型自作主张改动系统行为。

---

## 1) 输入与锁链（核心）
- W：跳跃
- 鼠标左键：发射锁链
- X：取消锁链（正式功能，已实现；**取消也属于锁链物理逻辑**，应走溶解/消失流程，不是简单 free）
- C：使用回血精灵（待办）

---

## 2) 锁链视觉/溶解约束（必须保持）
- Line2D 的 width/texture/gradient 由 Inspector 控制，脚本不得重置
- burn 溶解：tween `shader_parameter/burn`
- shader 路径固定：`res://shaders/chain_sand_dissolve.gdshader`

---

## 3) 状态：weak 与 stun 必须区分（保持现状）
- weak（用于链接/融合）
  - 结束：恢复移动、HP 回满、所有链 slot 溶解消失（保持现状）
- stun（例如雷花 Hurt）
  - 眩晕结束：恢复移动
  - **眩晕期间被锁链命中/链接，不应立刻解除眩晕**

---

## 4) 玩家 HP 与受击（已完成）
- 5 心 UI：空心为底，满心裁剪层；数值变化立即刷新
- 受击：扣心 + 0.1s 无敌 + 击退 + 短时禁输入（参数化）

---

## 5) 天气：雷击 thunder_burst（已完成）
- 打雷定义为“一次事件” thunder_burst（非持续态）
- 触发点：打雷动画开始或指定帧（按当前实现）

---

## 6) 雷花（LightningFlower）（已完成，必须保持）
### 6.1 能量与贴图（0–5）
- 0：`res://art/lightflower/lightflower_0.png`
- 1：`res://art/lightflower/lightflower_1.png`
- 2：`res://art/lightflower/lightflower_2.png`
- 3：`res://art/lightflower/lightflower_3.png`
- 4：`res://art/lightflower/lightflower_4.png`
- 5：`res://art/lightflower/lightflower_5.png`
能量变化必须立即刷新贴图（禁止延迟刷新）。

### 6.2 释放与连锁
1) 自身能量立刻清零（贴图立刻变 0）
2) 强光：强度 +10 → tween 到 0
3) 周围花能量 +1（上限 5），满能可继续连锁（按实现）

### 6.3 光照事件统一设计（必须）
- 雷击：全局广播（EventBus）
- 光照：光花主动 `get_overlapping_areas()` → 对怪物调用 `on_light_exposure(...)`

### 6.4 锁链触发释放（已完成）
- `on_chain_hit()` 成功释放返回 1
- interacted 去重：只有返回非 0 才标记
- 删除 `_is_emitting` 的二次触发拦截，使用 `_emit_id` 处理并发

---

## 7) LightReceiver（与 zip 对齐）
### 7.1 目的
让“隐身态不可被锁链命中”的飞怪仍可被光照系统识别并累加显形能量。

### 7.2 MonsterFly.tscn 真实配置
- 节点：`LightReceiver (Area2D)`（脚本：`res://scene/LightReceiver.gd`）
- 碰撞（注意：必须写 bitmask + 注释）：
```gdscript
collision_layer = 16  # ObjectSense(5) / Inspector 第5层
collision_mask  = 16  # ObjectSense(5) / Inspector 第5层
```
- 形状：CircleShape2D 半径 ≈ 61.008（Inspector 约 61）
  - **允许浮动**：不是硬约束，只要稳定覆盖怪物并能被光花检测到即可

---

## 8) MonsterFly 潜行/显形（已实现）
- 显形条件：雷击或光照
- 隐身态（visible_time <= 0）：
  - 仍移动、仍碰墙（is_on_wall 有效）
  - 不可被锁链命中：`collision_layer = 0`
  - 仍可接收光照：通过 LightReceiver
- visible_time 归零后立即隐身，无昏迷时间

---

## 9) HurtArea 伤害链路（已完成）
- 雷花 HurtArea：可伤害玩家与 walk 类怪（fly 默认不受影响）
- walk：被 Hurt 进入眩晕，不掉血

---

## 10) 当前未完成（真实待办）
- 锁链槽位 UI（AB 槽）：未完成
- 回血精灵：未完成
