# 10_AI_REQUEST_FORMAT.md（把需求交给 AI 的“强约束提示词”模板）

> 把下面内容作为你发给 AI 的消息开头，可显著减少跑偏。

---

## 固定开头（复制即可）
你将修改一个 Godot 4.5 项目。请严格遵守以下硬约束：

1) 不改变 `scene/player.gd::_physics_process` 的 tick 顺序（Movement → move_and_slide → LocomotionFSM → ActionFSM → Health → Animator → ChainSystem）。
2) 只有 `scene/components/player_animator.gd` 可以播放动画；FSM/Movement/ChainSystem 禁止直接播放（链条动画仅在现有特例范围内）。
3) Animator 禁止改写 velocity；所有物理/冲量由 `player_movement.gd` 或明确的 Movement helper 执行。
4) 每个新增动作必须：有唯一主退出条件（anim_completed 或 timeout），并写清打断清理清单。
5) 任何修改请给出：涉及文件路径 + 函数名 + 变更点摘要 + 最小验证步骤（用例A/B/C）。

接下来是动作契约（必须按契约实现）：
<在这里粘贴你填好的 ACTION_CONTRACT 条目>

---

## 如果信息缺失，AI 允许做的默认假设（减少反复问答）
- 若 mix 未指定：入场 0.08s，退场 0.10s（仅建议值，需写入实现）
- 若 timeout 未指定但依赖 completed：给 2x 动画时长的兜底 timeout
- 若未指定 hitbox：默认无 hitbox（只做动画与状态回归）
