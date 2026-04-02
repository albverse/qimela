# Dialogue Manager × Spine 对话演出系统 发注蓝图 v1.4

## 1. 项目目的

基于 **Dialogue Manager** 制作一套**黑暗奇幻风格的角色绑定式气泡对话 UI**，并与 **Spine 立绘场景**联动。

目标不是普通底栏文本框，而是：

- 当前发言气泡显示在发言者一侧
- 上一句自动后移到上方历史槽，并降为 50% 透明
- 再下一句时，该历史气泡彻底淡出
- 角色立绘全部为 **独立 Spine 场景**
- 角色的表情、说话、过渡动画由独立控制器自动解析
- 使用 **Dialogue Manager 负责文本资源、跳转、条件、变量与运行时遍历**
- 所有最终演出 UI 由**自定义对话舞台层**负责，不依赖插件自带默认气泡表现

---

## 2. 实现原则

### 2.1 优先利用 Dialogue Manager 原生能力
原生优先利用的部分：

#### A. 对话资源与运行时遍历
使用 Dialogue Manager 负责：

- `.dialogue` 文件编辑
- cue / jump / responses / conditions / mutations
- `DialogueManager.get_next_dialogue_line(...)`
- `DialogueManager.show_dialogue_balloon_scene(...)`（仅作为可选包装入口）

#### B. 自定义 Balloon / 自定义舞台
Dialogue Manager 允许使用**自定义 balloon scene**，也允许完全手动遍历行。

本项目推荐：

- **不依赖插件默认 example balloon 结构**
- 使用项目自己的 `DialogueStage` / `DialogueRunner` 作为主控
- 由主控内部调用 `get_next_dialogue_line(...)` 驱动 UI、Spine、历史气泡推进
- `DialogueLabel` 只作为打字机文本组件使用

#### C. 行数据作为元信息入口
Dialogue Manager 没有 Dialogic 的 `portrait` / `extra_data` 这一套原生角色入口。

因此本项目统一改为以下两种入口：

1. **行标签（tags）**：承载 emotion、talk、role、bubble style 等轻量元数据
2. **mutation / extra_game_states**：承载会话级配置、运行时状态与少量主动触发逻辑

#### D. 自定义 Spine Portrait Scene
每个角色使用 **独立 Spine 场景**，但它不属于插件原生 portrait 系统，而是属于项目自定义舞台的一部分。

也就是说：

- Dialogue Manager 只提供“谁在说、说什么、这一句附带什么标签”
- Spine 立绘、气泡槽位、历史句推进都由项目自定义控制器负责

### 2.2 不使用默认 Example Balloon 作为最终结构
Dialogue Manager 自带的 example balloon 只适合作为示例，不能直接承载本项目需求。

原因：

- 示例气泡本质是单气泡推进
- 没有“当前句 + 历史句”双槽历史逻辑
- 没有独立双侧角色立绘舞台
- 没有玩家皮肤自动同步与明暗同步
- 没有按本项目要求的 talk / transition / history 管理

因此必须制作：

- 自定义 `DialogueStage`
- 自定义 `BubbleSlotManager`
- 自定义 `DialogueMetaResolver`
- 自定义 `SpinePortraitController`
- 自定义 `ExpressionTransitionResolver`

插件只负责“给你行数据”，不负责“替你做演出”。

---

## 3. UI 核心需求

### 3.1 UI 类型
这是**角色绑定式气泡对话 UI**，不是底栏式 AVG 文本框。

屏幕同一时刻只保留：

- **1 个当前气泡**
- **1 个历史气泡**

### 3.2 固定槽位
系统不是自由飘动，而是固定槽位逻辑。

需要四个可编辑槽位：

- `player_current_slot`
- `other_current_slot`
- `player_history_slot`
- `other_history_slot`

注意：

- 历史槽不是全局一个固定居中位置
- **玩家历史槽** 和 **对方历史槽** 必须分开
- 这样才能从位置上表达“上一句是谁说的”
- 四个槽位位置都要能在编辑器里直接调整

### 3.3 气泡推进规则

#### 规则A：同一方连续发言
例如右侧连续说三句：

- 第1句：显示在 `other_current_slot`
- 第2句：第1句移动到 `other_history_slot`，透明度降到 50%；第2句出现在 `other_current_slot`
- 第3句：第1句彻底淡出；第2句移动到 `other_history_slot`，第3句继续在 `other_current_slot`

#### 规则B：发言者切换
例如玩家说完，对方接话：

- 玩家当前句移动到 `player_history_slot`，降为 50%
- 对方新句出现在 `other_current_slot`
- 下一句再推进时，旧历史气泡彻底淡出

#### 规则C：任何时刻最多只保留一个历史气泡
上方历史槽**始终只有一个历史气泡**。
新历史气泡进入时，旧历史气泡必须淡出并销毁。

### 3.4 气泡动画需求

#### 当前句出现
- 透明度从 0 到 1
- 可带轻微缩放或轻微位移
- 保持最高阅读优先级

#### 当前句转历史句
- 从当前槽平滑移动到对应历史槽
- 透明度降到 `0.5`
- 可适度降层级或降亮度

#### 历史句淡出
- 在下一句开始时淡出
- 不允许硬切消失

### 3.5 超长文本转历史时的缩略规则
必须追加一条 UI 规格：

#### 触发条件
- 当当前句文本长度 **大于 100 字** 时，当前气泡允许因正文过长而被拉高或拉宽
- 但当该气泡在下一句到来时被转入历史槽，**不能继续保留完整长文本尺寸**

#### 历史态处理规则
- 转为历史气泡时，只显示原文本的**前 20 字**
- 缩略文本后建议追加省略标记，例如：`……`
- 历史气泡必须回到预设的**正常历史尺寸**，不能继续沿用长文本撑大的尺寸
- 该缩略只作用于**历史态显示**，不改变原句的完整文本内容

#### 设计目的
- 保持历史槽的 UI 美观与版式统一
- 避免长句历史气泡挤压角色立绘或破坏双侧构图
- 保证当前句可完整阅读，历史句只承担“提醒上一句内容”的作用

#### 实现要求
- `BubbleSlotManager` 在“当前句 -> 历史句”推进时，必须执行历史文本摘要逻辑
- 需要保留 `full_text` 与 `history_preview_text` 两份内容：
  - `full_text`：当前句完整显示与逻辑使用
  - `history_preview_text`：历史态缩略显示
- 历史气泡尺寸应基于独立的 history layout 重新计算，而不是对当前大气泡简单缩放

### 3.6 气泡样式可选
必须支持**玩家气泡样式**和**对方气泡样式**独立选择。

至少要有：

- `player_bubble_style`
- `other_bubble_style`

并且这两者应支持：

- 在编辑器里设默认值
- 在对话开始时动态指定
- 每次对话可换不同样式

备注：

- Dialogue Manager 本身不管理这类气泡样式资源
- 最终由 `BubbleStyleController` 根据会话配置与每句 override 应用样式

---

## 4. Spine 立绘系统需求

### 4.1 每个角色必须是独立 Spine 场景
所有角色立绘都不是贴图，而是**单独的 Spine 场景实例**。

一个角色 = 一个独立 Spine Portrait Scene。

### 4.2 每个 Spine 场景至少包含
建议结构：

- `PortraitRoot`
- `SpineNode`
- `BubbleAnchor`
- `PortraitController`

可选扩展：

- `NameAnchor`
- `FaceAnchor`
- `FXAnchor`

其中：

- `BubbleAnchor`：给气泡归属使用
- `PortraitController`：负责表情 / 说话 / 过渡 / 皮肤 / 部件逻辑

### 4.3 皮肤系统需求（修正版）
**取消“由使用者在对话开头手动指定玩家立绘皮肤”的方案。**

改为系统主动决定：

#### 玩家立绘皮肤自动选择
- 玩家立绘的皮肤，必须根据**当前玩家小人（游戏内角色实例）身上实际穿着的皮肤**自动决定
- 对话系统不应要求使用者手动选择玩家立绘服装皮肤
- 读取当前玩家小人的 skin 名称后，自动切换到同名的立绘 skin
- 默认约定：**小人皮肤名与立绘皮肤名同名**

例如：

- 玩家小人当前 skin = `hero_school_uniform`
- 对话立绘自动切换为 `hero_school_uniform`

#### 玩家立绘亮暗状态自动选择
皮肤还有亮暗两个状态，对应不同明度场景。
系统需要根据玩家所在场景的光照设定，自动切换立绘皮肤的亮暗版本。

规则：

- 当前场景为暗设定 -> 自动启用立绘皮肤的 **暗状态**
- 当前场景为亮设定 -> 自动启用立绘皮肤的 **亮状态**

也就是说，玩家立绘最终使用的皮肤并非单一名，而是：

- 基础服装皮肤：由玩家小人当前 skin 决定
- 亮/暗变体：由当前场景明度标记决定

例如：

- 玩家小人 skin = `hero_school_uniform`
- 场景明度 = dark
- 立绘最终使用：`hero_school_uniform_dark`

或采用项目内部约定的其他命名，只要规则统一即可。

#### 对方角色皮肤
对方角色仍允许通过**行标签**、**会话状态**或**场景配置**指定 skin。
但玩家角色必须优先采用“从当前玩家小人自动同步”的机制。

#### 实现要求
必须存在一个 **PlayerPortraitSkinResolver**，负责：

- 读取当前玩家小人的 skin
- 读取当前场景的亮/暗状态
- 组合成当前应使用的立绘 skin
- 通知玩家 Spine Portrait Scene 切换 skin

这部分不能依赖手动配置，必须系统主动完成。

### 4.4 场景亮暗状态接口要求
必须有统一接口供对话系统读取当前场景是“亮”还是“暗”。

建议不要让对话系统自行推算光照，而由场景或全局环境系统直接提供明确标记，例如：

- `light_state = bright`
- `light_state = dark`

或等价的布尔/枚举值。

对话系统只负责读取，不负责判断。

---

## 5. 表情 / 说话 / 过渡动画需求

### 5.1 控制目标
角色动画系统不能要求策划或 AI 每句都手写完整动画链。
而应由一个**状态解析器**根据“上一状态”和“本句目标状态”自动补全过程。

### 5.2 统一命名规范
动画命名统一，便于自动解析。

#### 稳定状态
- `idle_loop`
- `angry_loop`
- `sad_loop`
- `fear_loop`

#### 过渡状态
- `idle_to_angry`
- `angry_to_idle`
- `idle_to_sad`
- `sad_to_idle`

#### 说话状态
- `idle_talk_loop`
- `angry_talk_loop`
- `sad_talk_loop`

不要混用 `idle_to_talk` 这种不统一形式。
统一后，AI 才能可靠补全。

### 5.3 talk 状态规则
所有 `*_talk_loop` 都不是长期停留状态。

固定规则：

- 文字显示期间：播放 `emotion_talk_loop`
- **文字打字机完成时**：停止 talk，回到 `emotion_loop`
- **玩家强制推进时**：也必须立即退出当前 talk 状态
- 如果下一句也是 talk，则下一句的 talk 动画必须**重新从头播放**

也就是说：

- `text_finished` -> 退出 talk
- `force_advance` -> 退出 talk
- `next_talk_line` -> talk 动画重新开始，不延续上一句的中间帧

### 5.4 状态解析器规则
系统需要一个独立的 **Expression Transition Resolver**。

输入：

- 上一句结束后的稳定状态
- 本句目标情绪
- 本句是否需要 talk
- 本句结束后停留状态

输出：

- 进入过渡动画
- 当前说话动画
- 文本结束后的停留状态
- 下一句切换时的退出路径

### 5.5 解析示例

#### 示例1：从平静进入生气并说话
上一状态：`idle_loop`
本句目标：`angry + talk`

应自动理解为：

- `idle_to_angry`
- `angry_talk_loop`
- 文本结束后 -> `angry_loop`

完整链：

`idle_loop -> idle_to_angry -> angry_talk_loop -> angry_loop`

#### 示例2：保持生气但继续下一句说话
上一句结束后状态：`angry_loop`
下一句目标：`angry + talk`

应自动理解为：

- 直接播放 `angry_talk_loop`
- 文字结束后回 `angry_loop`

完整链：

`angry_loop -> angry_talk_loop -> angry_loop`

注意：
即使还是 angry，也必须**重新播一次 angry_talk_loop**，不能直接接着上句末尾。

#### 示例3：从生气回到平静
上一状态：`angry_loop`
本句目标：`idle`

应自动理解为：

- `angry_to_idle`
- `idle_loop`

完整链：

`angry_loop -> angry_to_idle -> idle_loop`

#### 示例4：从平静变生气，但本句不说话
上一状态：`idle_loop`
本句目标：`angry + no talk`

应自动理解为：

- `idle_to_angry`
- `angry_loop`

完整链：

`idle_loop -> idle_to_angry -> angry_loop`

### 5.6 过渡动画缺失时的兜底
如果缺少某个 `from_to_to` 过渡动画：

- 有过渡动画：优先播放
- 没有过渡动画：短混合切到目标 loop
- 不允许因为缺少过渡而报错卡死

例如没有 `angry_to_idle`：

- 直接短混合到 `idle_loop`

---

## 6. 组件化要求（不要把逻辑写死成一坨）

即使当前用整套 Spine 动画，也必须按“部件化思路”设计控制器。

也就是：

- 情绪稳定状态
- 说话状态
- 皮肤状态
- 亮暗状态
- 气泡样式状态
- 将来可能扩展的眼睛 / 嘴 / 眉 / 附件

这些都不能硬塞成一大串 if-else 拼动画名。
必须预留独立控制层。

---

## 7. 数据输入格式要求

### 7.1 对话开始时的全局配置
在对话开始时通过 `DialogueRunner.start_dialogue(resource, title, config)` 的 `config` 字典设置本轮会话配置：

```gdscript
var config: Dictionary = {
    # 角色名 → role 映射
    "character_role_map": { "Hero": "player", "Cultist": "other" },
    # 气泡默认样式纹理路径
    "player_bubble_style": "res://art/bubble_player_dark_01.png",
    "other_bubble_style": "res://art/bubble_enemy_dark_02.png",
    # 额外气泡纹理注册（可通过 bubble_style tag 引用）
    "bubble_textures": {
        "explosion": "res://art/bubble_explosion.png",
        "thinking": "res://art/bubble_thinking.png",
    },
    # 气泡材质注册（可通过 bubble_material tag 引用）
    "bubble_materials": {
        "explosion": preload("res://materials/bubble_explosion_mat.tres"),
    },
    # 立绘 shader 注册（可通过 portrait_shader tag 引用）
    "portrait_shaders": {
        "dark_aura": preload("res://shaders/dark_aura_mat.tres"),
    },
    # 场景亮暗状态
    "light_state": "bright",
    # 可选：传入玩家节点引用（皮肤同步时使用）
    "player_node": player_node,
}
```

注意：

- **不再手动传入 `player_skin`**
- 玩家立绘皮肤应由系统从玩家小人自动解析
- 对方皮肤仍允许通过事件或角色配置指定
- 纹理、材质、shader 均通过注册表模式管理，在 config 中注册后即可在 tags 中按 key 引用

### 7.2 每句台词的状态输入
每句台词前，系统应能接受结构化状态，而不是只写动画名。

补充说明：
- **不建议**把“是否缩略历史文本”做成逐句随意开关
- 该规则默认属于全局 UI 规格，由历史态系统统一执行
- 只有在将来确实出现特殊演出需要时，才追加逐句 override

推荐字段：

```json
{
  "speaker_role": "player",
  "emotion": "angry",
  "use_talk": true,
  "after_text": "keep",
  "skin_override": "",
  "bubble_style_override": "",
  "portrait_effect": "",
  "portrait_shader": "",
  "bubble_anim": "",
  "bubble_material": ""
}
```

字段说明：

- `speaker_role`：`player / other / narrator`
- `emotion`：目标情绪
- `use_talk`：本句是否张嘴说话
- `after_text`：
  - `keep`：保持当前情绪 loop
  - 指定情绪：文本结束后转到该情绪
- `skin_override`：本句临时切 skin（主要用于非玩家角色）
- `bubble_style_override`：本句临时改气泡样式
- `portrait_effect`：立绘动效命令（`fade_in` / `fade_out` / `slide_in` / `slide_out` / `shake`）
- `portrait_shader`：立绘附着 shader 标识（需在 session config 中注册对应 ShaderMaterial）
- `bubble_anim`：气泡动效命令（`shake` / 或 AnimationPlayer 中的自定义动画名）
- `bubble_material`：气泡材质标识（需在 session config 中注册对应 Material，如 `explosion` / `thinking`）

#### 推荐默认逻辑
如果 `after_text = keep`：

- `angry + talk` -> 文本结束后停在 `angry_loop`
- `idle + talk` -> 文本结束后停在 `idle_loop`

### 7.3 在 Dialogue Manager 中的落地方式
Dialogue Manager 本身返回的是：

- `DialogueLine.character`
- `DialogueLine.text`
- `DialogueLine.tags`
- `DialogueLine.responses`
- `DialogueLine.next_id`

因此本项目规定：

#### A. 行级元数据优先写入 tags
推荐写法（每个 tag 独立 `[#key=value]`，确保 Dialogue Manager 正确解析）：

```text
Hero: [#role=player] [#emotion=angry] [#talk=true] [#after=keep] 这不是雨。
Cultist: [#role=other] [#emotion=idle] [#talk=true] [#bubble_style=bubble_enemy_dark_02] 那是幸福之雨。
Hero: [#role=player] [#emotion=idle] [#talk=true] [#portrait_effect=shake] [#bubble_anim=shake] 什么……！？
Cultist: [#role=other] [#emotion=angry] [#talk=true] [#bubble_material=explosion] 你已经没有退路了！
```

解析后：

- `role` -> 气泡槽位归属
- `emotion` -> 目标情绪
- `talk` -> 是否说话
- `after` -> 文本结束后停留状态
- `bubble_style` -> 本句样式 override
- `skin` -> 本句皮肤 override
- `portrait_effect` -> 立绘动效命令（fade_in / fade_out / slide_in / slide_out / shake）
- `portrait_shader` -> 立绘附着 shader 标识
- `bubble_anim` -> 气泡动效命令（shake / 自定义动画名）
- `bubble_material` -> 气泡材质标识（需在 session config 注册）

#### B. 会话级配置通过 extra_game_states 或启动参数注入
例如：

- `DialogueSessionState.player_bubble_style`
- `DialogueSessionState.other_bubble_style`
- `DialogueSessionState.light_state`
- `DialogueSessionState.player_skin_sync_enabled`

#### C. 主动逻辑通过 mutation 调用
例如：

```text
do DialogueHooks.RefreshPlayerPortrait()
do DialogueHooks.SetConversationStyle("ritual_dark")
```

但必须控制使用频率。
**不要把每句都写成大量 do 调用。**
轻量、重复、结构化的信息优先放 tags。

### 7.4 关于旁白
允许 `narrator` 存在。

规则：

- 旁白不触发任何角色 talk 动画
- 不强制占用 player / other 当前槽
- 旁白 UI 属于后续可扩展项，不与本次 player/other 双侧气泡逻辑耦合死

---

## 8. Dialogue Manager 对接规范

### 8.1 Dialogue Manager 原生负责什么
Dialogue Manager 负责：

- 时间线资源与文本编辑
- cue / jump / response / condition / mutation
- 对话运行时遍历
- `DialogueLine` 数据生成
- `DialogueLabel` 的打字机文本能力
- 通过 `extra_game_states` 暴露游戏状态给条件与变量系统

### 8.2 自定义模块负责什么

#### A. DialogueRunner
职责：

- 持有当前 `DialogueResource`
- 调用 `await DialogueManager.get_next_dialogue_line(...)`
- 管理当前 `next_id`
- 处理 response 选择后的跳转
- 在 stage、Spine、标签、输入系统之间当调度中心

#### B. DialogueStage
职责：

- 作为最终演出舞台节点
- 管理左右立绘、气泡层、历史层、旁白层
- 接收 `DialogueRunner` 分发的行数据
- 驱动当前句 / 历史句 / 淡出逻辑

#### C. BubbleSlotManager
职责：

- 管理 `player_current_slot`
- 管理 `other_current_slot`
- 管理 `player_history_slot`
- 管理 `other_history_slot`
- 当前句/历史句动画推进
- 历史气泡淡出销毁

#### D. BubbleStyleController
职责：

- 应用玩家/对方气泡样式
- 支持默认样式 + 运行时 override
- 支持历史态透明度/颜色变化

#### E. DialogueMetaResolver
职责：

- 从 `DialogueLine.character` 与 `DialogueLine.tags` 解析本句结构化状态
- 解析 `speaker_role`
- 解析 `emotion`
- 解析 `use_talk`
- 解析 `after_text`
- 解析 `skin_override`
- 解析 `bubble_style_override`

#### F. SpinePortraitController
每个角色一个。负责：

- 皮肤切换
- 亮暗状态切换
- 表情状态切换
- talk 启停
- 过渡动画播放
- 兜底短混合
- 当前稳定状态记录

#### G. ExpressionTransitionResolver
职责：

- 解析上一稳定状态
- 生成当前句的动画链
- 管理 `finished_typing` 和 `force_advance` 时的退出行为

#### H. PlayerPortraitSkinResolver
仅玩家角色需要。负责：

- 从玩家小人读取当前 skin
- 从场景/环境系统读取亮暗状态
- 组合出玩家立绘应使用的目标 skin
- 通知玩家 Spine Portrait Scene 切换到正确皮肤

---

## 9. 推荐的 Dialogue Manager 使用方式

### 9.1 总体建议
本项目推荐使用：

- **Dialogue Manager 作为文本编辑器 + 运行时解释器**
- **项目自定义 DialogueRunner / DialogueStage 作为真正的演出层**

不推荐把最终实现建立在插件自带 example balloon 上再不断魔改。

### 9.2 启动方式
推荐两种方式：

#### 方式A：完全手动遍历（推荐）

- 项目自己实例化 `DialogueStage`
- 调用 `await DialogueManager.get_next_dialogue_line(...)`
- 手动把 `DialogueLine` 交给舞台层

优点：

- 结构清晰
- AI 易读易改
- 更适合重度定制 UI

#### 方式B：使用 `show_dialogue_balloon_scene(...)` 包装自定义 stage

- 让 Dialogue Manager 负责打开一个自定义 balloon scene
- 自定义 scene 内部仍然采用自己的 stage / runner 逻辑

优点：

- 对接插件入口更统一

缺点：

- 对本项目这种重演出方案，收益不大

### 9.3 玩家皮肤同步
玩家皮肤**不通过手动事件输入**。
而是由 `PlayerPortraitSkinResolver` 自动完成：

- 对话开始时同步一次
- 如有必要，在对话中支持再次同步
- 玩家小人换装后，对话立绘可以重新读取并刷新

### 9.4 对方角色皮肤切换
对方角色允许通过以下任一方式指定：

- 行 tags：`[#skin=cult_uniform_a]`
- 会话状态默认值
- 场景内角色配置

### 9.5 气泡样式切换
建议允许通过以下任一方式指定：

- 行 tags：`[#bubble_style=bubble_player_dark_02]`
- 会话配置默认值
- mutation 修改会话状态

### 9.6 每句情绪控制
不靠角色 portrait 名进行分发。
统一使用：

- `DialogueLine.tags`
- `DialogueMetaResolver`
- `ExpressionTransitionResolver`

来决定本句动画逻辑。

---

## 10. 跳过 / 强制推进规则

### 10.1 打字机结束
当最后一个字显示出来时：

- 当前 `*_talk_loop` 必须结束
- 自动进入对应 `*_loop`

本项目应监听 `DialogueLabel.finished_typing`，而不是只根据肉眼显示状态推断。

### 10.2 玩家强制推进
当玩家强制推进当前句时：

- 若还在打字：先 `skip_typing()`
- 当前 talk 状态必须立即结束
- 立即准备切入下一句目标状态
- 如果下一句还是 talk：
  - 必须从新一轮 `*_talk_loop` 起点重新播
  - 不能沿用旧句 talk 的中间状态

### 10.3 跳过行为不能让角色卡在嘴巴开合状态
任何跳过、快进、强制推进后，角色都必须落在一个合法稳定态或下一句合法进入态。

---

## 11. 编辑器可调项

以下参数必须暴露到编辑器，而不是写死在脚本里：

### 槽位
- `player_current_slot_position`
- `other_current_slot_position`
- `player_history_slot_position`
- `other_history_slot_position`

### UI动画
- 当前句入场时间
- 转历史句移动时间
- 历史句淡出时间
- 历史透明度（默认 0.5）

### 样式
- `player_bubble_style`
- `other_bubble_style`
- 每句 override 入口

### 历史文本缩略
- `history_shrink_threshold`（默认 100 字）
- `history_preview_char_count`（默认 20 字）
- `history_preview_suffix`（默认 `……`）
- 历史气泡正常尺寸配置（宽/高或最小/最大尺寸）

### 角色
- 对方默认 skin
- 默认气泡样式
- 默认 side / role
- 玩家皮肤同步开关（通常应开启）
- 玩家亮暗同步开关（通常应开启）

---

## 12. AI 不得误解的点

1. 不是普通 VN 底栏，核心是双侧角色气泡 + 单历史气泡机制。
2. 历史槽不是全局一个固定点，必须有：
   - 玩家历史槽
   - 对方历史槽
3. talk 不是停留状态，它只是“本句说话期间”的临时状态。
4. 下一句如果还是 talk，必须重播，不能把上一句 talk 中途接过去。
5. 过渡动画要自动补，不要要求使用者每句手写完整链。
6. 玩家立绘皮肤必须由系统主动读取玩家小人的当前皮肤，不再手动指定。
7. 玩家立绘亮暗状态必须由系统主动读取当前场景明度状态，不再手动指定。
8. Dialogue Manager 在本项目里主要是**文本运行时与数据来源**，不是最终 UI 框架。
9. `character` 只够表示“谁在说话”，不够表达完整状态；本项目必须依赖 tags / 会话状态补足结构化信息。
10. 默认 example balloon 不是最终方案，只能参考其取行与输入节奏。
11. 超过阈值的长文本，在转入历史槽时必须缩略为前 20 字并恢复正常历史尺寸；当前态仍显示全文。

---

## 13. 验收样例

### 样例A：玩家从平静到生气说话，再保持生气
输入：

- 上一句结束状态：`idle_loop`
- 本句 tags：`role=player, emotion=angry, talk=true`

预期：

- 气泡出现在玩家当前槽
- 播放：`idle_to_angry -> angry_talk_loop`
- 打字结束后：`angry_loop`

### 样例B：对方接话
输入：

- 上一句是玩家 angry
- 下一句 tags：`role=other, emotion=idle, talk=true`

预期：

- 玩家当前句移动到玩家历史槽，50% 透明
- 对方当前句出现在对方当前槽
- 对方播放 `idle_talk_loop`
- 打字结束后停在 `idle_loop`

### 样例C：同一人连续说两句
输入：

- 第一句：`other angry talk`
- 第二句：`other angry talk`

预期：

- 第一句结束后 -> `angry_loop`
- 第二句开始时，第一个气泡移动到对方历史槽
- 新句再次播放 `angry_talk_loop`
- talk 必须重播，不允许沿用前一句

### 样例D：强制推进
输入：

- 当前句仍在 `angry_talk_loop`
- 玩家点击强制推进到下一句 `idle_talk_loop`

预期：

- 当前句立刻退出 `angry_talk_loop`
- 进入 `angry_to_idle`（若存在）
- 再进入新句 `idle_talk_loop`
- 新句 talk 从头播放

### 样例E：玩家服装自动同步
输入：

- 玩家小人当前 skin = `hero_school_uniform`
- 当前场景明度 = `dark`
- 开始对话

预期：

- 玩家立绘自动切换到对应 dark 版本皮肤
- 不需要手动传入 `player_skin`
- 对话过程中若刷新立绘，同步结果仍保持一致

---


### 样例F：超长文本转历史缩略
输入：

- 玩家当前句文本长度：`132 字`
- 下一句开始，当前句需要从 `player_current_slot` 转入 `player_history_slot`

预期：

- 当前句在阅读阶段仍完整显示 132 字
- 转历史时，只显示前 20 字 + `……`
- 历史气泡尺寸恢复为正常历史规格
- 不允许历史槽保留被长文本撑大的超大气泡

---

---

## 14. AI 实现风险规避与结构约束（强制执行）

本章不是建议，而是**必须写进发注与实施规范中的硬约束**。
目的只有一个：**尽可能防止 AI 把系统写成能跑但难维护的一坨逻辑。**

### 14.1 总体判断
本项目允许 AI 参与实现，但**不允许 AI 自行决定系统分层**。

必须先固定以下事实：

1. **Dialogue Manager 只负责对话资源与行数据运行时**
2. **最终 UI 演出层全部由项目自定义组件负责**
3. **Spine 动画状态与气泡状态不能混写在同一个脚本里**
4. **长文本历史缩略不能作为临时补丁写进单个 label 逻辑里**
5. **任何“先写成一版再说”的跨层捷径都视为不合格实现**

### 14.2 必须固定的模块边界
AI 只能在以下模块职责内写代码，不允许越层偷写：

#### A. `DialogueRunner`
职责仅限：
- 启动 / 停止对话
- 调用 `DialogueManager.get_next_dialogue_line(...)`
- 推进下一行
- 将 `DialogueLine` 交给 `DialogueStage`
- 不允许直接操作气泡 UI
- 不允许直接控制 Spine 动画

#### B. `DialogueStage`
职责仅限：
- 接收当前行数据
- 调度 `BubbleSlotManager`
- 调度 `BubbleStyleController`
- 调度 `DialogueMetaResolver`
- 调度 `SpinePortraitController`
- 接收输入事件（继续、跳过、强制推进）
- 不允许自己拼接动画名
- 不允许自己解析玩家皮肤命名规则

#### C. `DialogueMetaResolver`
职责仅限：
- 从 `DialogueLine.character`、`tags`、会话状态中解析结构化元数据
- 输出统一格式的数据对象，例如：
  - `speaker_role`
  - `emotion`
  - `use_talk`
  - `after_text`
  - `skin_override`
  - `bubble_style_override`
- 不允许直接操作任何节点树
- 不允许在这里执行 UI 动画

#### D. `BubbleSlotManager`
职责仅限：
- 当前气泡创建
- 当前 -> 历史推进
- 历史淡出销毁
- 长文本历史缩略
- 位置 / 层级 / 透明度 / 尺寸变化
- 不允许读取 Dialogue 文件
- 不允许控制 Spine 动画

#### E. `BubbleStyleController`
职责仅限：
- 根据 role / style id / history state 应用样式资源
- 不允许决定气泡什么时候迁移
- 不允许解析对话标签

#### F. `SpinePortraitController`
职责仅限：
- 接收结构化状态指令
- 切皮肤
- 切亮暗
- 播放表情 loop / talk / transition
- 提供安全兜底
- 不允许自己决定何时进入下一句文本

#### G. `ExpressionTransitionResolver`
职责仅限：
- 根据“上一稳定态 + 本句目标态”输出动画链
- 不允许访问 UI 节点
- 不允许持有输入逻辑

#### H. `PlayerPortraitSkinResolver`
职责仅限：
- 读取玩家当前 skin
- 读取场景亮暗状态
- 组合 portrait skin
- 输出最终 skin id
- 不允许写入对话文本
- 不允许直接驱动气泡系统

### 14.3 禁止 AI 采用的实现方式
以下做法必须明确禁止：

1. **禁止把所有逻辑塞进一个 `dialogue_balloon.gd`**
2. **禁止在 `DialogueLabel` 脚本里顺手处理历史气泡迁移**
3. **禁止在 `SpinePortraitController` 中直接读取 `DialogueLine.tags`**
4. **禁止在 `BubbleSlotManager` 中拼接动画名**
5. **禁止用大量 if-else 直接硬编码所有情绪与 talk 组合**
6. **禁止把长文本历史缩略写成“直接改当前 label 的 text 再缩放”**
7. **禁止把玩家皮肤同步写成依赖人工传参的临时方案**
8. **禁止为省事而把 `current bubble` 直接复用成 `history bubble` 而不重算 layout**
9. **禁止没有兜底就直接播放某个 transition 动画**
10. **禁止先写耦合版本再说后面重构；本项目默认 AI 不擅长二次重构，必须第一次就按分层写**

### 14.4 必须先定义的数据契约
AI 写代码前，必须先固定统一数据结构。
不允许边写边改字段名。

建议最小结构：

```gdscript
class_name DialogueLineMeta
var speaker_role: StringName       ## player / other / narrator
var emotion: StringName            ## 目标情绪（idle / angry / sad / fear）
var use_talk: bool                 ## 本句是否播放 talk 动画
var after_text: StringName         ## 打字完成后停留状态：keep = 保持当前情绪
var skin_override: StringName      ## 本句临时皮肤 override
var bubble_style_override: StringName ## 本句临时气泡样式 override
var speaker_id: StringName         ## 说话者标识（角色名）
var portrait_effect: StringName    ## 立绘动效命令（fade_in / fade_out / slide_in / slide_out / shake）
var portrait_shader: StringName    ## 立绘附着 shader 标识
var bubble_animation: StringName   ## 气泡动效命令（shake / none）
var bubble_material_key: StringName ## 气泡材质标识（default / explosion / thinking）
```

建议最小气泡视图数据：

```gdscript
class_name BubblePayload
var full_text: String
var history_preview_text: String
var speaker_role: StringName
var speaker_name: String            ## 说话者显示名
var bubble_style_id: StringName
var is_history: bool
var bubble_animation: StringName    ## 气泡动效命令
var bubble_material_key: StringName ## 气泡材质标识
```

建议最小立绘控制数据：

```gdscript
class_name PortraitCommand
var target_emotion: StringName
var use_talk: bool
var after_text: StringName
var resolved_skin: StringName
var light_state: StringName
var portrait_effect: StringName     ## 立绘动效命令
var portrait_shader: StringName     ## shader 附着标识
```

要求：

- 字段名一旦确定，不得在 AI 后续任务中擅自改名
- 新增字段只能向后兼容，不能破坏旧调用
- 所有控制器之间只传数据对象，不直接跨层找节点

### 14.5 AI 的任务拆分方式（必须分阶段）
不允许给 AI 一次性任务：“把整套系统全部实现完”。

必须分为以下阶段：

#### 第 1 阶段：只做纯文本气泡系统
目标：
- 不接 Spine
- 不接皮肤
- 不接复杂情绪
- 只验证四槽位推进 + 历史淡出 + 长文本缩略

通过标准：
- 连续发言、发言切换、超长文本转历史都正确

#### 第 2 阶段：接入 `DialogueManager.get_next_dialogue_line(...)`
目标：
- 让文本来自 `.dialogue`
- 支持 tags 解析
- 仍不接 Spine 动画

通过标准：
- 可以稳定读取一整段对话
- 跳过与继续不破坏气泡推进

#### 第 3 阶段：接入 Spine Portrait 基础控制
目标：
- 只做 `idle_loop` / `*_talk_loop` / `text_finished -> loop`
- 暂不做复杂 transition

通过标准：
- talk 开始与结束正确
- 连续两句同情绪 talk 必须重播

#### 第 4 阶段：接入 `ExpressionTransitionResolver`
目标：
- 引入 `from_to_to` 过渡动画
- 做缺失动画兜底短混合

通过标准：
- `idle -> angry -> talk -> angry_loop`
- `angry -> idle -> talk`
- 缺动画时不报错不卡死

#### 第 5 阶段：接入玩家皮肤同步与亮暗同步
目标：
- 完成 `PlayerPortraitSkinResolver`
- 完成 bright / dark 与基础服装皮肤组合

通过标准：
- 换玩家 skin 与场景 light_state 后，portrait 能稳定刷新

### 14.6 每阶段都必须有独立验收样例
AI 每完成一个阶段，必须提供：

1. 改了哪些脚本
2. 每个脚本新增了什么职责
3. 哪些脚本**没有改**
4. 本阶段通过哪些验收样例
5. 还没实现什么

不允许输出“已全部完成”这类模糊说法。

### 14.7 必须保留的日志与调试输出
为了防止 AI 写出看似能跑、实际状态错乱的代码，必须保留以下日志开关：

- 当前 `DialogueLine.id`
- 当前 `speaker_role`
- 当前 `emotion`
- 当前 `use_talk`
- 当前稳定态
- 当前播放动画
- 当前历史气泡文本是否缩略
- 当前 resolved player skin
- 当前场景 `light_state`

要求：

- 日志必须能通过一个总开关关闭
- 日志文本必须统一前缀，例如 `[DialogueStage]`、`[BubbleSlot]`、`[SpinePortrait]`
- 不允许每个脚本随意 print 不带前缀的信息

### 14.8 强制推进与跳过的硬规则
这是最容易被 AI 写崩的部分，必须单列规则：

1. 当前句仍在打字时：
   - 第一次推进 = 先完成当前句打字
   - 不直接跳到下一句，除非项目明确另定规则
2. 当前句打字已完成：
   - 再推进才进入下一句
3. 若当前处于 `*_talk_loop`：
   - 在 `finished_typing`
   - 或 `skip_current_typing`
   - 或 `force_advance_to_next_line`
   时，都必须退出 talk，落回合法稳定态或合法过渡起点
4. 下一句若也是 talk：
   - 必须重新从 talk 起点播放
   - 禁止沿用上一句 talk 的中间帧

### 14.9 长文本历史缩略的硬规则
这一条不得被 AI 简化或曲解：

1. 缩略判定基于**原始完整文本长度**
2. 当前态必须始终保留完整文本
3. 历史态只负责显示摘要，不承担全文阅读
4. 历史摘要不得反向覆盖 `full_text`
5. 历史气泡必须使用独立 layout 重新计算尺寸
6. 若以后支持富文本、ruby、名字标签，摘要逻辑也必须集中在一个函数中，不允许散落在多个 UI 脚本里

建议固定函数：

```gdscript
func build_history_preview_text(full_text: String, preview_char_count: int, suffix: String = "……") -> String
```

### 14.10 版本与依赖冻结规则
为了避免 AI 按错 API 写代码，必须在蓝图中锁定：

- Godot 版本：`4.6`
- Dialogue Manager 版本：项目内固定版本，不允许 AI 擅自升级
- Spine runtime 版本：项目当前已接入版本，不允许 AI 擅自替换接口写法
- 所有新增脚本默认使用 **Godot 4.6 最新写法**

如果遇到任何 API 不确定项：

- 先查项目内现有代码写法
- 再查当前固定插件版本
- 不允许凭记忆猜接口名

### 14.11 AI 输出格式要求
以后让 AI 实现时，必须强制要求它按以下格式回答：

1. **本次只实现哪个阶段**
2. **新增/修改的脚本路径**
3. **每个脚本新增的函数名**
4. **本次不改哪些文件**
5. **为什么这样分层**
6. **本次验收步骤**
7. **已知未覆盖风险**

不接受整段无结构说明，也不接受“我顺手把其他层也合并优化了”。

### 14.12 允许的 AI 工作范围
AI 适合负责：

- 规则明确的 UI 状态机
- Bubble 迁移与淡出
- 历史缩略逻辑
- 标签解析
- 结构化控制器骨架
- Godot 4.6 下的标准脚本搭建

AI 不应被直接放权负责：

- 自行决定整体架构
- 自行改动项目已有 Spine 控制接口
- 在没有验收样例的情况下重构多层系统
- 一次性写完整个演出系统

### 14.13 结构验收优先级
验收时优先级必须是：

1. **结构是否干净**
2. **状态是否可追踪**
3. **边界是否清楚**
4. **功能是否正确**
5. **代码是否好看**

即使功能能跑，只要出现以下任一情况，也视为不合格：

- 关键逻辑跨层乱写
- 模块职责不清
- 没有 fallback
- 没有独立摘要函数
- 没有日志可追踪
- 通过硬编码拼接规避状态机设计

---

## 15. 对 AI 的实施口令模板（建议直接附在发注后）

以下文字可直接给 AI，作为实现限制条件：

> 你只允许在本次任务范围内实现指定阶段，不允许跨层顺手重构。
> 必须严格遵守以下模块职责：`DialogueRunner` 只负责取行推进；`DialogueStage` 只负责调度；`BubbleSlotManager` 只负责气泡生命周期；`SpinePortraitController` 只负责立绘控制；`ExpressionTransitionResolver` 只负责状态链解析；`PlayerPortraitSkinResolver` 只负责玩家皮肤解析。
> 禁止把逻辑写进一个总脚本里。禁止在 UI 层直接拼接动画名。禁止在立绘层直接读取对话 tags。
> 本次输出必须包含：修改文件路径、每个文件新增函数、未改文件、验收方法、未覆盖风险。
> 若存在 API 不确定项，不允许猜测，必须先对照项目当前版本写法。
> 本次实现优先保证结构正确、边界清晰、可调试，其次才是功能扩展。

---

## 16. 最终实施建议

### 插件原生部分
- Dialogue Manager 对话编辑器
- cue / jump / response / condition / mutation
- `DialogueManager.get_next_dialogue_line(...)`
- `DialogueLabel`
- `extra_game_states`

### 定制部分
- `DialogueRunner`
- `DialogueStage`
- `BubbleSlotManager`
- `BubbleStyleController`
- `DialogueMetaResolver`
- `SpinePortraitController`
- `ExpressionTransitionResolver`
- `PlayerPortraitSkinResolver`

### 结构结论
这条路**可以实现目标效果**，而且比 Dialogic 版本更适合重度定制。

但前提是要接受一个事实：

**Dialogue Manager 不是帮你做成图中 UI 的插件，它只是把“文本流 + 条件分支 + 行元数据”稳定交给你。**

---

## 17. 当前项目对标落地进度（2026-04-02 更新）

> 本章用于把蓝图规范与当前仓库实现逐条对齐。
> 标记说明：
> - ✅ 已实现（与规范一致）
> - 🔄 已实现但有调整（相对蓝图有职责/实现位置变化）
> - 🆕 本轮新增（2026-04-02 审计后新增）
> - ⚠️ 部分实现（已具备基础能力，仍有后续优化空间）

### 17.1 总体架构对标

- ✅ 已采用 `DialogueRunner` + `DialogueStage` + 控制器分层结构。
  - `DialogueRunner` 负责取行、起停、衔接下一句。含防重入锁（`_is_advancing`）和防双重信号保护。
  - `DialogueStage` 负责 UI/输入门控/响应选项显示与舞台调度。含 `_has_ended` 防止 `finish()` 重入。
  - `BubbleSlotManager` 负责气泡生命周期与槽位迁移。
  - `BubbleStyleController` 采用**注册表模式**管理纹理和材质，支持通过 tag 动态切换。
  - `DialogueMetaResolver`、`SpinePortraitController`、`ExpressionTransitionResolver`、`PlayerPortraitSkinResolver` 按职责拆分。
- 🔄 输入职责从”Runner 拦截”调整为”Stage 拦截 + Runner 仅驱动流程”。
- 🆕 `DialogueRunner` 对话起停时通过 `EventBus.dialogue_input_lock_requested/released` 广播输入锁定状态。

### 17.2 UI 槽位系统（AB 历史 / CD 当前）对标

- ✅ 四槽位逻辑已实现并可在编辑器拖动 Marker2D 调整。
- ✅ CD 区同一时刻仅一个当前气泡；下一句出现时上一句迁移到历史区（A/B），再下一句时旧历史淡出。
- ✅ 气泡与槽位以 `custom_minimum_size` 为基准做中心对齐。
- 🆕 支持**视口百分比槽位定位**（`viewport_relative_enabled`），开启后按百分比计算位置，自动适配不同分辨率。默认关闭，使用 Marker2D 模式。
- ⚠️ 历史态布局仍基于当前气泡实例转换；若后续需要”历史态独立 prefab”，可再扩展。

### 17.3 responses 分支能力对标

- ✅ `ResponsesLayer/ResponsesContainer` 支持动态生成按钮。
- ✅ `dialogue_response_selected(next_id)` 信号，选择后回写到流程推进。
- ✅ 分支选择后由 Runner 按 `next_id` 继续 `get_next_dialogue_line(...)`。
- ✅ responses 显示期间吞掉非按钮输入。
- 🆕 `ResponsesContainer` 改用 anchor 百分比布局，适配不同分辨率。

### 17.4 输入策略对标

- ✅ 对话期间仅鼠标左键用于推进（非 responses 场景）。
- 🆕 `_input()` 统一拦截**所有事件类型**（`InputEventMouseButton`、`InputEventKey`、`InputEventJoypadButton`、`InputEventScreenTouch` 等），全部 `set_input_as_handled()`。不再需要 `_unhandled_input()` 兜底。
- 🆕 **responses 显示时 _input 的处理策略**：当 responses 可见时，所有鼠标事件（包括 press 和 release）全部放行，不调用 `set_input_as_handled()`，确保 Godot GUI 系统能将点击传递给 Button 节点。仅非鼠标事件（键盘/手柄等）被吞掉。修复了此前鼠标释放事件被 `set_input_as_handled()` 拦截导致 Button.pressed 信号永远不触发的 bug。
- 🆕 `DialogueRunner` 通过 `EventBus.emit_dialogue_input_lock_requested()` / `emit_dialogue_input_lock_released()` 广播锁定状态，player / inventory 等系统可订阅此信号主动禁用自身输入处理。
- ✅ 对话激活态通过 `set_dialogue_active(true/false)` 显式门控。
- 🆕 `_advance_to_next_line()` 增加 `_is_advancing` 防重入锁，防止 `await` 期间快速点击导致并发推进。

### 17.5 立绘系统对标

- ✅ `SpinePortrait` 作为独立场景，支持独立实例化与参数调节。
- ✅ 入场滑入效果：支持 `offset_x / duration / ease / trans`，贝塞尔缓入缓出可调。
- ✅ player 与 other 可配置相反方向滑入。
- 🆕 **立绘动效命令系统**：通过 `[#portrait_effect=X]` tag 触发立绘动效。支持的动效：
  - `fade_in`：淡入（透明度 0→1，时长由 `fade_in_duration` 控制）
  - `fade_out`：淡出（透明度→0，时长由 `fade_out_duration` 控制）
  - `slide_in`：滑入（使用入场滑入动画参数）
  - `slide_out`：滑出（使用退场滑出动画参数）
  - `shake`：抖动（强度/持续时间/频率均 `@export` 可调）
  - **自定义动画名**：未匹配内置动效时自动尝试 AnimationPlayer 中的同名动画。美术人员只需在 SpinePortrait 的 AnimationPlayer 中创建动画，即可通过 `[#portrait_effect=动画名]` 直接在对话中调用。
  - 统一入口 `SpinePortraitScene.play_effect(effect_name)`，按名称分发，兜底到 `play_custom_animation()`。
- 🆕 `SpinePortrait.tscn` 已包含 `AnimationPlayer` 节点，美术可直接在编辑器中添加自定义动画。
- 🆕 **立绘 Shader 附着系统**：
  - Shader 文件存放于 `dialogue_system/shaders/` 目录。
  - 在 session config 中注册 ShaderMaterial：`”portrait_shaders”: { “blink”: shader_mat }`
  - 通过 `[#portrait_shader=blink]` tag 触发附着。
  - `SpinePortraitScene.apply_shader(shader_id)` / `clear_shader()` 负责实际操作。
  - shader 作用于 SpineSprite 的 `material` 属性。
  - 已提供示例：`dialogue_system/shaders/portrait_blink.gdshader`（闪烁效果）+ `portrait_blink_material.tres`。

### 17.6 皮肤同步策略对标

- ✅ 默认可关闭 `player_skin_sync_enabled` 与 `light_state_sync_enabled`。
- ✅ 保留了接口与解析链路，后续素材到位可直接启用。
- 🔄 本阶段策略是”默认关闭 + 保留接口”，而非”删除功能入口”。

### 17.7 气泡样式与动效系统对标

- ✅ `DialogueBubble` 保持独立场景，可单独替换纹理、材质、动画播放器。
- 🆕 **BubbleStyleController 注册表模式**：
  - `_texture_registry`：key → Texture2D 或路径字符串，首次使用时自动 load 并缓存。
  - `_material_registry`：key → Material 或路径字符串，同上。
  - 通过 `register_texture(style_id, texture_or_path)` / `register_material(material_key, material_or_path)` 注册。
  - `[#bubble_style=X]` tag 的 `style_override` **实际生效**——查注册表匹配纹理。此前仅接收参数但不执行查找。
  - `apply_style_to_bubble()` 一次性应用纹理+材质。
- 🆕 **气泡材质动态切换**：
  - 在 session config 注册：`”bubble_materials”: { “explosion”: mat, “thinking”: mat }`
  - 通过 `[#bubble_material=explosion]` tag 切换当前气泡的 BubbleBG 材质。
  - 传 null key 时不变更材质。
- 🆕 **气泡入场方向滑入**：
  - 新气泡从说话者方向斜向滑入 slot 目标位置。
  - player 气泡从右侧滑入，other 气泡从左侧滑入。
  - 偏移距离：`bubble_slide_in_offset`（默认 50px，`@export` 可调）。
  - 倾斜角度：`bubble_slide_in_angle`（默认 15°，`@export` 可调）。
  - 滑入过程中透明度从 0 到 1。
- 🆕 **气泡抖动动效**：
  - 通过 `[#bubble_anim=shake]` tag 触发。
  - Tween 实现：衰减式随机偏移，强度/持续时间/频率均 `@export` 可调。
  - 抖动在入场动画结束后自动执行，避免冲突。
  - 也支持通过 `play_custom_animation(name)` 播放 AnimationPlayer 中的自定义动画。
- 🆕 **说话者名字显示**：
  - `BubblePayload.speaker_name` 携带说话者名字。
  - `BubbleSlotManager._create_bubble()` 创建气泡后调用 `set_speaker_name()`。
  - `NameLabel` 节点在 `DialogueBubble.tscn` 中已存在，现已正确连线。
- ✅ 结构兼容 `NinePatchRect` / `TextureRect`。

### 17.8 可复用基架对标

- ✅ `DialogueTestScene` 实例化标准 `DialogueStage.tscn` 与标准 `SpinePortrait.tscn`。
- ✅ 测试场景支持通过 config 注册纹理、材质、shader。
- 🆕 测试 dialogue 文件新增 `~ effect_test` 段落，覆盖 portrait_effect / bubble_anim / bubble_material 标签。

### 17.9 生命周期与稳定性对标

- ✅ `SpinePortrait.setup_controller()` 幂等保护。
- ✅ `reset_controller()` 在对话结束时调用。
- ✅ `stop_talk()` 发出 `talk_finished` 信号。
- 🆕 `DialogueStage.finish()` 增加 `_has_ended` 保护，防止重复调用导致信号多发。
- 🆕 `DialogueRunner._finish()` 和 `_on_dialogue_finished()` 通过 `_is_running` 互斥，确保 `dialogue_ended` 只 emit 一次。
- 🆕 `_advance_to_next_line()` 增加 `_is_advancing` 互斥锁，await 期间不允许重入。

### 17.10 SFX 音效钩子对标

- 🆕 新增 4 个 EventBus 音效信号（预留接口，音频制作完毕后连接）：
  - `dialogue_sfx_typewriter_tick` — 打字机逐字音效
  - `dialogue_sfx_bubble_appeared` — 气泡出现音效
  - `dialogue_sfx_bubble_to_history` — 气泡移入历史区音效
  - `dialogue_sfx_portrait_changed` — 立绘切换/动效触发音效
- 🆕 `BubbleSlotManager` 在气泡创建/移入历史时自动通过 EventBus 发出对应信号。
- 🆕 `DialogueStage` 在立绘入场/动效触发时发出 `portrait_changed` 信号。

### 17.11 死代码清理对标

- 🆕 移除 `DialogueBubble` 中从未使用的 `@export`：`min_bubble_size`、`max_bubble_width`、`patch_margin_left/top/right/bottom`。
- 🆕 移除 `BubbleStyleController` 中从未被调用的 `apply_current_style()` 方法。
- 🆕 移除 `DialogueStage` 中存在竞态风险的 `_unhandled_input()` 方法，功能合并到 `_input()`。

### 17.12 当前数据契约实际字段（与代码一致）

#### DialogueLineMeta
| 字段 | 类型 | 默认值 | 来源 tag |
|------|------|--------|---------|
| `speaker_role` | `StringName` | `&”other”` | `role` |
| `emotion` | `StringName` | `&”idle”` | `emotion` |
| `use_talk` | `bool` | `true` | `talk` |
| `after_text` | `StringName` | `&”keep”` | `after` |
| `skin_override` | `StringName` | `&””` | `skin` |
| `bubble_style_override` | `StringName` | `&””` | `bubble_style` |
| `speaker_id` | `StringName` | `&””` | 自动从 `line.character` 读取 |
| `portrait_effect` | `StringName` | `&””` | `portrait_effect` |
| `portrait_shader` | `StringName` | `&””` | `portrait_shader` |
| `bubble_animation` | `StringName` | `&””` | `bubble_anim` |
| `bubble_material_key` | `StringName` | `&””` | `bubble_material` |

#### BubblePayload
| 字段 | 类型 | 说明 |
|------|------|------|
| `full_text` | `String` | 完整文本 |
| `history_preview_text` | `String` | 历史缩略文本 |
| `speaker_role` | `StringName` | player / other |
| `speaker_name` | `String` | 说话者显示名 |
| `bubble_style_id` | `StringName` | 气泡样式 override key |
| `is_history` | `bool` | 是否历史态 |
| `bubble_animation` | `StringName` | 气泡动效命令 |
| `bubble_material_key` | `StringName` | 气泡材质 key |

#### PortraitCommand
| 字段 | 类型 | 说明 |
|------|------|------|
| `target_emotion` | `StringName` | 目标情绪 |
| `use_talk` | `bool` | 是否播放 talk |
| `after_text` | `StringName` | 文本后停留状态 |
| `resolved_skin` | `StringName` | 解析后皮肤名 |
| `light_state` | `StringName` | 亮暗状态 |
| `portrait_effect` | `StringName` | 立绘动效命令 |
| `portrait_shader` | `StringName` | shader 附着标识 |

### 17.13 当前文件清单（与仓库一致）

```
dialogue_system/
├── controllers/
│   ├── bubble_slot_manager.gd        # BubbleSlotManager — 四槽位气泡生命周期
│   ├── bubble_style_controller.gd    # BubbleStyleController — 注册表模式样式/材质管理
│   ├── dialogue_meta_resolver.gd     # DialogueMetaResolver — tag 解析（含 11 个 tag key）
│   ├── expression_transition_resolver.gd  # ExpressionTransitionResolver — 动画链解析
│   ├── player_portrait_skin_resolver.gd   # PlayerPortraitSkinResolver — 玩家皮肤解析
│   └── spine_portrait_controller.gd  # SpinePortraitController — Spine 动画状态机
├── data/
│   ├── bubble_payload.gd             # BubblePayload — 气泡视图数据（8 字段）
│   ├── dialogue_line_meta.gd         # DialogueLineMeta — 行元数据（11 字段）
│   └── portrait_command.gd           # PortraitCommand — 立绘控制指令（7 字段）
├── scenes/
│   ├── DialogueBubble.tscn           # 气泡场景（NinePatchRect + RichTextLabel + NameLabel + AnimationPlayer）
│   ├── DialogueStage.tscn            # 舞台场景（CanvasLayer L10 + 4 Marker2D + ResponsesLayer）
│   ├── SpinePortrait.tscn            # 立绘场景（SpineContainer + SpineSprite + BubbleAnchor）
│   ├── dialogue_bubble.gd            # DialogueBubble — 打字机 + 抖动 + 样式
│   ├── dialogue_runner.gd            # DialogueRunner — 流程推进 + 输入锁定广播
│   ├── dialogue_stage.gd             # DialogueStage — 舞台调度 + 全输入拦截
│   └── spine_portrait.gd             # SpinePortraitScene — 动效 + shader + 滑入滑出
└── (共 15 文件)
```

### 17.14 当前状态总览（便于项目管理）

**已完成主路径：**
- 文本推进、AB/CD 槽位、历史迁移与缩略、打字机、立绘入场、responses 选择。
- 全输入拦截（所有事件类型）+ EventBus 输入锁定广播。
- 气泡方向滑入 + 抖动动效 + 材质/样式注册表切换。
- 立绘动效命令（shake / fade_in / fade_out / slide_in / slide_out）+ shader 附着。
- 说话者名字显示。
- SFX 音效钩子（4 个 EventBus 信号）。
- 视口百分比槽位定位（可选）。
- 防重入、防双重信号、死代码清理。

**后续可选增强项（非阻塞）：**
1. 历史态专用 prefab 与独立布局策略；
2. 皮肤/亮暗同步启用后的项目联调规范（待美术素材）；
3. 更细粒度的 responses 焦点导航与手柄支持；
4. 旁白（narrator）专用 UI 样式与槽位；
5. 对话历史回看面板；
6. 对话跳过/快进模式（按住键快速跳过已读对话）；
7. 打字机逐字 SFX 实际触发（当前仅预留信号，需在 DialogueBubble 打字 tween 中每字 emit）。
