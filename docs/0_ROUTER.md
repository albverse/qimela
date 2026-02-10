# 0_ROUTER.md（主索引，2026-02-02更新）

> **使用方式**：默认只读本文件。触发器命中时才读对应模块文档。

---

## 1. 文档结构

| 文档 | 用途 | 触发器 |
|------|------|--------|
| A_PHYSICS_LAYER_TABLE.md | 碰撞层/bitmask | collision_layer, mask, RayCast, Area2D |
| B_GAMEPLAY_RULES.md | 玩法规则/输入/状态 | 输入, weak, stun, 天气, 雷花 |
| C_ENTITY_DIRECTORY.md | 实体目录（唯一真相） | species_id, attribute, ui_icon |
| D_FUSION_RULES.md | 融合规则（唯一真相） | 融合, fusion, check_fusion |
| HOWTO_ADD_ENTITY.md | 添加新实体教程 | 新怪物, 新奇美拉 |

---

## 2. 功能完成状态

### ✅ 已完成
- 锁链发射/收回/溶解
- 怪物虚弱/眩晕系统
- 融合系统（SUCCESS/REJECTED/FAIL_HOSTILE/FAIL_VANISH）
- 锁链槽位UI（双槽显示、图标、cooldown、融合预览）
- 回血精灵（拾取/环绕/使用）
- 天气系统（雷击/雷花）
- 飞怪显隐系统
- ChimeraA（跟随型）
- ChimeraStoneSnake（攻击型，发射子弹）
- 玩家HP/受击/击退

### 🔧 TODO
- Boss 削弱机制
- 存档系统
- 音频资产替换（AudioBus 接口已就绪，占位 ID 已注册）

---

## 3. 输入映射（唯一真相）

| 功能 | action名 | 按键 |
|------|---------|------|
| 移动左 | move_left | A |
| 移动右 | move_right | D |
| 跳跃 | jump | W |
| 发射锁链 | (无action) | 鼠标左键 |
| 取消锁链 | cancel_chains | X |
| 融合 | fuse | Space |
| 使用回血精灵 | use_healing | C |
| 治愈精灵大爆炸 | healing_burst | Q |
| 武器切换 | (无action) | Z |

---

## 4. 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| .tscn 文件 | PascalCase | `MonsterFly.tscn` |
| .gd 文件 | snake_case | `monster_fly.gd` |
| class_name | PascalCase | `MonsterFly` |
| species_id | snake_case | `fly_light` |
| action名 | snake_case | `cancel_chains` |

---

## 5. 关键文件路径

### 核心脚本
```
scene/player.gd              # 玩家主脚本
scene/entity_base.gd         # 实体基类
scene/monster_base.gd        # 怪物基类
scene/chimera_base.gd        # 奇美拉基类
scene/components/player_chain_system.gd  # 锁链系统
```

### Autoload
```
autoload/event_bus.gd        # 事件总线
autoload/fusion_registry.gd  # 融合规则注册表
autoload/audio_bus.gd        # 音频唯一入口（禁止任意脚本直播音频）
```

### UI
```
ui/chain_slots_ui.gd         # 锁链槽UI
ui/hearts_ui.gd              # 血量UI
```

---

## 6. 文档读取协议

默认只用本文件回答。需要细节时请求读取：

**格式**：`NEED_DOC: A|B|C|D | 目的: <一句话>`

| 代号 | 文档 |
|------|------|
| A | A_PHYSICS_LAYER_TABLE.md |
| B | B_GAMEPLAY_RULES.md |
| C | C_ENTITY_DIRECTORY.md |
| D | D_FUSION_RULES.md |

---

## 7. Layer/Mask 速查

| 层号 | 层名 | bitmask |
|------|------|---------|
| 1 | World | 1 |
| 2 | PlayerBody | 2 |
| 3 | EnemyBody | 4 |
| 4 | EnemyHurtbox | 8 |
| 5 | ObjectSense | 16 |
| 6 | hazards | 32 |
| 7 | ChainInteract | 64 |

换算：第N层 → bitmask = 1 << (N-1)

---

## 8. 音频系统（AudioBus）

**护栏规则：音频唯一入口 = AudioBus；禁止任意脚本直接使用 AudioStreamPlayer.play()。**

### 总线结构
| 总线 | 用途 |
|------|------|
| Master | 总音量 |
| BGM | 背景音乐 |
| SFX | 战斗/环境音效 |
| UI | 界面音效 |

### API 速查
```gdscript
AudioBus.play_sfx(&"hit_light")              # 播放 SFX
AudioBus.play_bgm(&"area_forest")            # 播放 BGM（自动 crossfade）
AudioBus.stop_bgm()                          # 停止 BGM
AudioBus.play_ui(&"confirm")                 # 播放 UI 音效
AudioBus.set_volume_bgm(0.8)                 # 设置音量（linear 0~1）
AudioBus.set_volume_sfx(0.8)
AudioBus.set_volume_ui(0.8)
AudioBus.register_sfx(&"new_id", "res://audio/sfx/new.wav")  # 运行时注册
```

### 音效触发职责
| 来源 | 触发方式 | 示例 |
|------|---------|------|
| 动作音效 | PlayerAnimator（Spine events）→ AudioBus.play_sfx() | swing/hit/land |
| 怪物受击音 | apply_hit/take_damage 结果 → AudioBus.play_sfx() | monster_hurt |
| UI/系统音 | UI 层或系统流程 → AudioBus.play_ui() | confirm/cancel |
| BGM | 场景切换/区域进入 → AudioBus.play_bgm() | area_forest |

### 护栏机制
- 限频：同一 sfx_id 在 80ms 内只触发一次
- 并发上限：同一 sfx_id 最多 3 个同时播放
- SFX 池：16 个 AudioStreamPlayer 轮询复用
