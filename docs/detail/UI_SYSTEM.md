# UI 系统详细说明

> 对应主表：[GAME_ARCHITECTURE_MASTER.md](../GAME_ARCHITECTURE_MASTER.md) → 模块 14

---

## 1. 概览

| 组件 | 文件 | 职责 |
|------|------|------|
| ChainSlotsUI | `ui/chain_slots_ui.gd` + `ui/chain_slots_ui.tscn` | 双锁链槽位显示 |
| HeartsUI | `ui/hearts_ui.gd` + `ui/hearts_ui.tscn` | 玩家血量显示 |
| GameUI | `ui/game_ui.gd` + `ui/game_ui.tscn` | UI 容器 |

---

## 2. ChainSlotsUI — 锁链槽位 UI

### 2.1 节点结构

```
ChainSlotsUI (Control)
├── SlotA (Control)
│   ├── Icon (TextureRect)          # 锁链图标 + cooldown shader
│   ├── MonsterIcon (TextureRect)   # 绑定怪物的图标
│   ├── FlashOverlay (ColorRect)    # 发射闪光
│   ├── ActiveIndicator (ColorRect) # 当前活跃槽位指示
│   └── Control/AnimationPlayer     # appear/chimera_animation
├── SlotB (Control)
│   └── （同 SlotA 结构）
└── ConnectionLine (Control)
    └── CenterIcon (TextureRect)    # 融合预测图标
```

### 2.2 事件订阅

| EventBus 信号 | 处理函数 | 效果 |
|---------------|----------|------|
| `slot_switched` | `_on_slot_switched` | 切换活跃指示器 |
| `chain_fired` | `_on_chain_fired` | 闪光 + 清空图标 + 开始 cooldown |
| `chain_bound` | `_on_chain_bound` | 显示怪物图标 + 播放 appear/chimera 动画 |
| `chain_released` | `_on_chain_released` | 串行倒放 → burn → cooldown |
| `chain_struggle_progress` | `_on_chain_struggle_progress` | 驱动 appear 动画位置 |
| `fusion_rejected` | `_on_fusion_rejected` | 两槽位震动 |

### 2.3 严格串行动画序列（释放时）

有目标释放时的完整序列：
```
1. 倒放 AnimationPlayer 动画（只播剩余部分）  → 完成后
2. Burn Shader 动画（fire_Burn_shader）       → 完成后
3. Cooldown Shader 动画（chain_cooldown_fill） → 完成
```

无目标释放：直接跳到 cooldown。

### 2.4 Shader 使用

| Shader | 用途 | 关键参数 |
|--------|------|----------|
| `chain_cooldown_fill.gdshader` | Icon 冷却填充 | `progress: 0.0→1.0` |
| `fire_Burn_shader.gdshader` | MonsterIcon 燃烧消失 | `progress: 0.0→2.0`, `noise`, `colorCurve` |

### 2.5 融合预测图标

当两个槽位都有目标时，ConnectionLine 显示并计算融合结果：

| 条件 | 图标 |
|------|------|
| FusionRegistry 返回 SUCCESS | `UI_yes.png` |
| 返回 REJECTED / 同目标 / 无效 | `UI_NO.png` |
| 返回 FAIL_HOSTILE / FAIL_VANISH / FAIL_EXPLODE | `UI_DIE.png` |

### 2.6 挣扎进度驱动动画

非奇美拉目标链接时，ChainSystem 发出 `chain_struggle_progress(slot, t01)`：
- `t01 = 1.0`：刚链接（动画在末尾）
- `t01 = 0.0`：即将挣脱（动画在开头）
- UI 使用 `anim.seek(anim_length * (1.0 - t01))` 驱动 appear 动画位置

---

## 3. HeartsUI — 血量 UI

- 显示玩家当前 HP
- 使用 `heart_full_texture.png` 和 `heart_empty_texture.png`
- 根据 `PlayerHealth.hp` 实时更新

---

## 4. 设计原则

1. **UI 不直接引用游戏对象** — 全部通过 EventBus 信号驱动
2. **动画严格串行** — 使用单一 Tween 链保证顺序
3. **安全引用** — 所有 target 使用 `is_instance_valid()` 检查
4. **缓存纹理** — `_cached_target_textures` 避免每帧创建新 ImageTexture
