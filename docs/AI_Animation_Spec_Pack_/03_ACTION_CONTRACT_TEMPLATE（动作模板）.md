# 03_ACTION_CONTRACT_TEMPLATE.md（新增动作：必须填写的契约模板）

> 把每个“新动作”写成可验证契约。AI 只能按契约实现，禁止脑补。

请复制本模板，为每个动作生成一段：`### ACTION_ID: ...`

---

### ACTION_ID: <唯一ID，例如 DASH / HEAVY_ATTACK / CAST_SPELL>

#### 1) 归属层
- 层：ActionFSM / LocomotionFSM（二选一）
- 是否使用 Track1 overlay：是/否
- 播放模式：OVERLAY_UPPER / OVERLAY_CONTEXT / FULLBODY_EXCLUSIVE（与 WeaponController.AttackMode 对齐）
- 是否允许动作中 context 变化切换动画：是/否（对应 `lock_anim_until_end`）

#### 2) 进入条件（Entry Guards）
- 触发输入：<按键/鼠标/事件>（指出入口函数，例如 `scene/player.gd::_unhandled_input`）
- 必须满足：
  - hp > 0（否则 Die 抢占）
  - ActionFSM.state ∈ <允许列表>
  - on_floor: true/false/any
  - 其它资源条件：<冷却/能量/占用槽位>
- 转移优先级建议：Die=100 > Hurt=90 > 本动作=<数字>

#### 3) 退出条件（Exit Rules：唯一真相）
- 主退出方式：A) anim_completed  B) timeout  C) spine_event（可组合但必须声明主次）
- 若 A) anim_completed：
  - track：0 或 1
  - anim_name：<精确字符串>（必须与 Spine 资源一致）
  - completed 后派发事件：<例如 ActionFSM.anim_end_attack>
- 若 B) timeout：
  - 秒数：
  - 超时后调用：`PlayerActionFSM.resolve_post_action_state(reason)`
- 若 C) spine_event：
  - event 名：
  - 用途：<发射/生成 hitbox/施加冲量/切阶段等>

#### 4) 物理契约（Physics Contract：Animator 不得改 velocity）
- 动作期间移动输入：允许/禁止
- 是否冻结水平速度：是/否（若是，冻结在 `player_movement.gd` 或明确的 movement helper 内实现）
- 是否施加冲量：
  - 向量/大小：
  - 触发时刻：进入瞬间 / spine_event / 某计时
  - 执行位置：<文件路径::函数名>
- 空中可否触发：是/否
- 重力是否照常：是/否（如否，必须说明由 Movement 哪个分支实现）

#### 5) 打断矩阵（Interrupt Matrix：必须写清“被打断后清什么”）
| 打断来源 | 是否允许打断本动作 | 打断后的清理清单（必须写） |
|---|---|---|
| Hurt | YES/NO | <例如：清 pending_fire、停 hitbox、归还槽位、清 track1> |
| Die | YES（必须） | <清一切> |
| CancelChains(X) | YES/NO | <说明> |
| Fuse(Space) | YES/NO | <说明> |
| Weapon Switch(Z) | YES/NO | <说明> |

#### 6) 动画契约（Animation Contract）
- Spine 动画名（唯一）：`<exact_name>`
- loop：true/false
- track：0/1
- 混合（mix）：
  - 入场 mix：
  - 退场 mix（track1 叠加必须考虑）：
- 必须存在的骨骼（若用于锚点/发射）：
  - bone: <name> 语义：<Hand_R / Hand_L / Muzzle ...>
- 使用到的 Spine Event（如有）：
  - event_name: <用途>

#### 7) 需要修改的代码点（路径 + 函数名）
- `scene/components/player_action_fsm.gd`：<新增状态/转换/处理函数>
- `scene/components/player_animator.gd`：<更新 ACTION_ANIM / ACTION_END_MAP / 播放逻辑>
- `scene/components/weapon_controller.gd`：<更新 WeaponDef / anim_map / attack_mode>
- `scene/player.gd`：<输入入口接线，若需要>
- `scene/components/anim_driver_mock.gd`：<补 duration/事件模拟，若需要>

> 禁止新增其它播放入口；如需 helper，必须归属 Animator。

#### 8) 验证用例（可复现 + 有通过/失败判据）
- 用例1：正常触发 → completed/timeout → 回到预期状态
- 用例2：动作中被 Hurt 打断
- 用例3：动作中 hp=0 → Die 抢占
- 失败判据（任选其一即失败）：
  - 状态卡在 Attack/Fuse 等不归位
  - track1 没清导致叠加残留
  - Animator 改写 velocity
  - completed 未触发且无 timeout 兜底
