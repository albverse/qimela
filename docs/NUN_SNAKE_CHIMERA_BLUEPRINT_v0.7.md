# 《修女蛇（临时代号）工程蓝图 v0.7》

> 目标：把现有需求整理为 **AI 可直接执行** 的工程规范（Godot 4.5 + GDScript + Beehave）。  
> 说明：本蓝图严格对齐当前项目硬规则（Monster / Chimera / weak / stun / chain / Beehave / EventBus）。  
> 状态：**可落地，已按本轮更新删除旧项并统一到当前决定版。**

---

## 0. 名词归一

| 需求原词 | 工程标准名 | 备注 |
|---|---|---|
| 修女蛇 | `ChimeraNunSnake`（class_name） | 场景文件：`scene/enemies/chimera_nun_snake/ChimeraNunSnake.tscn` |
| beehave | `Beehave` | 项目统一拼写 |
| ghostfist | `ghost_fist` | 与现有命名风格一致 |
| ChimeraGhostHandL | `chimera_ghost_hand_l` | 现有 `species_id` |
| eyehurtbox / eyeHurtbox | `EyeHurtbox`（节点） + `eye_hurtbox`（变量） | 统一大小写规则 |
| 光花放电事件 | `lightning_flower_release` | 对应 `LightningFlower._release_light_with_energy` |
| 石化 | `PETRIFIED` | 玩家新状态 |
| 石化追击模式 | `PETRIFIED_EXECUTION_CHASE` | 修女蛇高优先级狩猎模式 |
| 眼球阶段 | `eye_phase` | 区分眼球是否在眼窝、飞行中、返航中 |
| 开眼转场锁 | `opening_transition_lock` | 防止 reactive BT 在开眼过程反复抢占 |
| 关眼转场锁 | `closing_transition_lock` | 防止 reactive BT 在关眼过程反复抢占 |

---

## 1. 与当前项目硬规则的对齐约束

1. **实体类型必须是 Chimera**：`entity_type = EntityType.CHIMERA`。  
2. **链条链接规则走 Monster 逻辑**：默认不可直接链，只有 `weak` 或 `stunned` 可链。  
3. **除“可融合”外，行为按 Monster 攻击型敌人处理**：可攻击玩家、可受击、可进入 `weak / stun`。  
4. **Beehave 条件节点无副作用，动作节点才执行行为**。  
5. **新增事件必须通过 EventBus `emit_*` 封装发出**，禁止直接 `.emit()`。  
6. **可调参数导出到 Inspector**。  
7. **攻击判定启闭必须由 Spine 动画事件驱动**，禁止用纯定时器硬猜命中窗口。  
8. **EyeHurtbox 与主 Hurtbox 的伤害路由必须彻底分离**。  
9. **眼球子弹不走普通 projectile 伤害路由**，使用独立碰撞层与专用脚本。  
10. **状态名不直接等价于受击配置**，受击配置单独定义。  
11. **开眼 / 关眼转场期间必须启用 transition lock**。  
12. **`ground_pound` 为定点爆发型**：`GroundPoundHitbox` 为场景内常驻节点，在 `atk_hit_on` 时开启，在 `atk_hit_off` 时关闭，不持续跟随任何骨骼移动。  
13. **`OPEN_EYE` 是固定攻击链状态，不是自由待机态**：`close_to_open` 的最终帧必须直接承接 `stiff_attack`；`stiff_attack` 结束后进入 `open_eye_idle`，停留 `open_eye_idle_timeout` 后承接 `shoot_eye_start`；`GUARD_BREAK` 结束后必须立即执行 `open_eye_to_close` 返回 `CLOSED_EYE`。  
14. **当 `eye_phase != SOCKETED` 时进入 `WEAK / STUN`，统一播放 `shoot_eye_recall_weak_or_stun`，播放结束后直接进入 `weak_loop` 或 `stun_loop`。**

---

## 8. 攻击流

### 8.1 攻击A：`stiff_attack`

#### 前提
- 当前在 `OPEN_EYE`  
- 玩家在 `stiff_attack_range`  

#### 结果
- 命中玩家：`-1 HP` + `0.5s` 僵直  

#### 后续
- 若攻击正常结束且修女蛇未受击：  
  - 进入 `open_eye_idle`  
  - 停留 `open_eye_idle_timeout`  
  - 然后进入 `shoot_eye_start`  

#### stiff_attack 中 EyeHurtbox 被命中（新增优先级规则）
1. 先扣 hp。  
2. 若扣完后的 hp 达到 `weak` 阈值：**立即进入 WEAK（最高优先级）**。  
3. 若未达到 `weak` 阈值，但扣完后的 hp `<= stiff_attack_eye_hit_tail_sweep_hp_threshold`（默认 3，可调）：
   - 立即中断当前 stiff_attack 后续链，执行：
   - `open_eye_to_close → tail_sweep_transition → tail_sweep`，
   - 结束后返回 CLOSED_EYE 体系（`closed_eye_idle / closed_eye_walk` 由当下 AI 决定）。
4. 若扣完后的 hp 仍大于该阈值：
   - 按原链继续：`stiff_attack → open_eye_idle → shoot_eye_start`。

#### 优先级（高→低）
- 到达 weak 阈值 → `WEAK`  
- 未到 weak，但 hp ≤ 阈值 → 闭眼 + 尾扫反击  
- 其余情况 → 继续原攻击链  

---

## 14. 已确认决策（增补）

27. `TailSweepHitbox` 必须绑定 `bone_tail_hit`（运行时每帧同步骨骼世界坐标）。  
28. `OPEN_EYE / GUARD_BREAK` 期间链条命中应通过 `EyeHurtbox` 路由生效；主 Hurtbox 保持无效。  
29. 睁眼状态下光花放电来源统一识别 `lightning_flower / lightflower / lightning_flower_release`。  
30. `stiff_attack` 中眼部受击的中断规则以“先扣血、先判 weak、再判反击阈值”为准。
