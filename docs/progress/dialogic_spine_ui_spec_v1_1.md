# Dialogic × Spine 对话演出系统 发注蓝图 v1.1

## 1. 项目目的

基于 **Dialogic** 制作一套**黑暗奇幻风格的角色绑定式气泡对话 UI**，并与 **Spine 立绘场景**联动。

目标不是普通底栏文本框，而是：

- 当前发言气泡显示在发言者一侧
- 上一句自动后移到上方历史槽，并降为 50% 透明
- 再下一句时，该历史气泡彻底淡出
- 角色立绘全部为 **独立 Spine 场景**
- 角色的表情、说话、过渡动画由独立控制器自动解析
- 尽可能优先利用 **Dialogic 原生结构**，只在原生做不到的地方做定制扩展

---

## 2. 实现原则

### 2.1 优先利用 Dialogic 原生能力
原生优先利用的部分：

#### A. 自定义 Layout / Layer
使用 Dialogic 现有结构扩展，不从零重写对话系统：

- `dialogic_layout_base.gd`
- `dialogic_layout_layer.gd`

#### B. 文本生命周期信号
利用 Text 子系统信号驱动 UI 和 Spine：

- `about_to_show_text(info)`
- `text_started(info)`
- `text_finished(info)`
- `speaker_updated(character)`

#### C. 角色进场 / 更新事件
优先利用 Character Event 的原生字段：

- `portrait`
- `extra_data`

其中：

- `portrait`：可继续作为 Dialogic 原生角色 portrait 名使用
- `extra_data`：用于传入气泡样式、side、特殊表情参数等扩展数据

#### D. 自定义 Portrait Scene
每个角色使用 **自定义 Spine Portrait Scene**，该场景继承或包装 Dialogic Portrait 体系，而不是用普通静态图片 portrait。

### 2.2 不能直接用默认 Text Bubble
默认 `Base_TextBubble` 会在新台词出现时关闭其它气泡。
这不符合本项目“当前句 + 历史句”规则。

因此必须制作：

- 自定义 Bubble Base
- 自定义 Bubble Layer
- 自定义 Bubble Slot Manager

但仍挂在 Dialogic 的 Layout / Layer 体系里，不硬改插件底层。

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

### 3.5 气泡样式可选
必须支持**玩家气泡样式**和**对方气泡样式**独立选择。

至少要有：

- `player_bubble_style`
- `other_bubble_style`

并且这两者应支持：

- 在编辑器里设默认值
- 在对话开始时动态指定
- 每次对话可换不同样式

备注：

- 如果 Dialogic 原生机制足够承载“样式资源切换”，优先用原生方式
- 但由于本项目气泡行为本身已定制，最终大概率会采用：
  - Dialogic 原生时间线 / 事件负责切换指令
  - 自定义 Bubble Layer 负责真正应用样式资源

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

或采用你们项目内部约定的其他命名，只要规则统一即可。

#### 对方角色皮肤
对方角色仍允许通过 Dialogic 事件、角色数据或场景配置指定 skin。
但玩家角色必须优先采用“从当前玩家小人自动同步”的机制。

#### 实现要求
必须存在一个**Player Portrait Skin Resolver**，负责：

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
建议在对话开始时设置本轮会话配置：

```json
{
  "player_bubble_style": "bubble_player_dark_01",
  "other_bubble_style": "bubble_enemy_dark_02"
}
```

注意：

- **不再手动传入 `player_skin`**
- 玩家立绘皮肤应由系统从玩家小人自动解析
- 对方皮肤仍允许通过事件或角色配置指定

### 7.2 每句台词的状态输入
每句台词前，系统应能接受结构化状态，而不是只写动画名。

推荐字段：

```json
{
  "speaker_role": "player",
  "emotion": "angry",
  "use_talk": true,
  "after_text": "keep",
  "skin_override": "",
  "bubble_style_override": ""
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

#### 推荐默认逻辑
如果 `after_text = keep`：

- `angry + talk` -> 文本结束后停在 `angry_loop`
- `idle + talk` -> 文本结束后停在 `idle_loop`

### 7.3 关于旁白
允许 `narrator` 存在。

规则：

- 旁白不触发任何角色 talk 动画
- 不强制占用 player / other 当前槽
- 旁白 UI 属于后续可扩展项，不与本次 player/other 双侧气泡逻辑耦合死

---

## 8. Dialogic 对接规范

### 8.1 Dialogic 原生负责什么
Dialogic 负责：

- 时间线推进
- 角色 join / update / leave
- 文本事件触发
- 原生 portrait 事件入口
- 传入 `portrait` 与 `extra_data`

### 8.2 自定义模块负责什么

#### A. BubbleSlotManager
职责：

- 管理 `player_current_slot`
- 管理 `other_current_slot`
- 管理 `player_history_slot`
- 管理 `other_history_slot`
- 当前句/历史句动画推进
- 历史气泡淡出销毁

#### B. BubbleStyleController
职责：

- 应用玩家/对方气泡样式
- 支持默认样式 + 运行时 override
- 支持历史态透明度/颜色变化

#### C. SpinePortraitController
每个角色一个。负责：

- 皮肤切换
- 亮暗状态切换
- 表情状态切换
- talk 启停
- 过渡动画播放
- 兜底短混合
- 当前稳定状态记录

#### D. ExpressionTransitionResolver
职责：

- 解析上一稳定状态
- 生成当前句的动画链
- 管理 `text_finished` 和 `force_advance` 时的退出行为

#### E. PlayerPortraitSkinResolver
仅玩家角色需要。负责：

- 从玩家小人读取当前 skin
- 从场景/环境系统读取亮暗状态
- 组合出玩家立绘应使用的目标 skin
- 通知玩家 Spine Portrait Scene 切换到正确皮肤

---

## 9. 推荐的 Dialogic 使用方式

### 9.1 玩家皮肤同步
玩家皮肤**不通过手动事件输入**。
而是由 `PlayerPortraitSkinResolver` 自动完成：

- 对话开始时同步一次
- 如有必要，在对话中支持再次同步
- 玩家小人换装后，对话立绘可以重新读取并刷新

### 9.2 对方角色皮肤切换
对方角色仍可通过 Character Event 的 `extra_data` 或其他自定义事件传入：

```json
{"skin":"cult_uniform_a"}
```

自定义 Spine Portrait Scene 在 `_set_extra_data()` 中解析并应用。

### 9.3 气泡样式切换
建议允许通过 `extra_data` 或轻量自定义事件传入：

```json
{"bubble_style":"bubble_player_dark_02"}
```

如果只是在对话开始时设置整轮默认值，也可以由时间线开头调用一次 Layout / UI Controller 的设置方法。

### 9.4 每句情绪控制
这里不建议硬塞进默认 TextBubble。
建议使用：

- 一个轻量自定义事件
或
- 对文本事件附带结构化状态数据

原因：
Dialogic 原生文本行只靠 portrait 名不足以完整表达你的状态机需求。

---

## 10. 跳过 / 强制推进规则

### 10.1 打字机结束
当最后一个字显示出来时：

- 当前 `*_talk_loop` 必须结束
- 自动进入对应 `*_loop`

### 10.2 玩家强制推进
当玩家强制推进当前句时：

- 立即结束当前 talk 状态
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
8. 插件原生优先，但不强求为原生而牺牲结构；能用原生 Character Event / Portrait / Layout 就用，原生做不到的 UI 行为，用定制 Layer 完成。

---

## 13. 验收样例

### 样例A：玩家从平静到生气说话，再保持生气
输入：

- 上一句结束状态：`idle_loop`
- 本句：`speaker=player, emotion=angry, use_talk=true`

预期：

- 气泡出现在玩家当前槽
- 播放：`idle_to_angry -> angry_talk_loop`
- 打字结束后：`angry_loop`

### 样例B：对方接话
输入：

- 上一句是玩家 angry
- 下一句：`speaker=other, emotion=idle, use_talk=true`

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

## 14. 最终实施建议

### 原生部分
- Dialogic 时间线
- Dialogic Character Event
- Dialogic Portrait Scene
- Dialogic Text Signals

### 定制部分
- 自定义 Bubble Layout / Layer
- BubbleSlotManager
- BubbleStyleController
- SpinePortraitController
- ExpressionTransitionResolver
- PlayerPortraitSkinResolver

这条路最稳。
既不会和插件底层强耦合，也不会把状态逻辑写烂。
