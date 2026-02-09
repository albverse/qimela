# 08_DEBUG_LOGGING_AND_VERIFICATION.md（最小验证：让错乱无处藏身）

> 目标：每次新增动作，都能用同一套日志与复现步骤快速判定“有没有乱”。

---

## 1) 建议日志标签（统一格式）
在玩家系统中保持类似格式（示例）：
- `[INPUT] ...`
- `[ACTION] TRANS=From->To reason=... pr=...`
- `[LOCO] TRANS=From->To reason=...`
- `[ANIM] play track=... anim=... loop=... mode=...`
- `[ANIM] completed track=... anim=...`
- `[CHAIN] ...`（链条物理/溶解/链接）

> 原则：状态转移与动画播放都必须能在日志里对上，否则就是“隐式逻辑”。

---

## 2) 最小验证用例（新增动作必跑）
### 用例A：正常完成
1) 进入可触发场景（地面/空中按契约要求）
2) 触发动作
3) 等待 completed/timeout
**通过标准**：
- ActionFSM state 回到预期（None/Idle 等）
- Track1 无残留（或按契约进入下一段）
- 没有重复播放同一动作（除非 loop）

### 用例B：Hurt 打断
1) 触发动作
2) 动作进行中制造受击（hp>0）
**通过标准**：
- 进入 Hurt（pr=90）
- 触发清理清单（pending/hitbox/track1/计时器）
- Hurt 结束后回到契约定义的状态

### 用例C：Die 抢占
1) 触发动作
2) 让 hp 变为 0
**通过标准**：
- 立即进入 Die（pr=100）
- 所有 pending 清空
- 不再处理输入、不再推进动作逻辑（终态冻结）

---

## 3) 常见失败信号（出现任意一个就回滚检查）
- 日志有 `[ANIM] play` 但没有对应的 completed/timeout，且 state 不归位
- track1 动画结束后仍保持上半身姿势（残影）
- 动作被打断后仍然触发 fire/hitbox（幽灵事件）
- Animator/Driver 写了 velocity（越权）
