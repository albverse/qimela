# PROJECT_CONTEXT.md（稳定事实）

## 引擎版本
- **Godot 4.5**（以对话后期用户明确说明为准；已作废：任何早于该描述的 4.3/4.4/4.x 泛称）

## 项目一句话 + 类型
- 一句话：**2D 动作解谜 / 战斗 + “锁链捕获与合成奇美拉”系统原型**（目前以主测试场景验证为主）
- 类型：横版（平台跳跃）+ 锁链投射（类似“子弹射出”）+ 怪物虚弱/链接 + 双链接融合生成奇美拉

## 核心系统清单（已确定事实）
1. **玩家移动**：A/D 左右、W 跳跃；视觉翻转仅翻 `Visual`（不翻物理本体）。
2. **双锁链系统（两根）**：鼠标左键按下发射；两根链优先用空闲槽位（0/1）。
3. **锁链投射（子弹式）**：链端从手部发射，使用 Raycast / direct_space_state `intersect_ray` 做逐段命中检测。
4. **锁链状态机（已出现）**：`IDLE / FLYING / STUCK / (LINKED) / DISSOLVING`（LINKED 在“虚弱怪物”命中时出现）。
5. **锁链视觉（炫酷链条）**：用 `Line2D` + 纹理平铺 + 点列（Verlet + 约束迭代 + 波动注入）。
6. **长度上限与预警**：`chain_max_length` 超长自动溶解；接近上限时链条渐变变红（warn_start_ratio 等参数）。
7. **溶解特效**：使用 shader（文件路径固定为 `res://shaders/chain_sand_dissolve.gdshader`）在 `burn_time` 内溶解。
8. **怪物基础机制（已实现方向）**：满血被链命中 -> HP-1 + 受击僵直 0.1s + 变亮/变白“闪白”；HP==1 进入虚弱（飞行停悬/陆行停走）。
9. **融合（SPACE / action_fuse）**：两根锁链分别 LINKED 到两只虚弱怪物时，按空格触发融合演出（锁玩家 `fusion_lock_time=0.5s`），怪物消失、锁链加速溶解、在玩家附近生成 ChimeraA。
10. **ChimeraA（已存在脚本）**：被锁链“链接”后触发互动效果：陆行追随玩家 X（带速度/加速度/阈值）。

## 关键约束 / 偏好（对实现有约束力）
- Godot Shader：**不使用 `hint_color`**；颜色 uniform 用 `vec3/vec4` 并直接赋默认值。
- 节点树展示要求：给节点树时必须清晰标注“新增/旧节点”，避免建议“全局层 ChainLayer”等容易造成结构不一致的做法。
- “数据A”回退基准：用户已明确**锁链系统的某一版 Player.gd + RopeSim2D.gd 为回退基准**（下方参数表记录其关键数值）。
- 输入偏好：**W 跳跃**（不使用空格跳跃）；**鼠标左键发射锁链**；X 取消链条功能已禁用（不再依赖 X）。
- 物理碰撞偏好：玩家与怪物/奇美拉**可设置为不发生实体碰撞**，但仍需：落地/重力有效、锁链命中有效、攻击/受击有效（通过 Hurtbox/Hitbox 或射线 mask 实现）。
- 资源路径要求：shader 的正确路径仅有：`res://shaders/chain_sand_dissolve.gdshader`（不得写错）。

## 关键文件清单（路径未知则标注）
- `player.gd`（路径未知，但文件名明确；用户已上传并在工程中替换使用）
- `RopeSim2D.gd`（路径未知；用于 RopeSim2D 测试/或作为参考实现）
- `MonsterBase.gd`（路径未知）
- `MonsterFly.gd`（路径未知）
- `MonsterWalk.gd`（路径未知）
- `ChimeraA.gd`（路径未知；`class_name ChimeraA`）
- Shader：`res://shaders/chain_sand_dissolve.gdshader`（路径明确）
- 备注：对话中出现过 `rope.gd` / `RopeSim2D.tscn` 的报错与清理；现阶段以 Player 集成的链条实现为主。

## 关键参数表（来自对话“数据A”与当前脚本出现的关键数值）
> 说明：若当前工程脚本值与“数据A”不同，需在变更史里标注；此处先记录双方关键值与含义。

| 参数名 | 数据A默认 | 近期脚本出现值 | 含义 / 验收点 |
|---|---:|---:|---|
| move_speed | 260 | 260 | 玩家水平速度 |
| jump_speed | 520 | 520 | 跳跃初速度（W） |
| gravity | 1500 | 1500 | 玩家重力 |
| chain_speed | 1200 | 1200 | 链端飞行速度 |
| chain_max_length | **550** | **450（出现过）** | 链条最大拉伸长度；超出触发溶解（必须可见且稳定） |
| chain_max_fly_time | 0.2 | 0.2 | 飞行超时转 STUCK |
| hold_time | 0.3 | 0.3 | STUCK 悬停后开始溶解 |
| burn_time | 1.0 | 1.0 | 溶解时长（融合时可用更短 dissolve_time） |
| rope_segments | 22 | 22 | Line2D 点数 = segments+1 |
| rope_damping | 0.88 | 0.88 | Verlet 阻尼 |
| rope_stiffness | 1.7 | 1.7 | 约束刚性 |
| rope_iterations | 13 | 13 | 约束迭代次数（稳定性） |
| rope_gravity | 0.0 | 0.0 | 绳子自重（需要更“垂”时调大） |
| rope_wave_amp | 44 | 44 | 发射瞬间“全绳抖动”幅度 |
| rope_wave_freq | 10 | 10 | 抖动频率 |
| rope_wave_decay | 7.5 | 7.5 | 抖动衰减速度（越大越快恢复） |
| rope_wave_hook_power | 2.2 | 2.2 | 钩子端权重（抖动/注入更集中于端部） |
| end_motion_inject | 0.5 | 0.5 | 端点运动注入（钩子端） |
| hand_motion_inject | 0.15 | 0.15 | 手端运动注入 |
| warn_start_ratio | 0.80 | 0.80 | 断裂预警开始比例 |
| warn_gamma | 1.6 | 1.6 | 预警曲线（越大越后期才红） |
| texture_anchor_at_hook | true | true | UV 锚定在钩子端，使“展开/缩进”只发生在手端 |
| fusion_lock_time | - | 0.5 | 融合演出锁玩家时长 |
| fusion_chain_dissolve_time | - | 0.5 | 融合时两条链更快溶解时间 |
| MonsterFly max_hp | - | 3 | 飞行怪物最大HP |
| MonsterWalk max_hp | - | 5 | 陆行怪物最大HP |
| weak阈值 | - | HP==1 | 进入虚弱状态的判定 |

## Boss 行为与规则（已在项目设定中确认，但可能未实现）
- Boss：漂浮无重力 AI。
- 远距离规则：玩家离 Boss 过远时，Boss 会把“灵魂”瞬间移动到玩家附近可操纵物体并附身攻击。
- 若玩家附近无可附身物体：Boss 启动“瞬移”，耗时 1 秒；1 秒后瞬移到**触发时刻（1秒前记录）的玩家位置**。
