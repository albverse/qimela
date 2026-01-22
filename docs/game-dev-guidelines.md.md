# 游戏文书指导计划（锁链投射 × 融合奇美拉）

> 用途：作为仓库内“单一真相来源”，供 Codex/协作者/未来自己在实现时遵守。
> 适用引擎：Godot 4.5（GDScript）。
> 基线版本：数据A（Player.gd + RopeSim2D.gd）；出现退化必须可回退到数据A对照排查。
> 变更规则：任何实现不得违反本文“硬约束”。若必须例外，需在提交说明中写明原因、影响范围、测试步骤与回滚方式。

## 0. 硬约束（Codex 每次编写都必须先读这一段）

- **命中对象必须走 EnemyHurtbox / LinkPoint（Area2D）**；不得依赖 CharacterBody2D 本体被命中来做逻辑判定。
- **命中后必须能解析到“逻辑主体”**（MonsterBase / ChimeraBase / Part），并遵守统一接口契约：
  - `on_chain_hit(player, slot, hit_world) -> int`：返回 **0/1/2**（0=普通受击且本链溶解；1=允许链接；2=忽略/穿透）。
  - `on_chain_attached(slot, player, hit_world)`：链进入 LINKED 时通知。
  - `on_chain_detached(slot)`：链断裂/溶解/融合结束时通知。
- **Player 的锁链核心行为默认不改**（除非规范允许且写明原因）。
- **每条锁链必须使用独立 `ShaderMaterial`**；Tween 完成后必须复位材质参数，避免残留/串台。
- **生成防卡死必须采用 A+B 双保险**：生成前找不重叠点 + 生成后禁碰撞 1 帧再恢复。
- **数据驱动优先**：新增怪物/奇美拉优先走 `MonsterDef / ChimeraDef / Recipe` 表，不改 Player 主流程。
- **Godot Shader 约束（沿用既定规则）**：颜色相关 `uniform` 用 `vec3/vec4` 并直接赋默认值，避免使用 `hint_color`。
- **节点树输出规范（给 Codex）**：输出节点树时对新增/旧节点做清晰颜色标识；避免使用可能导致结构歧义的“全局层”等措辞。

## 1. Codex 交付验收清单（每次提交都要有）

- 修改/新增了哪些文件（文件路径列表）。
- 核心改动点（关键函数与状态机变化）。
- 可复现测试步骤（最短路径），并标注**期望日志关键词**。
- 回滚方式（如何恢复到数据A）。

把目前我们已经谈论到的功能，和项目整体未来方向整理成规范化文书，以方便第三方了解当前游戏的全部功能与未来开发的计划。
以下为“第三方可读”的规范化项目文书草案（可直接丢给外包/协作者/未来的自己当说明书）。内容基于我们目前已落地的实现与已确认的设计方向，按“当前可运行功能 → 系统结构 → 开发计划路线图”组织。
# 项目功能规格与开发路线文书（Draft v0.1）

## 0. 项目概述

本项目为 2D 横版动作解谜原型，核心机制是“锁链投射 + 链接/融合（奇美拉）”。玩家通过鼠标瞄准发射锁链，对敌人造成伤害、使其虚弱并进入可链接状态；当两条锁链分别链接到两只虚弱怪物时，可触发融合演出并生成“奇美拉”。
当前重点：把“锁链物理观感（炫酷锁链材质 + 自然抖动）”作为强特色，同时建立可扩展的“怪物类型 × 融合产物（奇美拉类型）”框架。
## 1. 当前已实现的核心玩法与功能

### 1.1 玩家移动与基础操作

移动：A / D 左右移动（也支持 InputMap 动作 move_left/move_right）。
跳跃：W 跳跃（不使用空格跳跃；空格用于融合）。
角色朝向：根据输入左右自动翻转 Visual（仅翻视觉，不改变碰撞体方向），并提供参数 facing_visual_sign 以修正“左右反了”的工程情况。
### 1.2 锁链系统（双链槽位）

同时最多存在 2 根锁链（左手/右手不同发射点，节点独立：ChainLine0/ChainLine1）。
发射方式：鼠标左键点击 → 以鼠标位置为目标向量发射（不限制八方向）。
锁链行为状态机（核心）：
IDLE：未使用
FLYING：如子弹般飞行，逐帧射线检测命中
STUCK：飞行结束或命中后停留
LINKED：链接到目标（怪物/奇美拉）并随目标移动
DISSOLVING：进入溶解（散沙/噪点溶解 Shader）后消失
命中逻辑（已确认）：
命中“可受击目标”（EnemyHurtbox/怪物）时：根据目标返回值决定“立刻溶解”或“进入链接”。
命中“普通静物/平台”：按设定触发锁链消失特效（不做反弹）。
未命中：飞行超过 chain_max_fly_time 后进入 STUCK，停留 hold_time 后溶解消失。
### 1.3 锁链物理观感与锁链材质显示（核心特色）

锁链使用 Line2D + 纹理重复实现“锁链图案”，并采用 Verlet 约束模拟“绳子抖动感”。
已实现效果：
整根锁链会抖动，并且靠近钩子/端点抖动更强，随后快速恢复稳定（参数控制 rope_wave_*）。
材质“展开/缩进只发生在玩家手端”：通过点序反转（UV 锚在钩子端）实现视觉上的“从手端拉出锁链”更自然（参数 texture_anchor_at_hook）。
断裂预警变红：当距离接近 chain_max_length，锁链颜色逐步向红色过渡（warn_start_ratio / warn_gamma / warn_color）。
最大长度限制：距离超过 chain_max_length 时自动进入溶解消失（作为“断裂/失效”表现）。
### 1.4 溶解特效（Shader）

锁链消失采用 res://shaders/chain_sand_dissolve.gdshader。
溶解流程：Tween 推进 shader 参数（如 burn）→ 完成后隐藏 Line2D 并复位材质。
已确认原则：每条锁链使用独立 ShaderMaterial，避免“上一根链的残留效果影响下一根链”。
### 1.5 物理碰撞/受击检测架构（已落地）

为了避免“玩家/怪物互相顶开、黏在头上”等异常物理推挤，同时保持“锁链能打中敌人”，采用分层分职责策略：
玩家/怪物本体（CharacterBody2D）：只与 World（地面墙壁）发生物理碰撞，用于站立/落地/移动。
受击目标（EnemyHurtbox，Area2D）：专供锁链射线命中/受击判定，与本体碰撞无关。
锁链射线的命中目标由 chain_hit_mask 控制（在 Player Inspector 勾选），通常包含：
World（用于“打到墙就消失/停住”等）
EnemyHurtbox（用于“打到敌人/奇美拉触发受击或链接”）
该架构的直接收益：
玩家不再被怪物推挤/卡死；
锁链命中稳定且可控；
后续扩展“不同受击部位 / 多 LinkPoint / 多段奇美拉”变得简单。
## 2. 敌人与虚弱/链接/融合（当前与近期目标）

### 2.1 现有怪物类型（原型）

以方块素材占位，暂定两类基础怪：
MonsterFly：飞行单位，max_hp=3
MonsterWalk：陆行单位，max_hp=5
受击规则（已确立）：
锁链命中满血怪物：怪物 HP -1，锁链触发消失（溶解）。
怪物受击反馈：怪物“闪白/变亮”一次；并进入 0.1 秒僵直（打断动作）。
当怪物 HP 降到 1：进入“虚弱/昏迷状态”
飞行怪：停止飞行悬停不动
陆行怪：停止移动
### 2.2 链接规则（虚弱状态）

当怪物处于虚弱（HP=1），再被锁链命中：
锁链进入 LINKED 状态，端点挂在怪物身上（随怪物移动）。
锁链不再按 hold_time 自动溶解；只有超出最大长度才会断裂/溶解。
### 2.3 融合规则（ChimeraA 原型）

条件：两根锁链分别 LINKED 到两只虚弱怪物，且两只怪物不相同。
触发：空格（InputMap fuse 或 KEY_SPACE）。
演出：锁玩家移动 fusion_lock_time=0.5s；两只怪物原地消失；锁链以更快参数溶解。
结果：在玩家附近生成奇美拉（目前先实现 ChimeraA）。
## 3. 奇美拉系统：当前实现与未来扩展方向

### 3.1 奇美拉并非统一“跟随型”

已确认的方向是：奇美拉可以是多种定位，至少包括：
敌对型奇美拉：与普通怪物一样攻击玩家，只是“融合产物 = 新敌人”。
可互动奇美拉（链触发互动效果）：玩家锁链链接期间触发【互动效果】，断链/溶解则停止。
ChimeraA：【互动效果】= 尽可能在平台上移动到玩家附近（追随玩家 X 坐标），速度比玩家慢。
多部位链触发型（ChimeraB 等）：需要多个“链接点”同时被链接才触发互动效果。
### 3.2 ChimeraA（当前目标：可互动跟随型）

生成后默认不主动攻击。
当玩家锁链击中 ChimeraA 的 Hurtbox：
锁链进入 LINKED
ChimeraA 进入 _linked=true，开始执行“追随玩家”的移动逻辑（你的 ChimeraA.gd 已具备此逻辑框架）。
断链后：停止互动行为（回到待机/原地停留）。
### 3.3 ChimeraB（未来：双链接点 / 双实体协作）

已确认的正确理解：
ChimeraB 本质可视为两个子实体 a、b（不要求始终重叠，甚至可能分离移动）。
只有当 a 与 b 都被链接住时才触发互动效果。
工程上推荐使用“LinkPoint（Area2D）”体系，每个 LinkPoint 有 link_id；Player 的锁链命中的是 LinkPoint 而非 Chimera 主体，这样可以精准判断“链住了哪一块”。
## 4. 生成防卡死策略（已确认采用 A+B 双保险）

担忧：奇美拉生成在玩家位置时，如果碰撞体略大或错位，可能与地面重叠导致卡死。
采用组合方案：
A：生成前找不重叠点（通常在玩家上方/侧方做若干候选点，用 shape query 或 test_move 检测）
B：生成后禁碰撞 1 帧再恢复（确保即便临界状态也能脱离重叠）
该策略适用于怪物、奇美拉、召唤物等所有“瞬时生成”对象。
## 5. 工程结构与命名约定（第三方协作重点）

### 5.1 玩家节点树关键结构（简化描述）

Player（CharacterBody2D）
Visual（Node2D，用于翻转）
HandL（Node2D，左手发射点）
HandR（Node2D，右手发射点）
Chains（Node2D）
ChainLine0（Line2D）
ChainLine1（Line2D）
### 5.2 “数据A”基线版本（回退基准）

当前锁链系统与 RopeSim2D 的稳定版本定义为数据A。未来任何功能新增如出现退化/闪烁/残留等问题，必须可以一键回退到数据A进行对照排查。
数据A包含：
Player.gd：双链槽位 + 鼠标发射 + 断裂变红 + UV 锚定 + Verlet 抖动 + 溶解 Shader 等
RopeSim2D.gd：基础绳索模拟（测试/对照用）
## 6. 性能与优化原则（当前已采用/将持续遵循）

已采纳的主要优化方向：
Line2D 点位：避免每帧 clear/add，改为预分配点数后每帧 set_point_position。
RayQuery：每条锁链缓存 PhysicsRayQueryParameters2D，避免每帧 new/create。
权重表：缓存 w_end / w_start，避免每帧 pow。
ShaderMaterial：每条链独立材质，避免串台；尽量复用而非频繁 new（视最终实现稳定性选择）。
## 7. 未来开发路线图（建议按里程碑推进）

### Milestone 1：融合链路打通（短期）

受击/虚弱/链接/融合整条流程稳定（MonsterFly + MonsterWalk → ChimeraA）。
修复：受击闪白、僵直、虚弱停止行为的表现统一。
融合生成防卡死 A+B 落地并验证在斜坡/台阶/狭窄地形的鲁棒性。
### Milestone 2：ChimeraA 互动闭环（短期）

锁链链接到 ChimeraA → 触发跟随移动；断链则停止。
追随移动在多平台路径下的可接受行为（先简化为“尽量向玩家 X 靠近”，不做复杂寻路）。
### Milestone 3：组合映射框架（中期）

引入 MonsterKind/ChimeraRecipe（融合配方表）：
Fly + Walk = ChimeraA
Fly2 + Walk2 = ChimeraB / ChimeraC …
明确每种 Chimera 的“敌对型/互动型/多链接点型”类别与触发方式。
### Milestone 4：ChimeraB（中期）

LinkPoint 系统（Area2D）与 slot 绑定
双实体/多部位链接条件判定
“鼠标点击触发攻击动作”的互动型攻击机制
### Milestone 5：表现与打磨（长期）

锁链命中反馈（命中停顿、音效、屏幕震动可选）
溶解 Shader 完善（风格统一、无残留、性能可控）
UI：锁链接近断裂的更清晰提示（红色+音效/边缘闪烁）
可配置化：所有关键数值留在 @export 并保留注释（便于策划/调参）
## 8. 风险点与规避策略（给第三方的“踩坑提示”）

物理推挤导致卡死/黏头：坚持“本体只撞 World，受击用 Hurtbox/Area2D”，生成用 A+B 双保险。
锁链 Shader 残留/串台：每条链独立材质、Tween 完成后复位材质参数，必要时销毁旧 Tween。
锁链抖动发散：rope_damping / rope_stiffness / rope_iterations 需成组调参；优先保证稳定再追求夸张抖动。
融合对象识别失败：当命中的是 Hurtbox/LinkPoint 时，需要向上解析回 MonsterBase/Chimera 实体。
如果你希望这份文书变成“真正可交付给外包的规格说明书”，下一步我会把它补齐两样东西： 1）每个脚本的职责列表与对外接口（例如 MonsterBase 必须实现哪些方法、返回值约定是什么）； 2）数据表/配方表格式（MonsterKind、ChimeraRecipe、互动类型、链接点数量等）。
我需要你的补齐，以及对chimeraB和其他未设计的怪物的策划书的详细
下面把你要的两块“补齐内容”一次性补全： 1）脚本职责 + 对外接口规范（第三方可按此实现/替换脚本） 2）数据表/配方表格式（用于 MonsterKind × ChimeraRecipe 扩展） 并给出 ChimeraB 的详细策划书，以及一套“未设计怪物/奇美拉”的可扩展策划模板与若干具体提案（可直接落到数据表里）。
## A. 脚本职责与接口规范（必须遵守的工程契约）

### A1. Player.gd（玩家 + 锁链系统的总控）

职责
玩家移动/跳跃/朝向翻转（Visual 仅翻转）。
双锁链槽位（0/1），负责：发射、射线检测命中、进入 LINKED、超距断裂、溶解 shader、rope 抖动模拟、断裂预警变红。
负责“融合输入（空格）”的条件判断与演出调度：锁玩家 → 让怪物消失 → 溶解两条链 → 生成奇美拉 → 解锁玩家。
对外接口（Player 对外调用）
无强制公共接口（第三方一般不主动调用 Player），但 Player 会调用目标对象的接口（见下）。
Player 依赖的目标接口（被命中对象必须实现/或通过 Hurtbox 转发）
Player 的射线命中“EnemyHurtbox / LinkPoint”后，最终一定要拿到“逻辑主体 Node”（MonsterBase / ChimeraBase / ChimeraPart）并调用：
1）on_chain_hit(player: Node, slot: int, hit_world: Vector2) -> int
含义：锁链命中时询问“该怎么处理”。 返回值（约定常量）：
0 = 普通受击：扣血/受击反馈已由目标处理，Player 这根链应立刻进入溶解（DISSOLVING）。
1 = 允许链接：目标已确认“进入可链接/可互动状态”，Player 这根链进入 LINKED，并保存挂点。
2 = 忽略/穿透：目标不响应（可用于某些免疫阶段/幻影），Player 可继续飞行或按设计处理（建议仍溶解，避免穿透太怪）。
说明：你现在日志里看到 type0=CharacterBody2D，说明 Player 拿到的还只是节点类型，并没有拿到你真正想要的“MonsterBase/ChimeraA”。这通常是 命中对象不是 Hurtbox/LinkPoint 或 Hurtbox 没把 owner 正确转发 导致的。
2）on_chain_attached(slot: int, player: Node, hit_world: Vector2) -> void
含义：当 Player 判定进入 LINKED 时通知目标——“你被第几根链链接住了”。 用于：ChimeraA 的互动开关、ChimeraB 的双链接点计数等。
3）on_chain_detached(slot: int) -> void
含义：当链断裂/溶解/融合演出结束时通知目标——“链接结束”。 用于：停止互动、清理状态、解除浮空、解除跟随等。
### A2. MonsterBase.gd（怪物基类：生命、受击、虚弱、融合消失）

职责
管理 HP、最大 HP、弱化条件（HP==1）、死亡/消失。
管理受击反馈：闪白（变亮/变白）、僵直 0.1 秒（打断移动/攻击）。
暴露统一的锁链接口：on_chain_hit 返回 0/1 控制“溶解 vs 链接”。
融合演出支持：set_fusion_vanish(true) 期间禁用碰撞/隐藏视觉（避免卡死和残留碰撞）。
对外接口（必须实现）
on_chain_hit(player, slot, hit_world) -> int
HP > 1：扣血 1，触发闪白 + 0.1 僵直，返回 0（让锁链溶解）。
HP == 1（weak=true）：返回 1（允许链接），不再扣血（或按你的规则可扣但保持弱态）。
set_fusion_vanish(v: bool) -> void
v=true：禁用碰撞、隐藏 visual、停止 AI。
v=false：恢复。
建议的信号（第三方扩展时很有用）
signal hp_changed(hp:int, max_hp:int)
signal became_weak()
signal died()
### A3. MonsterFly.gd / MonsterWalk.gd（具体怪物：移动/攻击 AI）

职责
只负责“怎么动/怎么打”，不要重复写 HP/受击逻辑（全部走 MonsterBase）。
Fly：飞行悬停/巡航/俯冲（原型阶段可先静止漂浮）。
Walk：地面走动/转向/追玩家（原型阶段可简单左右移动或静止）。
必须遵循
不要依赖与 Player 的物理推挤（你已走“互不碰撞”路线），攻击判定应走：
怪物攻击 Area2D（Hitbox）打 PlayerHurtbox，或
直接用区域检测/射线检测 PlayerHurtbox。
### A4. ChimeraA.gd（互动型奇美拉：链链接期间触发互动）

职责
生成后可处于“非互动（待机）”状态。
当 on_chain_attached 被调用且链未断：进入互动状态 _linked=true。
互动效果：沿平台尽可能靠近玩家（简化为追玩家 X；不做跳跃/寻路）。
当 on_chain_detached：停止互动。
必须实现（否则你会遇到“击中没反应”）
on_chain_hit(...) -> int：一般应返回 1（允许链接），并在内部进入互动。 你现在 ChimeraA.gd 只有 on_chain_attached/detached，但 没有 on_chain_hit，因此 Player 即便命中，也可能走“默认溶解/默认无效”的分支。
### A5. EnemyHurtbox（Area2D：受击盒，推荐存在）

职责（为什么“不是多余”）
将“物理移动体（CharacterBody2D）”和“受击判定”解耦。 这样你可以做到：玩家和怪物不物理碰撞，但锁链仍稳定命中；怪物受击盒还可以做得更大/更准确、更利于手感。
将命中对象统一为 Area2D，Player 的射线只打 Hurtbox 层，减少“命中乱七八糟的节点类型”。
必须提供
@export var owner_path: NodePath 或自动 get_parent() 找到逻辑主体
func get_owner_actor() -> Node：返回 MonsterBase/ChimeraBase/Part
或者在 Hurtbox 上直接实现 on_chain_hit，内部转发给 owner_actor。
## B. 数据表/配方表格式（用于可扩展设计）

目标：以后你新增 MonsterFly2/Walk2、ChimeraB/C/D，只改数据表，不改 Player 核心。
### B1. 枚举与 ID

MonsterKind：FLY, WALK, FLY2, WALK2, ...
ChimeraKind：A, B, C, ...
关键原则： 配方判断时使用 kind（逻辑类型），不要用场景名/节点名（不可靠）。
### B2. MonsterDef（怪物定义表）

每个怪物种类一条记录，字段建议：
| 字段 | 类型 | 说明 |
|---|---|---|
| kind | MonsterKind | 逻辑类型（用于配方匹配） |
| scene | PackedScene | 生成用场景 |
| max_hp | int | 最大生命 |
| weak_hp | int | 进入虚弱阈值（当前为 1） |
| hit_stun | float | 受击僵直（默认 0.1） |
| flash_time | float | 闪白持续（例如 0.06） |
| tags | Array[String] | 可选：如 `air/ground/armored` |

### B3. ChimeraRecipe（融合配方表）

每条配方定义“两只怪物 kind → 产物 chimera kind”。
| 字段 | 类型 | 说明 |
|---|---|---|
| a | MonsterKind | 输入 1 |
| b | MonsterKind | 输入 2 |
| result | ChimeraKind | 输出 |
| consume | bool | 是否消耗输入（当前为 true） |
| fx_time | float | 演出时长（默认 0.5） |
| priority | int | 可选：匹配优先级（数值越大越优先） |

匹配规则（建议）
无序匹配：(a,b) 与 (b,a) 等价。
若存在多条匹配，优先更具体的（可加“优先级”字段）。
### B4. ChimeraDef（奇美拉定义表）

| 字段 | 类型 | 说明 |
|---|---|---|
| kind | ChimeraKind | A/B/C… |
| scene | PackedScene | 生成用场景 |
| type | enum | `ENEMY / INTERACTIVE / MULTILINK` |
| link_required | int | 触发互动需要的链接条数（A=1，B=2） |
| interaction | enum | `FOLLOW_X / ORBIT / ATTACK_ON_CLICK / ...` |
| params | Dictionary | 互动参数（速度、延迟、范围等） |

## C. ChimeraB 详细策划书（可直接按此实现）

### C1. 核心定位

ChimeraB = 双实体组合型互动奇美拉
由两个“子个体 a、b”组成：它们可以分离移动，不要求重叠。
只有当 a 与 b 都被玩家锁链链接住（同时满足）时，才触发互动效果。
### C2. 链接点设计（LinkPoint 体系）

你提出的 LinkPoint（Area2D + link_id）方案是正确且工程上最稳的。
结构建议
ChimeraB（Node2D 或 CharacterBody2D 作为容器）
PartA（CharacterBody2D）
HurtboxA（Area2D，group=EnemyHurtbox，export owner_actor=PartA）
LinkPointA（Area2D，link_id=0，owner_actor=PartA）
PartB（CharacterBody2D）
HurtboxB（Area2D）
LinkPointB（Area2D，link_id=1）
命中规则
Player 的锁链只打 LinkPoint（推荐），这样你就不会出现“type=CharacterBody2D 但不知道是谁”的问题。
LinkPoint 在 on_chain_hit 中转发：
如果 ChimeraB 未处于可互动（例如还没满足某条件），返回 0（让锁链溶解）。
如果允许链接，则返回 1，并把 slot -> link_id 记录到 ChimeraB 内部。
### C3. ChimeraB 互动效果（你定义的版本）

互动效果仅在满足“双链接”时开启：
会飞（不落地、无重力或弱重力）。
跟随玩家但带延迟和波动：
目标点 = 玩家附近某个偏移点（例如玩家上方 40px），
移动使用“弹簧/缓动”形式（慢于玩家，带一点惯性）。
不会自动攻击：
当玩家鼠标点击（即发射锁链的按键）时，ChimeraB 播放攻击动画。
然后在攻击范围内判定伤害（Area2D Hitbox 或圆形检测）。
### C4. ChimeraB 状态机（建议）

IDLE：未满足双链接，不做互动，a/b 维持原地或基础行为。
HALF_LINKED：只链住其中一个 LinkPoint；不触发互动，仅提示（可选 UI）。
ACTIVE：双链接满足，开始跟随玩家漂浮。
ATTACKING：收到玩家点击触发攻击，进入短暂攻击状态。
COOLDOWN：攻击后冷却（避免连续点击刷伤害）。
断链条件
任意一个 slot 断裂/溶解 → 退出 ACTIVE → 回到 HALF_LINKED/IDLE。
### C5. 关键参数（直接暴露为 @export）

follow_speed（跟随速度）
follow_lag（延迟强度）
orbit_noise_amp / orbit_noise_freq（波动幅度与频率）
attack_cooldown
attack_range / attack_damage
link_timeout（可选：双链接需要在多少秒内完成，否则重置）
## D. 未设计怪物与奇美拉：可扩展策划模板 + 具体提案

下面给你一套“只要填表就能扩”的设计框架，并附上几种很实用的怪物/奇美拉提案（都能和锁链系统强耦合，且易实现）。
### D1. 新怪物模板（每个怪物建议回答这些）

kind / max_hp / weak_hp
移动方式（地面/飞行/贴墙/瞬移）
攻击方式（近战/投射/范围/召唤）
锁链交互（满血命中：扣血并溶解；弱态命中：可链接）
弱态表现（停止移动/坠落/眩晕/护盾破裂）
融合偏好（和谁融合产出什么）
### D2. 新怪物提案（你可以马上加 kind）

1）MonsterTank（kind=TANK，max_hp=7）
满血：移动慢，受击僵直更短（更“硬”）
弱态：跪地不动（可链接）
特点：适合和 WALK 组合产出“护卫型奇美拉”（例如 ChimeraC：挡子弹或推开敌人）
2）MonsterTurret（kind=TURRET，max_hp=4）
固定炮台：定时朝玩家方向射击
弱态：停止射击（可链接）
特点：适合和 FLY 组合产出“浮游炮奇美拉”（类似你对 ChimeraB 的一部分）
3）MonsterPhase（kind=PHASE，max_hp=3）
有短暂“无敌相位”，锁链命中时返回 2（忽略），必须在非相位窗口命中才生效
弱态：相位失效，完全僵直（可链接）
特点：用于教学“观察节奏”但实现成本低
4）MonsterSwarm（kind=SWARM，max_hp=2）
小型群体单位：数只一起
弱态：单只停下（可链接）
特点：给锁链系统提供“快速制造可融合材料”的乐趣
### D3. 新奇美拉提案（除 A、B 外）

ChimeraC（敌对型）
配方例：TANK + WALK = ChimeraC
行为：原地/巡逻攻击玩家，融合只是“制造更危险敌人”
工程简单：不需要链接互动接口
ChimeraD（互动型：防御/护盾）
配方例：TANK + FLY = ChimeraD
互动：链链接期间，玩家获得减伤或一次护盾（断链即失效）
表现：跟随玩家但不攻击
ChimeraE（互动型：开锁/解谜）
配方例：WALK2 + FLY2 = ChimeraE
互动：链链接期间，它会去激活某些机关（极适合你后续做动作解谜）
## E. 你现在遇到的“类型不对/击中没反应/闪白不生效”在规范上怎么定位

给第三方一个最短检查链路（工程排错必备）：
Player 的射线究竟命中了什么？ 应该命中：EnemyHurtbox 或 LinkPoint（Area2D）。 如果日志只看到 CharacterBody2D，说明你命中的还是本体，不是 Hurtbox。
命中对象是否能解析到逻辑主体？ Hurtbox/LinkPoint 必须能返回 MonsterBase/ChimeraBase，并且这些主体必须实现 on_chain_hit。
受击闪白为什么“不生效”？ 必须确保 _visual 指向的是实际渲染节点（Sprite2D/AnimatedSprite2D/Node2D 容器）。 如果你 modulate 的是空节点、或渲染在子节点，视觉不会变。
以上三条写进规范，第三方照着查，不会迷路。
## F. 建议的“下一步交付物”（你后面做内容会省大量时间）

一个 GameDefs.gd（或资源文件）集中放：MonsterDef、ChimeraDef、Recipe 表
EnemyHurtbox / LinkPoint 的两个小场景做成“拖拽即用”
ChimeraBase.gd 抽象基类，统一处理链接计数/互动状态开关
这些文书怎么样告诉codex才能让他遵守？直接发给他？还是需要写入什么文件？
两种都行，但最稳的是“写进仓库里的规范文件 + 在 Codex 任务里强制引用它”。只把文字贴给 Codex，短期有效，过几轮就容易漂移。
推荐做法（工程上最稳）
1）把规范写成仓库文件（单一真相来源）
在项目根目录加一个文件，例如：
docs/CHAIN_AND_CHIMERA_SPEC.md（规范/接口契约）
docs/GAME_DEFS.md（数据表字段与配方规则）
可选：docs/ARCHITECTURE.md（整体架构）
把我刚整理的内容放进去，尤其是：
必须实现的接口：on_chain_hit / on_chain_attached / on_chain_detached
返回值约定（0/1/2）
Hurtbox/LinkPoint 的职责与命中规则
MonsterDef/ChimeraDef/Recipe 表字段
这样 Codex 每次改代码都能被你要求“以该文件为准”。
2）在每次让 Codex 干活时，用“硬约束提示词”
你给 Codex 的任务开头固定包含这段结构（直接复制即可）：
目标：你要他做什么（例如“实现 ChimeraB 的双链接”）
约束：必须遵守哪个规范文件
验收：必须给出哪些内容（修改了哪些文件、如何测试、日志关键词）

#### Codex 任务提示词示例

```text
请先阅读并遵守：docs/CHAIN_AND_CHIMERA_SPEC.md 与 docs/GAME_DEFS.md。
任何实现必须严格符合接口契约：
- on_chain_hit(player, slot, hit_world)->int  返回0/1/2
- on_chain_attached(slot, player, hit_world)
- on_chain_detached(slot)
任务：实现 ChimeraB（双实体A/B，分别有LinkPoint link_id=0/1），只有当两个LinkPoint都被锁链LINKED时触发互动效果（飞行跟随+点击攻击）。
要求：
1) 不允许改动 Player 的锁链核心行为（除非规范允许且写明原因）
2) 必须通过 LinkPoint / EnemyHurtbox 命中，不得直接靠 CharacterBody2D 命中
3) 提供修改文件列表、关键代码片段、以及可复现测试步骤（含日志关键词）
```

3）把“接口契约”再固化成代码层面的硬错误（防漂移）
只靠文档还不够，建议你加一个小脚本做“运行时断言”，让不符合接口的对象直接报错，Codex 会被迫修正。

```gdscript
# 例如在 Player 的命中逻辑里（开发阶段）：
如果命中对象解析不到 on_chain_hit：push_error("Hit target missing on_chain_hit: %s" % node)
如果返回值不是 0/1/2：直接报错并溶解
这样 Codex 一旦写偏，游戏就红字狂报，它会立刻回到规范。
```

你问的“直接发给他” vs “写入文件”
只发聊天文本：快，但容易遗忘/漂移。
写入仓库文件：稳定、可追溯、可反复引用（推荐）。
最佳组合：写入文件 + 每次任务提示里强制引用文件 + 运行时断言。
最小行动清单（你现在就能做）
新建 docs/CHAIN_AND_CHIMERA_SPEC.md，把规范粘进去保存。
新建 docs/GAME_DEFS.md，把 MonsterDef/Recipe/ChimeraDef 格式粘进去保存。
以后每次给 Codex 下任务，第一句固定写： “先阅读并遵守 docs/CHAIN_AND_CHIMERA_SPEC.md 与 docs/GAME_DEFS.md，任何更改不得违反。”
（可选但强烈建议）在 Player 命中处加断言，逼他遵守接口。
你帮我创建这个md文件并且把刚才的内容全部写进去让我可以下载

---

## 附录：日语小尾巴（可忽略）

- 仕様書（しようしょ）＝“规格说明书”。例句：仕様書（しようしょ）を共有（きょうゆう）して、実装（じっそう）の認識（にんしき）を揃（そろ）えます。（共享规格说明书，统一实现认知。）
- 拡張性（かくちょうせい）＝“可扩展性”。例句：拡張性（かくちょうせい）を優先（ゆうせん）して、データ駆動（くどう）でレシピを追加（ついか）できる設計（せっけい）にします。（优先可扩展性，做成数据驱动可追加配方的设计。）
- 規約（きやく）＝“规范/契约”。例句：実装（じっそう）は規約（きやく）に従（したが）い、例外（れいがい）がある場合（ばあい）は理由（りゆう）を明記（めいき）する。（实现遵循规范，有例外则明确写理由。）
