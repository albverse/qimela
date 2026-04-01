# 对话 UI 美术使用手册

本文档面向美术人员，说明如何在 Godot 编辑器中调整对话系统的视觉表现。
**无需编写任何代码。**

---

## 1. 文件结构总览

```
dialogue_system/
├── scenes/
│   ├── DialogueBubble.tscn    ← 对话气泡（独立场景，美术主要修改此文件）
│   ├── SpinePortrait.tscn     ← 角色立绘（独立场景，每个角色可单独实例）
│   ├── DialogueStage.tscn     ← 舞台模板（含默认槽位布局）
│   ├── dialogue_bubble.gd
│   ├── spine_portrait.gd
│   ├── dialogue_stage.gd
│   └── dialogue_runner.gd
├── controllers/               ← 逻辑控制器（美术一般不需要修改）
└── data/                      ← 数据结构（美术一般不需要修改）
```

---

## 2. 对话气泡调整（DialogueBubble.tscn）

### 2.1 打开方式
在 Godot 编辑器中双击 `dialogue_system/scenes/DialogueBubble.tscn`。

### 2.2 场景节点结构

```
DialogueBubble (Control)          ← 气泡根节点
├── BubbleBG (NinePatchRect)      ← 气泡背景（可替换为 TextureRect）
│   └── MarginContainer           ← 文字边距容器
│       └── DialogueLabel         ← 对话文本（RichTextLabel）
├── NameLabel (Label)             ← 角色名标签
└── AnimationPlayer               ← 气泡动效播放器（可添加自定义动画）
```

### 2.3 更换气泡样式

#### 替换背景纹理
1. 选中 `BubbleBG` 节点
2. 在 Inspector 面板中找到 `Texture` 属性
3. 拖入新的气泡纹理图片
4. 调整 **Patch Margin**（九宫格边距）使拉伸效果正确：
   - `Patch Margin Left / Top / Right / Bottom`
   - 数值应与纹理中不可拉伸区域的像素尺寸一致

#### 切换为 TextureRect（如需 Shader 动效）
如果需要给气泡添加 Shader 效果：
1. 删除 `BubbleBG` (NinePatchRect)
2. 新建 `TextureRect` 并命名为 `BubbleBG`
3. 将 `MarginContainer` 移到新建的 `BubbleBG` 下
4. 在 Inspector → Material 中赋予 `ShaderMaterial`
5. 赋予纹理和编写 shader

> **重要**：背景节点必须命名为 `BubbleBG`，且其下必须有 `MarginContainer/DialogueLabel` 结构。

#### 添加气泡动效
1. 选中 `AnimationPlayer` 节点
2. 创建新动画（如 `idle_breathe`、`enter_bounce` 等）
3. 对 `BubbleBG` 或根节点的 scale / modulate / position 等属性添加关键帧
4. 可在代码中通过 `play_custom_animation("动画名")` 调用

### 2.4 调整文字边距
选中根节点 `DialogueBubble`，在 Inspector 中找到：
- **Text Margin**：`Vector4(左, 上, 右, 下)` — 控制文字与气泡边框的距离

### 2.5 调整气泡尺寸
- **Min Bubble Size**：气泡最小宽高
- **Max Bubble Width**：气泡最大宽度（文字超过时自动换行）

### 2.6 运行时动态更换样式
在 `.dialogue` 文件中通过 tags 指定：
```
Hero: [#role=player, bubble_style=dark_02] 这是使用新样式的对话。
```
需要在 `BubbleStyleController` 中注册对应的样式资源。

---

## 3. 角色立绘调整（SpinePortrait.tscn）

### 3.1 场景节点结构

```
SpinePortrait (Control)           ← 立绘根节点
└── SpineContainer (Node2D)       ← 立绘容器（控制缩放与偏移）
    ├── SpineSprite               ← Spine 骨骼动画节点
    └── BubbleAnchor (Marker2D)   ← 气泡锚定位置（暂留扩展用）
```

### 3.2 可调参数（选中根节点后在 Inspector 中查看）

#### Portrait Transform 分组
| 参数 | 说明 | 建议值 |
|------|------|--------|
| **Portrait Scale** | 立绘缩放 (X, Y) | `(0.8, 0.8)` |
| **Portrait Offset** | 立绘偏移（相对于控件原点） | 根据立绘原点调整 |

#### Slide-In Animation 分组（入场滑入动画）
| 参数 | 说明 | 建议值 |
|------|------|--------|
| **Slide In Enabled** | 是否启用滑入动画 | `true` |
| **Slide In Offset X** | 滑入起始偏移量。正值 = 从右侧滑入，负值 = 从左侧滑入 | 玩家侧 `600`，对方侧 `-600` |
| **Slide In Duration** | 滑入持续时间（秒） | `0.6` |
| **Slide In Ease** | 缓动模式 | `Ease In Out`（推荐） |
| **Slide In Trans** | 过渡曲线类型 | `Cubic`（推荐，柔和的贝塞尔效果） |

> **提示**：`Slide In Offset X` 的正负决定滑入方向。
> 玩家在右侧 → 正值（从右侧屏幕外滑入）；
> 对方在左侧 → 负值（从左侧屏幕外滑入）。

### 3.3 更换立绘 Spine 文件
1. 准备好 `.skel`、`.atlas`、`.png` 三件套
2. 创建 `.tres` (SpineSkeletonDataResource)，引用 atlas 和 skel
3. 选中 SpineSprite 节点，将 `Skeleton Data Res` 指向新的 `.tres`

### 3.4 调整立绘在画面中的位置
直接在 2D 视图中拖动 `SpinePortrait` 控件，或在 Inspector 中修改其 offset/anchor。

---

## 4. 气泡位置调整（Marker2D 锚点系统）

### 4.1 核心概念
对话系统使用 **4 个 Marker2D** 节点作为气泡位置锚点：

| 锚点名称 | 含义 | 位置建议 |
|----------|------|----------|
| **SlotA_OtherHistory** | 对方的历史气泡位置 | 屏幕上方左侧 |
| **SlotB_PlayerHistory** | 玩家的历史气泡位置 | 屏幕上方右侧 |
| **SlotC_OtherCurrent** | 对方的当前气泡位置 | 屏幕中下方左侧 |
| **SlotD_PlayerCurrent** | 玩家的当前气泡位置 | 屏幕中下方右侧 |

### 4.2 调整方式
1. 在场景树中选中对应的 `SlotA` / `SlotB` / `SlotC` / `SlotD` 节点
2. 在 2D 视图中**直接拖动**到想要的位置
3. 运行游戏查看效果
4. 反复微调直到满意

### 4.3 规则说明
- **CD 区（当前对话）同一时刻只保留一个气泡**
- 新的一句话出现时，上一句自动移动到对应的历史位置（A 或 B）
- 历史气泡透明度自动降低，再下一句时彻底淡出
- 示例流程：
  1. 玩家说话 → 气泡出现在 D
  2. 对方说话 → D 的气泡移动到 B（变透明），新气泡出现在 C
  3. 玩家再说话 → B 的气泡淡出消失，C 的气泡移动到 A，新气泡出现在 D

---

## 5. 动画参数调整（BubbleSlotManager）

选中 `BubbleSlotManager` 节点，在 Inspector 中可调：

### Animation 分组
| 参数 | 说明 | 默认值 |
|------|------|--------|
| **Bubble Enter Duration** | 新气泡入场动画时间 | `0.3` 秒 |
| **Bubble Enter Scale From** | 入场时的初始缩放（1.0 = 无缩放效果） | `0.85` |
| **Bubble To History Duration** | 当前气泡移到历史位置的时间 | `0.4` 秒 |
| **History Fadeout Duration** | 历史气泡淡出消失的时间 | `0.3` 秒 |
| **History Opacity** | 历史气泡的透明度（0 = 完全透明，1 = 不透明） | `0.5` |

### History Text 分组
| 参数 | 说明 | 默认值 |
|------|------|--------|
| **History Shrink Threshold** | 超过此字数的文本在转为历史时会被缩略 | `100` 字 |
| **History Preview Char Count** | 历史缩略后显示的字符数 | `20` 字 |
| **History Preview Suffix** | 缩略后缀 | `……` |

### Typewriter 分组
| 参数 | 说明 | 默认值 |
|------|------|--------|
| **Typewriter Speed** | 打字机每秒显示的字符数 | `25` |

---

## 6. 对话文件编写（tags 格式）

在 `.dialogue` 文件中，每句话可携带 tags 控制表现：

```
角色名: [#role=player, emotion=angry, talk=true, after=keep] 对话文本
```

### 可用 tags

| Tag | 说明 | 可选值 |
|-----|------|--------|
| `role` | 发言者角色 | `player` / `other` |
| `emotion` | 目标表情 | `idle` / `angry` / `sad` / `fear` |
| `talk` | 是否播放说话动画 | `true` / `false` |
| `after` | 打字结束后保持的表情 | `keep` = 保持当前 / 具体表情名 |
| `skin` | 临时切换皮肤 | 皮肤名称 |
| `bubble_style` | 临时更换气泡样式 | 样式 ID |

---

## 7. 快速上手步骤

### 想要调整气泡位置？
→ 拖动 `SlotA` ~ `SlotD` 四个 Marker2D

### 想要更换气泡外观？
→ 打开 `DialogueBubble.tscn`，替换 `BubbleBG` 的 texture

### 想要调整立绘大小？
→ 选中立绘节点，修改 `Portrait Scale`

### 想要改变立绘入场效果？
→ 调整 `Slide In Offset X` / `Slide In Duration` / `Slide In Trans`

### 想要给气泡加 Shader 动效？
→ 给 `BubbleBG` 节点的 Material 赋予 ShaderMaterial

### 想要让气泡有帧动画？
→ 在 `DialogueBubble.tscn` 的 `AnimationPlayer` 中创建动画

---

## 8. 注意事项

1. **不要重命名关键节点**：`BubbleBG`、`MarginContainer`、`DialogueLabel`、`SpineContainer`、`BubbleAnchor` 这些名称被脚本引用
2. **立绘不会被翻转**：如需镜像效果，请在 Spine 文件中制作
3. **皮肤自动同步已关闭**：当前版本不会根据玩家小人自动切换立绘皮肤，此功能待美术素材就绪后启用
4. **只有左键点击推进对话**：对话进行中所有键盘和其他鼠标按键被屏蔽
5. **每个对话框和立绘都是独立场景**：可以分别打开编辑，不会互相影响
