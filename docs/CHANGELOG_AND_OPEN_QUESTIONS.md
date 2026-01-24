# CHANGELOG_AND_OPEN_QUESTIONS.md（变更史与未决问题）

## 关键变更史（按对话时间顺序，最短句）
1. 从“直线绳”升级为 **Line2D 纹理链条 + Verlet**，并解决“尾巴无限拉长/缩进端不自然”问题。
2. 明确 **双锁链（两手）**：ChainLine0/1 与 Visual 同层级；左右手发射点不同。
3. 输入改为：**W 跳跃**、鼠标左键发射；X 取消链条被禁用（回退到“自然溶解/超长溶解”）。
4. 添加：**超长自动溶解 + 预警变红**；shader 路径固定为 `res://shaders/chain_sand_dissolve.gdshader`。
5. 引入怪物虚弱/链接：满血命中 -> HP-1 + 受击；HP==1 -> 虚弱；虚弱再命中 -> LINKED（链不走 hold_time 自动溶解）。
6. 引入融合：两链分别 LINKED 虚弱怪物 -> Space 融合 -> 生成 ChimeraA。
7. 处理过多次脚本报错（类型推断/Variant、class_name 冲突、rope.gd “running” 未声明、shader fragment return 错误等）；当前工程已“正常运行但融合不生成 ChimeraA”。
8. 物理碰撞调整：玩家与怪物/奇美拉可设置为不互撞，但锁链仍可命中（通过 Ray mask 或 Hurtbox）。

## 仍不确定 / 待用户补充的信息清单
1. **具体场景路径**：MainTest.tscn、Player.tscn、MonsterFly.tscn、MonsterWalk.tscn、ChimeraA.tscn 的实际路径（目前仅有文件名/概念）。
2. **Layer/Mask 规划表**：当前工程里各层（World/PlayerBody/MonsterBody/EnemyHurtbox 等）分别是第几层？（Godot Inspector 中的编号与命名映射需确认）。
3. **锁链命中优先级**：命中怪物 Hurtbox 与命中世界静态体时，谁优先？（目前需求：打到普通平台要“停止/或立刻溶解”，具体版本多次切换）。
4. **ChimeraA 互动触发条件**：是否要求“锁链必须 LINKED 到 ChimeraA 才追随”，还是“生成后自动靠近玩家一次”？（对话中两种说法都出现过，需以最新策划为准）。
5. **MonsterKind / kind 枚举**：对话中出现过 MonsterKind 未声明的报错；当前最终枚举应放在哪里（MonsterBase 还是独立脚本）。

## 最小验证实验清单（每个未决问题对应一个最小验证方法）
1. 场景路径：在 FileSystem 里搜索 `ChimeraA.tscn`，把其路径填进 Player 的 `chimera_scene/chimeraA_scene`，运行融合验证生成。
2. Layer/Mask：打开 Player、Monster、World 的 CollisionObject2D，截图 Layer/Mask；写成一张表（层号->含义）。
3. 命中对象类型：在 Player 的命中处打印 `hit.collider` 的 `get_class()` 与 `get_script()`；若为 CharacterBody2D 且无脚本，则说明打的是实体而非 Hurtbox。
4. ChimeraA 接链：在 ChimeraA.gd 的 `on_chain_attached` 打印；在 Player 链接成功时必须调用该函数并能看到日志。
5. 闪白验证：给 Monster 的视觉节点加一个临时 `Label` 或在 `_flash_white` 内打印 `_visual.name`；若 modulate 被动画覆盖，在 AnimationPlayer 里搜 `modulate` 轨道并临时禁用。

