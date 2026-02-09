# 01_PROJECT_INVARIANTS.md（最高优先级：不可破坏约束）

> 目标：把“项目为什么不乱”的关键条件写死。任何 AI 改动如果触碰这些，必须先停下。

---

## A. 固定 tick 顺序（不可改变）
来自 `scene/player.gd::_physics_process(dt)`：

1) `movement.tick(dt)`  
2) `move_and_slide()`  
3) `loco_fsm.tick(dt)`  
4) `action_fsm.tick(dt)`  
5) `health.tick(dt)`（若存在）  
6) `animator.tick(dt)`  
7) `chain_sys.tick(dt)`（Animator 之后；用于读取当帧骨骼锚点）

**禁止**：把 Animator 放到 move_and_slide 之前；禁止把 ChainSystem 放到 Animator 之前。

---

## B. 单一职责（谁都别越界）
### B1) Movement（`scene/components/player_movement.gd`）
- 只负责：水平速度、重力、落地 vy 夹断、消费 jump_request、面向（facing）  
- **禁止**：播放动画、状态机转移、创建攻击/融合逻辑

### B2) LocomotionFSM（`scene/components/player_locomotion_fsm.gd`）
- 只负责：根据 floor/vy/move_intent 决定 locomotion_state  
- **禁止**：播放动画、修改 velocity、发射锁链/武器

### B3) ActionFSM（`scene/components/player_action_fsm.gd`）
- 只负责：动作覆盖层状态裁决（Attack/Cancel/Fuse/Hurt/Die 等）  
- **禁止**：播放动画、修改 velocity、直接操纵 Spine

### B4) Animator（`scene/components/player_animator.gd`）
- **唯一**允许播放动画的模块（Spine 或 Mock）  
- 只负责：依据 locomotion_state/action_state 选择并播放动画，派发 anim_end 事件  
- **禁止**：写 velocity、处理输入、决定状态机逻辑

### B5) ChainSystem（`scene/components/player_chain_system.gd`）
- 只负责：锁链物理/链接/溶解/融合引导；读取手部锚点  
- **禁止**：改写 locomotion/action 状态机；禁止引入新的动画播放入口（链条动画为“特例”，见下条）

---

## C. 动画播放入口约束（必须一致）
- 普通武器（Sword/Knife 等）：走 **ActionFSM → Animator** 标准路径
- Chain（链条）：`scene/player.gd::_unhandled_input` 中存在 **bypass ActionFSM** 的路径，直接 `chain_sys.fire(side)`；链条动画通常由 ChainSystem 手动触发并标记为 manual（避免 Animator tick 误清理）

**禁止**：新增第二个“随便哪里都能 play 动画”的入口。  
如果必须新增：只能加在 Animator 内部，并由状态机驱动。

---

## D. 退出条件必须“唯一真相”
每个新动作必须明确：
- 主退出条件：`anim_completed` 或 `timeout` 或 `event_point`（可有兜底，但必须写主次）
- 所有清理动作（pending_fire、slot 占用、hitbox、track 混合）必须写在 Exit 或 Interrupt 规则里

---

## E. 打断优先级（最低约束）
在 ActionFSM 体系下：  
**Die(pr=100) > Hurt(pr=90) > 其它动作**  
任何新动作不得让自己抢占 Die/Hurt，也不得阻止 Die/Hurt 的清理逻辑。
