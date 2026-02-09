# 06_IMPLEMENTATION_CHECKLIST_ADD_ACTION.md（新增动作：实施检查清单）

> 这是“落地到代码”的步骤清单。按顺序做，能显著减少漏改点。

---

## Step 0：先写契约（必须）
- 复制 `03_ACTION_CONTRACT_TEMPLATE.md`
- 填好：进入/退出/打断/物理/动画/验证用例
- 把该动作命名为 ACTION_ID，并确定动画名 exact_name

---

## Step 1：决定动作走哪条路径
- 普通武器动作：走 `ActionFSM → Animator`（默认）
- Chain 特例：只有链条发射/取消沿用 bypass；新动作不应走 bypass

---

## Step 2：WeaponController（如果动作属于某武器攻击）
文件：`scene/components/weapon_controller.gd`
- 是否需要新增 WeaponType？
- 是否需要新增新的“攻击类型”或“重攻击”条目？
- 更新 WeaponDef：
  - `attack_mode`
  - `lock_anim_until_end`
  - `anim_map`（context → anim）
  - `cancel_anim`（如有）

---

## Step 3：ActionFSM（只做裁决，不播动画）
文件：`scene/components/player_action_fsm.gd`
- 若是新状态：更新 `enum State`，并补 `STATE_NAMES`
- 在输入入口/事件入口中触发转移（例如 `on_m_pressed`、`on_space_pressed`、`on_weapon_switched` 等现有入口）
- 写清 resolver：动作结束后回到哪（Idle/Run/None），统一走 `resolve_post_action_state`
- 如果依赖 completed：确保有 `anim_end_*` 事件处理函数与状态匹配
- 加超时兜底（如果动作可能因为资源问题收不到 completed）

---

## Step 4：Animator（唯一播放点）
文件：`scene/components/player_animator.gd`
- 更新 `ACTION_ANIM`：ActionStateName → anim_name
- 更新 `ACTION_END_MAP`：anim_name → anim_end_event_name
- 若需要新事件：在 `_on_anim_completed` 或相关回调中派发给 FSM（保持单向：Animator → FSM）
- 如为 FULLBODY_EXCLUSIVE：明确清理 Track0/Track1 的策略

---

## Step 5：Spine Driver / Mock Driver（让完成事件可被验证）
- Spine：确保能回调 `anim_completed(track, anim_name)`（或明确是 loop，不依赖 completed）
- Mock：给该 anim_name 配 duration（或模拟 event），保证测试流程不依赖 Spine 才能跑

---

## Step 6：输入接线（只允许在既定入口）
文件：`scene/player.gd`
- 若需要新增按键：在 `_unhandled_input` 中接线
- 若是移动类：不要从这里处理，交给 Movement/LocomotionFSM
- 禁止在其它节点新增 `_input/_unhandled_input` 旁路

---

## Step 7：验证
按 `08_DEBUG_LOGGING_AND_VERIFICATION.md` 跑：
- 正常完成
- Hurt 打断
- Die 抢占
- 观察：状态是否归位、track 是否清理、是否出现双重播放/幽灵发射
