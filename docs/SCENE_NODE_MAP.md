# SCENE_NODE_MAP.md（场景节点地图）

> 说明：以下节点名/职责来自对话中“已经出现过/已经使用过”的元素；缺失处标记“待定位”。

## 玩家 Player（CharacterBody2D）
- ScenePath: `Player`（待定位具体 tscn）
- 常见子节点（已出现路径）：
  - `Visual`：只负责视觉翻转（`visual.scale.x`）；**常见坑**：visual 为 null 会报 `scale on null instance`。
  - `Visual/HandL`、`Visual/HandR`：锁链发射起点；左右手起点不同。
  - `Chains/ChainLine0 (Line2D)`、`Chains/ChainLine1 (Line2D)`：两根锁链的显示；与 `Visual` 同层级（用户明确）。
- 定位方法：在 Player.gd 的 `@export var ..._path` 搜索 `Visual/Hand` 与 `Chains/ChainLine`。

## 锁链 Line2D（ChainLine0/1）
- 职责：显示链条纹理；点列来自 Verlet 结果。
- 常见坑：
  - Line2D 不显示：可见性 `visible=false`、材质未设、或点坐标没用 `to_local`。
  - “只有尾巴被无限拉长”：通常是纹理 mode / UV anchor / 点顺序问题；已采用 `texture_anchor_at_hook=true` + 反向点序来让展开只发生在手端。
- 定位方法：Inspector 搜索 `Line2D -> Texture / Texture Mode / Tile`（具体字段因版本不同显示略有差异）。

## 怪物 Monster（CharacterBody2D）
- 角色：MonsterFly / MonsterWalk（方块占位）
- 关键子节点（推荐/已讨论）：
  - `CollisionShape2D`：只负责实体落地（与 World 碰撞）。
  - `EnemyHurtbox (Area2D)` + `CollisionShape2D`：只负责“受击检测”（被锁链射线命中）。
- 常见坑：
  - 玩家跳跃碰怪物后“粘头上”：属于实体碰撞分离问题；可通过 Layer/Mask 让玩家与怪物不互撞。
  - 受击闪白不生效：AnimationPlayer 覆写 modulate；或视觉节点不是 `_visual` 指向对象。
- 定位方法：MonsterBase.gd 中查找 `_visual` 与 `on_chain_hit`。

## ChimeraA（CharacterBody2D）
- 角色：融合产物；默认不主动攻击，链接后触发互动（追随玩家 X）。
- 关键函数（已出现脚本）：
  - `set_player(p)` 或 `set_player(p: Node2D)`：绑定玩家引用
  - `on_chain_attached(slot)`：进入 linked（触发互动）
  - `on_chain_detached(slot)`：解除 linked
- 常见坑：
  - 生成后卡地板：CollisionShape2D 过大/原点偏；需“生成点避重叠 + 1帧禁碰撞”。
  - “击中无反应”：Player 的命中对象不是 ChimeraA（打到了 body 而非 Hurtbox/接口），或 Player 没调用 `on_chain_attached`。
- 定位方法：ChimeraA.gd 中查 `on_chain_attached`，Player.gd 中查 `LINKED` 分支与 `call("on_chain_hit"... )`。

## LinkPoint（Area2D，未来用于 ChimeraB）
- 目的：让 Player 的锁链命中“LinkPoint”而不是 Chimera 主体，从而区分“链接了 ChimeraB 的哪一块”。
- 注意：用户设想 ChimeraB = 两个可分离移动的子怪物 a/b；只有 a 与 b 都被链接才触发互动。
- 节点状态：概念已确认，尚待落地（待定位/待创建）。

## 其它已提到节点/组件（待定位）
- `AnimationPlayer`：若存在，需注意会覆盖 `modulate` 导致闪白看不见。
- `Hurtbox/Hitbox`：用于解耦“实体碰撞”与“受击判定”；避免玩家与怪物互撞仍可受击。
- `RangeArea / ExplosionRangeArea`：在 Boss 讨论中出现（范围检测），具体场景待定位。
