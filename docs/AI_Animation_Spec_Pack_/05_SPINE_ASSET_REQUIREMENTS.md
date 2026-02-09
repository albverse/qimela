# 05_SPINE_ASSET_REQUIREMENTS.md（Spine 资源：骨骼/事件/命名的硬规则）

> 目的：把“资源侧”的要求写死，避免 AI 在代码侧补救资源错误。

---

## 1) 必备骨骼（与代码约定对齐）
Player Spine 中必须存在（至少）：
- `chain_anchor_l`：左手锁链发射点
- `chain_anchor_r`：右手锁链发射点

注意：项目当前方案 **不做左右骨骼名交换**。朝向翻转由 `Visual.scale.x` 处理，锚点直接按语义读取。

---

## 2) 动画命名：精确匹配（禁止“差不多”）
- GDScript 中动画名是 `StringName`/字符串常量，必须与 Spine 动画名 **逐字一致**。
- 如果要改名：必须同步更新
  - `scene/components/player_animator.gd` 的映射表
  - `scene/components/weapon_controller.gd` 的 anim_map
  - 任何依赖 ACTION_END_MAP 的结束事件映射

---

## 3) 事件点（Spine Event）命名约定（推荐）
当你需要“在动画某一帧做事”（发射/冲量/生成 hitbox）时，使用事件点，不要写死计时器。

推荐事件名（示例）：
- `fire`：发射子弹/生成 projectile
- `hitbox_on` / `hitbox_off`：开启/关闭攻击判定
- `dash_impulse`：施加冲量（由 Movement 执行）
- `phase_2`：动作分段（例如重攻击第二段）

规则：
- 事件名必须在契约里列出用途
- 事件触发后的逻辑必须有“幂等”保护（重复触发不产生双发）

---

## 4) 混合（mix）与叠加的最低要求
- Track1 overlay 动作必须考虑：
  - 入场 mix（避免“瞬切抖动”）
  - 退场 mix（避免“上半身残影”）
- FULLBODY_EXCLUSIVE 必须明确：
  - 进入时是否需要清 Track0/Track1
  - 退出后如何回到 locomotion（通常靠 anim_completed + 状态 resolver）

---

## 5) 资源变更的同步清单（你改 Spine 时必须做）
- 改骨骼名 → 更新 Animator/ChainSystem 的 bone 名配置
- 改动画名 → 更新 WeaponController/Animator 映射 + EndMap
- 新增事件点 → 更新 Animator 或相关系统的 event handler，并补 Mock 模式模拟（若该事件参与逻辑）
