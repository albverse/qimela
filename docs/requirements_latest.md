# 功能需求与实现约束（最新版 v1.1，2026-01-25）

> 本文件优先级最高：若与旧 ZIP 内任何 MD 冲突，以本文件为准。  
> 目标：把已确认需求、关键约束、完成进度、待办事项统一收敛为“可验收清单”。

---

## A. 硬约束（不得擅自改动）

### A1. 引擎/写法
- 引擎：Godot 4.5
- 代码风格：使用 Godot 4.5 的最新 API/写法；不确定的 API 必须先查官方文档再写（尤其是 PhysicsQuery/Control 属性）。

### A2. 锁链（Chain）整体表现
- 视觉：Line2D 的 `width/texture/gradient` 由 Inspector 决定，脚本 **不得重置**。
- 溶解：使用 burn shader 的 `shader_parameter/burn` tween；每条链单独持有 ShaderMaterial，避免串台。
- 动效：保持原版 Verlet + 波动叠加（rope_segments / stiffness / iterations / wave_amp 等沿用既定参数）。

### A3. “弱化（weak，可锁链链接）”与“眩晕（stun）”必须区分
- **weak**：原本用于链链接/融合的状态。弱化结束：恢复移动、HP 回满、所有链 slot 溶解消失（保持原逻辑）。
- **stun**：例如被雷花 Hurt 到的眩晕。眩晕结束：恢复移动。  
  **眩晕期间被锁链命中/链接，不应立刻解除眩晕**（必须像“普通眩晕”一样仍不可移动）。

---

## B. UI：心形生命值（已完成）
- 贴图：`heart_full_texture` / `heart_empty_texture` 两张 PNG。
- 表现：空心为底，满心作为裁剪层；数值变化时满心裁剪比例立即刷新。
- 对齐：两张贴图必须像素对齐（布局 anchors/offset 固定，避免伸缩模式不一致）。

---

## C. 玩家受击/击退（已完成）
- 受击时：短时间锁定水平输入 + 强推（击退），并有“禁止输入”的持续时间可调。
- 可调参数位置：玩家受击模块/Health 模块中应暴露 `input_lock_time`（或同义变量）用于调节禁止输入时长。

---

## D. 天气雷电间隔（已完成）
- 当前实现：支持最小/最大间隔（你已将 min 改为 2 秒并验收通过）。
- 约束：保持该设计，不再改成 0~5 的随机（已确认放弃）。

---

## E. HurtArea 同时伤害玩家与怪物（已完成）
- HurtArea 可以伤害：
  - 玩家
  - 除飞怪以外的怪物（例如 walk 怪）
- 对 walk 怪：被雷花 Hurt 到后进入**眩晕**（不掉血）。
- 对飞怪：默认不受该 HurtArea 影响（如未来需要，再加白名单/组）。

---

## F. FlowerSense → ObjectSense（已完成并更名）
### F1. 命名
- 将 FlowerSense 更名为 **ObjectSense**，作为通用“可感知/可交互物体”的碰撞/感知层。

### F2. 雷花能量与贴图映射（必须即时反映）
- 能量范围：0~5
- 贴图路径（按 energy 索引）：
  - 0：`res://art/lightflower/lightflowe_0r.png`（注意：文件名你提供为此拼写）
  - 1：`res://art/lightflower/lightflower_1.png`
  - 2：`res://art/lightflower/lightflower_2.png`
  - 3：`res://art/lightflower/lightflower_3.png`
  - 4：`res://art/lightflower/lightflower_4.png`
  - 5：`res://art/lightflower/lightflower_5.png`
- **关键约束**：能量变化必须立即刷新贴图，不允许出现“下一次雷电才刷新”的延迟。

### F3. 能量释放规则（连锁反应）
- 任意一朵花释放能量：
  1) 自身能量立刻清零（贴图立刻变 0）
  2) 触发强光：发光强度 = 当前强度 + 10，然后立刻 tween 到 0
  3) 周围花接收辐射：能量 +1（上限 5），若因此达到满能量则可触发进一步连锁释放（按当前实现的链式规则）

---

## G. 锁链与雷花：交互存在，但不允许“阻挡链”
### G1. 目标
- 玩家在花丛里依然能正常射链（花不能在任何意义上“挡链”）。
- 但锁链仍可触发雷花的交互逻辑（`on_chain_hit` 等）。

### G2. 推荐实现（两条 Ray：阻挡 vs 交互）
- Ray A（block）：只检测 world/enemy 等**真正阻挡锁链**的对象。
- Ray B（interact）：只检测 ObjectSense/ChainInteract 层的 Area2D，用于触发 `on_chain_hit`，但**不会作为阻挡**。
- 两条 Ray 都从 prev_pos → end_pos；若两者同时命中，以距离近者决定是否触发交互，但最终阻挡仍由 Ray A 决定。

### G3. Mask 的 Inspector 勾选必须可用
- 所有 `chain_hit_mask / chain_interact_mask` 一律用：
  `@export_flags_2d_physics var xxx_mask: int = 0` citeturn0search4  
  禁止要求用户手填数字（避免 bitmask 误会）。citeturn0search3

---

## H. 当前完成进度（以“你已验收”为准）
- ✅ 心形 UI（对齐已修复）
- ✅ 玩家受击击退 + 输入锁定（并可调）
- ✅ 雷花能量贴图即时刷新
- ✅ 能量释放立即清零 + 强光 tween
- ✅ 花能量连锁反应（已验收）
- ✅ walk 怪被雷花 Hurt → 眩晕而非掉血
- ✅ 锁链与花交互存在，但花不再阻挡锁链（已验收）
- ✅ 输入/类型/函数命名相关报错已逐一修复

---

## I. 待办/风险点（建议你用“验收测试”锁死）
1) **把本次已实现的脚本与场景**确认都已打包/提交（你上传的旧 ZIP 里可能不包含最新雷花/心形 UI 相关脚本；建议你以后打包时包含新增脚本与 .tscn/.tres）。  
2) 碰撞层命名表（World(1)、EnemyBody(3) 等）请在项目里固定，后续所有文档与脚本统一引用“层名+层号”。  
3) 若未来新增更多可交互物体：统一走 ObjectSense + Ray B 交互路线，避免再出现“交互层挡链”。

