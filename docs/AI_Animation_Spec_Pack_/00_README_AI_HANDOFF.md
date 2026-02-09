# AI 动画规格包（用于把“新增动作”做成不乱的工程变更）

本包目标：当你未来要给 **Player 新增动画动作/攻击/施法等** 时，把“状态机—物理—动画—Spine资源”之间的协作写成**可执行契约**，让 AI 不能凭经验脑补，从而避免：
- 动画播了但状态不归位（卡死/锁死）
- 物理被 Animator 改写（位移/重力错乱）
- 进入/退出条件不唯一（完成事件和计时器互相打架）
- 被 Hurt/Die 打断后资源不清理（链槽/挂起发射/Hitbox残留）

---

## 使用方式（给 AI 的“阅读顺序”）
1) **先读 `01_PROJECT_INVARIANTS.md`**：这是最高优先级的“硬约束”。
2) 再读 `02_ANIMATION_SYSTEM_OVERVIEW.md`：了解现有轨道、驱动、映射。
3) 新增动作时：先复制 `03_ACTION_CONTRACT_TEMPLATE.md` → 填成一条动作契约（或参照 `09_EXAMPLE_ADD_ACTION_DASH.md`）。
4) 按 `06_IMPLEMENTATION_CHECKLIST_ADD_ACTION.md` 实施改动。
5) 用 `08_DEBUG_LOGGING_AND_VERIFICATION.md` 跑最小验证用例。

---

## 本包默认适配的项目结构（与你仓库一致）
- `scene/player.gd`
- `scene/components/player_movement.gd`
- `scene/components/player_locomotion_fsm.gd`
- `scene/components/player_action_fsm.gd`
- `scene/components/player_animator.gd`
- `scene/components/anim_driver_spine.gd`
- `scene/components/weapon_controller.gd`
- `scene/components/player_chain_system.gd`

---

## 重要声明（避免“文档漂移”）
- 本包是“动画契约层”，不替代你仓库中的 `docs/0_ROUTER.md`、`docs/A_PHYSICS_LAYER_TABLE.md`、`docs/D_FUSION_RULES.md` 等“系统级唯一真相”文档。
- 若本包与仓库现状冲突：以 `01_PROJECT_INVARIANTS.md` 与代码实现为准，并更新本包（不要让 AI 自行猜测差异）。
