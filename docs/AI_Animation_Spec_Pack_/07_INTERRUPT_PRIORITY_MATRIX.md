# 07_INTERRUPT_PRIORITY_MATRIX.md（打断与优先级：最低一致约束）

> 目的：让所有新增动作都遵守同一套“谁能打断谁”的底线。

---

## 1) 全局优先级（ActionFSM）
- Die：pr=100（终态）
- Hurt：pr=90（受击）
- 其它动作：建议 pr ≤ 80（按重要性分层）

规则：
1) **任何动作不能阻止 Die**。Die 发生时必须清空 pending、计时器、占用资源。
2) Hurt 可以打断大多数动作；若某动作不允许被 Hurt 打断，必须给出强理由，并给出替代“受击反馈”。

---

## 2) 推荐的打断矩阵（默认值）
| 当前动作 | 被 Hurt 打断 | 被 Die 打断 | 被 Fuse 打断 | 被 CancelChains 打断 |
|---|---:|---:|---:|---:|
| 普通 Attack | YES | YES | 可选（通常 NO） | 与武器相关 |
| 重攻击/施法 | YES（或 YES 但减轻） | YES | NO | 与武器相关 |
| Fuse（融合） | YES（通常转 fuse_hurt 或 hurt） | YES | N/A | N/A |
| Chain 发射（bypass） | 在输入层禁止（Hurt/Die 时直接 return） | YES | N/A | YES |

---

## 3) 打断后的“必须清理项”（最小集合）
- pending_fire / pending_event（任何延迟提交）
- hitbox enable 状态（开过就必须关）
- Track1 的残留（必要时清或播放结束过渡）
- 动作计时器（timeout 保护）
- 与 slot/链条相关的占用标记（尤其是融合引导/锁定时间）
