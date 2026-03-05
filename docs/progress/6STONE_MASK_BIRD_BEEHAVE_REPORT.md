# StoneMaskBird Beehave 行为与动画梳理（基于当前代码）

> 参照：`docs/SPINE_GODOT_LATEST_INTEGRATED_STANDARD.md` 的“由叶节点统一调用动画接口（避免直连 Spine）”约束，本文仅按 `anim_play()` 逻辑描述行为-动画映射。

## 1) 行为树总优先级（从高到低）

1. `STUNNED`：`Act_StunnedFallLoop`
2. `WAKE_FROM_STUN`：`Act_WakeFlyReturnRest`
3. `HURT`：`Act_HurtKnockbackFlicker`
4. `WAKING`：`Act_WakeUpUninterruptible`
5. `RETURN_TO_REST`：`Act_ReturnToRest`
6. `FLYING_ATTACK`：`ShootFace` / `AttackLoopDash` / `ChasePlayer`（同级内部按条件选择）
7. `HUNTING`：`Act_HuntWalkMonster`
8. `REPAIRING`：`Act_RepairRestArea`
9. `RESTING`：`Act_RestingLoop`

## 2) 每个行为下的动画状态

### A. RESTING（休息）
- 行为：`act_resting_loop.gd`
- 动画：常驻 `rest_loop`（循环）。
- 退出：
  - 玩家触发 wake 请求 → `mode=WAKING`（下一行为由 `Act_WakeUp` 处理）；
  - `rest_hunt_requested=true` 也同样走 `WAKING`。

### B. WAKING（起床）
- 行为：`act_wake_up.gd`
- 动画：`wake_up`（非循环、不可打断语义）。
- 结束后分流：
  - 若 `rest_hunt_requested=true` → `mode=HUNTING`；
  - 否则 → `mode=FLYING_ATTACK`，并开启攻击时窗（`attack_until_sec`）。

### C. FLYING_ATTACK（空中战斗）

#### C1. ShootFace 分支（有面具且玩家在发射范围）
- 行为：`act_shoot_face.gd`
- 动画流：
  - 靠近悬停点：`fly_move`（循环）；
  - 到位后：`shoot_face`（非循环，等待 Spine 事件 `shoot` 执行发射）；
  - 发射后：`has_face=false`，回到飞行流程。

#### C2. Dash 分支（冲刺攻击循环）
- 行为：`act_attack_loop_dash.gd`
- 动画流：
  - 冷却/待机：`fly_idle`（循环）；
  - 起冲：`dash_attack`（非循环）；
  - 回拉：`dash_return`（非循环）；
  - 完成后回到 `fly_idle`，等待下一次冷却结束。

#### C3. Chase 分支（追击）
- 行为：`act_chase_player.gd`
- 动画：
  - 有位移：`fly_move`（循环）；
  - 接近或等待：`fly_idle`（循环）。
- 可能切换到：`RETURN_TO_REST` / `HUNTING` / `REPAIRING`。

### D. HURT（受击硬直）
- 行为：`act_hurt_knockback.gd`
- 动画：`hurt`（非循环）。
- 结束：回到 `FLYING_ATTACK`。

### E. STUNNED（弱化坠落/眩晕）
- 行为：`act_stunned_fall.gd`
- 动画流：
  1. 空中坠落：`fall_loop`（循环）；
  2. 落地瞬间：`land`（非循环）；
  3. 眩晕停留：`stun_loop`（循环）。
- 弱化计时结束后：转 `WAKE_FROM_STUN`。

### F. WAKE_FROM_STUN（眩晕恢复并回巢）
- 行为：`act_wake_fly_return.gd`
- 动画流：
  1. `wake_from_stun`（非循环）；
  2. `takeoff`（非循环）；
  3. 飞行阶段：`fly_move`（循环）；
  4. 回巢落位：`sleep_down`（非循环）；
  5. 最终进入 `RESTING`（由行为完成收尾设置）。

### G. RETURN_TO_REST（常规回巢）
- 行为：`act_return_to_rest.gd`
- 动画流：
  1. 飞向巢穴：`fly_move`（循环）；
  2. 到位后：`sleep_down`（非循环）；
  3. 进入 `RESTING`（后续由 `rest_loop` 常驻）。

### H. REPAIRING（修巢）
- 行为：`act_repair_rest_area.gd`
- 动画流：
  - 飞行移动：`fly_move`（循环）；
  - 到修复位等待/定位：`fly_idle`（循环）；
  - 修复过程：`fix_rest_area_loop`（循环）；
  - 修复完成后切回 `RETURN_TO_REST` 或 `FLYING_ATTACK`。

### I. HUNTING（狩猎地面怪夺面具）
- 行为：`act_hunt_walk_monster.gd`
- 动画流：
  - 搜索/飞近：`fly_move`（循环）；
  - 抓取过程（无独立攻击动作时保持移动/停悬逻辑）；
  - 戴回面具：`no_face_to_has_face`（非循环）；
  - 结束后根据攻击时窗决定回 `FLYING_ATTACK` 或 `RETURN_TO_REST`。

## 3) 本次发现并修正的明显矛盾

1. **RESTING 唤醒条件与需求不一致**：原先仅 `ghost_fist` 可唤醒。已补充 `chimera_ghost_hand_l` 命中也能触发 `WAKING`。
2. 其余 StoneMaskBird 的行为-动画映射与当前 BT 优先级一致，未发现会导致明显死锁/矛盾的分支。
