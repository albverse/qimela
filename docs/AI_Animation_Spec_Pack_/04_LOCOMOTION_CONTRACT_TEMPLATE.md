# 04_LOCOMOTION_CONTRACT_TEMPLATE.md（新增移动状态：契约模板）

> 只有在你要新增“移动层状态”（例如滑步、攀爬、游泳）时才用本模板。
> 普通攻击/施法不属于这里，应写 Action 契约。

---

### LOCO_ID: <唯一ID，例如 SLIDE / CLIMB>

#### 1) 进入条件
- 来自 MoveIntent：Walk/Run/None（是否需要新增 intent）
- floor/vy 条件：
- 触发输入：<如果需要额外按键，必须说明入口与消费方式>

#### 2) 退出条件（唯一真相）
- 主退出：anim_completed / 条件变化（floor/vy/intent）/ timeout
- 若使用 anim_completed：必须更新 `player_animator.gd::LOCO_END_MAP`

#### 3) 物理契约（Movement 执行）
- 此状态下 velocity.x 的计算规则：
- 重力是否变化：
- 是否限制转向：

#### 4) 动画契约
- `player_animator.gd::LOCO_ANIM` 新增映射
- `LOCO_LOOP` 是否 loop
- 如为非 loop：`LOCO_END_MAP` 增加结束事件 → `LocomotionFSM` 消费

#### 5) 验证用例
- 地面进入/退出
- 空中进入/退出（若适用）
- 被 Hurt/Die 抢占时是否安全
