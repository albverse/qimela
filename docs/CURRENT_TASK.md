# CURRENT_TASK.md（当前任务单）

## 优先问题 1：融合后 ChimeraA 未生成/未生效
- **复现步骤**：
  1) 两只怪物（Fly + Walk）都被打到 HP==1 进入虚弱；
  2) 两根锁链分别命中两只虚弱怪物并进入 `LINKED`；
  3) 按空格（`action_fuse` 或 Space）触发融合。
- **预期**：
  - 玩家被锁定 `fusion_lock_time`；两怪物消失；两链溶解；演出结束后在玩家附近生成 ChimeraA。
- **实际**（近期日志线索）：
  - `[FUSE] type0=CharacterBody2D type1=CharacterBody2D`、`[HIT] Fly1 class=CharacterBody2D`，表明当前命中/识别对象仍是 CharacterBody2D，本应通过 Hurtbox/脚本接口识别具体类型/脚本类。
- **验收标准（DoD）**：
  - 触发融合后，场景树出现 ChimeraA 实例；ChimeraA 能落地且不会卡入地面；ChimeraA 被锁链命中可进入互动（linked）。

## 优先问题 2：怪物“闪白”不生效（只消失/无变化）
- **复现步骤**：满血怪物被锁链命中。
- **预期**：怪物视觉节点整体变亮/变白，持续 `flash_white_time` 后恢复；受击僵直 0.1 秒。
- **常见原因（需要验证）**：
  - 视觉节点 `_visual` 不是 Sprite/Node2D 或者被 AnimationPlayer 每帧覆写 `modulate`；
  - Monster 实例实际被 `queue_free()` 或 `visible=false` 导致看起来“消失”。
- **DoD**：可见的“变亮”闪烁，且不影响碰撞/受击逻辑。

## 优先问题 3：生成位置安全（防止 ChimeraA 卡地板/重叠刚体）
- **目标方案（已定）**：A+B 双保险
  - A：生成前找到一个不重叠点（通常玩家上方或身旁）；
  - B：生成后禁碰撞 1 帧再启用。
- **DoD**：无论玩家站地面/坡面/贴墙，融合生成都不会把 ChimeraA “卡死/弹飞”。

---

## 归属说明：场景(.tscn) 主控 vs 脚本(.gd) 主控
- **场景主控**：
  - 碰撞 Layer/Mask 配置（PlayerBody/MonsterBody/World 等）；
  - Hurtbox/Hitbox Area2D 的存在与形状；
  - ChimeraA 预制体根节点类型（CharacterBody2D）及其 CollisionShape2D 位置/大小；
  - 主测试场景 MainTest（若保存报“依赖项问题”，通常是引用了不存在的 .tscn）。
- **脚本主控**：
  - Player 锁链状态机、Ray hit 判定 mask、LINKED 与融合条件；
  - MonsterBase HP/weak/受击僵直/闪白；
  - ChimeraA 的 on_chain_attached/on_chain_detached 与移动逻辑；
  - 融合锁玩家与链条溶解时间。

## 不要做（防止发散/重构）
- 不要重构输入体系（保持：A/D、W 跳、鼠标左键发链、Space 融合）。
- 不要改动“数据A”参数语义（可调值，但不要改变变量名/用途）。
- 不要引入新的全局层/单例来管理链条（避免节点结构漂移）。
- 不要把“命中识别”改回纯碰撞体硬碰（保持射线 + Hurtbox/组/接口的可测试结构）。
