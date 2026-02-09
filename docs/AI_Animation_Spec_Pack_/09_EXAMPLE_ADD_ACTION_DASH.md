# 09_EXAMPLE_ADD_ACTION_DASH.md（示例：DASH 动作契约，展示“写到不会歧义”的程度）

> 说明：这是示例，不代表你项目现在就有 DASH。用途是给 AI 看“契约应写多硬”。

---

### ACTION_ID: DASH

#### 1) 归属层
- 层：ActionFSM
- Track1 overlay：否（本动作为 FULLBODY_EXCLUSIVE）
- 播放模式：FULLBODY_EXCLUSIVE
- lock_anim_until_end：true（动作开始后不随 context 变化）

#### 2) 进入条件（Entry Guards）
- 输入触发：`scene/player.gd::_unhandled_input` 监听 `KEY_SHIFT + KEY_SPACE`（示例）
- 必须满足：
  - hp > 0
  - ActionFSM.state ∈ {None}
  - on_floor: true
- 优先级：DASH pr=80（低于 Hurt/Die）

#### 3) 退出条件（Exit Rules：唯一真相）
- 主退出：A) anim_completed
  - track：1（track1 播放全身独占）
  - anim_name：`dash`
  - completed 后派发：`anim_end_dash`
- 兜底：B) timeout = 0.6s（若 completed 未到，强制 resolver）

#### 4) 物理契约（Physics Contract）
- 动作期间移动输入：禁止（避免玩家改变方向导致穿模）
- 冻结水平速度：由 Movement 执行（进入 DASH 时 Movement 读取 action_state 并锁定 velocity.x）
- 施加冲量：
  - 大小：+900 * facing（示例）
  - 时刻：Spine Event `dash_impulse`
  - 执行位置：`scene/components/player_movement.gd::apply_dash_impulse()`
- 空中触发：否
- 重力：照常（不改重力，只是短时间冲量）

#### 5) 打断矩阵
| 打断来源 | 是否打断 | 清理 |
|---|---|---|
| Hurt | YES | 清 pending_event，停止 dash 锁定，清 track1，关闭 hitbox（若有） |
| Die | YES | 清一切，冻结输入/移动 |
| CancelChains(X) | NO | 不相关 |
| Fuse(Space) | NO | 不相关 |
| Weapon Switch(Z) | NO | 不允许切换 |

#### 6) 动画契约
- Spine anim：`dash`
- loop：false
- track：1
- mix：入场 0.08s；退场 0.10s
- 事件：
  - `dash_impulse`：触发 Movement 冲量（幂等：只允许一次）

#### 7) 代码点
- `scene/components/player_action_fsm.gd`：
  - enum 增加 DASH
  - on_dash_input()：触发转移
  - anim_end_dash()：resolver
  - timeout 兜底
- `scene/components/player_animator.gd`：
  - ACTION_ANIM 增加 Dash → dash
  - ACTION_END_MAP 增加 dash → anim_end_dash
  - FULLBODY_EXCLUSIVE 清理策略
- `scene/components/player_movement.gd`：
  - apply_dash_impulse()
  - action_state==DASH 时锁定输入/速度
- `scene/components/anim_driver_mock.gd`：
  - dash duration=0.55s（示例）

#### 8) 验证用例
- 正常 dash 完成回到 Idle/Run
- dash 中受击：立即进入 Hurt，冲量不再重复触发
- dash 中 hp=0：进入 Die，dash 停止推进
