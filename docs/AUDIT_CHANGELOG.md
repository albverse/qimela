# Audit Changelog（代码审计修复记录）

日期：2026-02-23

---

## Bug修复 (B)

| ID | 文件 | 修复内容 |
|----|------|----------|
| B1 | player_action_fsm.gd | 新增 `DEFAULT_HURT_TIMEOUT` 常量，stun结束后恢复默认hurt超时 |
| B3 | player_chain_system.gd | `fusion_rejected` 信号修复：`has_method()` 无法检测信号，改为直接 `emit()` |
| B7 | entity_base.gd | `on_chain_detached` 中重置 `_hurtbox_original_layer = -1` |
| B9 | chimera_base.gd | 飞行奇美拉idle时 `velocity.y = 0.0`，防止Y速度残留 |
| B11 | chain_slots_ui.gd | 移除 `"chimera_animation "` 尾部空格兼容，仅匹配 `"chimera_animation"` |

## 文档标注（不修复）

| ID | 原因 | 参见 |
|----|------|------|
| B4 | 敌对怪物AI属计划功能 | MONSTER_DESIGN.md §5 |
| B5 | healing_burst对所有怪物+1是正确的环境光行为 | MONSTER_DESIGN.md §3 |
| B6 | 链接必须虚弱/眩晕是核心设计 | MONSTER_DESIGN.md §1 |
| B8 | 无respawn系统，save/load未构建 | — |
| B10 | MonsterFly隐身保持collision_mask是防穿模设计 | MONSTER_DESIGN.md §2 |

---

## 死代码清理 (D)

| ID | 文件 | 操作 |
|----|------|------|
| D1 | player_chain_system.gd | 删除 `_has_action()` |
| D2 | player_chain_system.gd | 删除 `_resolve_monster()` |
| D3 | player_chain_system.gd | 删除 `_try_fuse()` |
| D4 | player_chain_system.gd | 删除 `pick_fire_side()` |
| D5 | player_chain_system.gd | 删除 `_chimera` 变量 |
| D6 | player_action_fsm.gd | 删除 `_abort_chain_if_active()` |
| D7 | player_action_fsm.gd | 保留 `allow_move_interrupt_action`，标注 `## PLANNED` |
| D8 | player_action_fsm.gd | 删除 `_pending_fire_side` 及所有引用 |
| D9 | player.gd | 删除 `anim_fsm` 变量 |
| D10 | chimera_base.gd | 删除 `source_count` 变量 |
| D11 | fusion_registry.gd | 统一在所有execute路径调用 `setup(player)` / `set_player(player)` |
| D12 | chain_slots_ui.gd | 删除 `_is_fusion_release()` |
| D13 | chain_slots_ui.gd | 删除 `slot_anim_playing` 变量 |
| D14 | fusion_registry.gd | 规则管理API标注 `## PLANNED: 配方解锁系统` |
| D15 | — | 保留 `vanish_progress_updated` 信号（未来UI） |
| D16 | — | 保留 `light_finished` 信号（未来动画） |
| D17 | weapon_ui.gd | 整文件删除 |

---

## 冗余优化 (R)

| ID | 文件 | 操作 |
|----|------|------|
| R1 | player_chain_system.gd | 删除私有 `_switch_slot()`，统一用公共 `switch_slot()` |
| R2 | player_chain_system.gd | 内联 `_force_dissolve_all_chains()` 到公共方法 |
| R3 | player_action_fsm.gd | 合并 `_sync_loco_to_resolved` 和 `_sync_loco_to_state` 为统一 `_sync_loco()` |
| R5 | monster_base.gd | `_update_weak_state()` 改为调用 `super._update_weak_state()` + 追加眩晕 |
| R6 | monster_fly.gd | `_force_release_all_chains()` 简化为调用父类 `_release_linked_chains()` |
| R7 | 7个monster子类 | 移除冗余 `entity_type = EntityType.MONSTER`（MonsterBase._ready统一设置） |
| R10 | entity_base.gd | 更新 `get_icon_id()` 注释标注与 `get_attribute_type()` 等价 |

---

## 架构优化 (A)

| ID | 操作 |
|----|------|
| A2 | 所有Player组件的 `CharacterBody2D` 类型统一为 `Player` |
| A6 | AnimDriverSpine 新增 `get_current_anim(track)` 方法，与Mock驱动器接口对齐 |
| A6+ | AnimDriverSpine 所有 `print()` 改为 `debug_log` 开关控制 |

---

## 历史遗留清理 (H)

| ID | 文件 | 操作 |
|----|------|------|
| H1 | player_chain_system.gd | 移除tombstone注释 |
| H2 | player.gd | 移除 `spine_quick_test.gd` 生产环境加载 |
| H5 | chain_slots_ui.gd | 移除旧 `_play_monster_burn` 注释 |

---

## 删除文件

| 文件 | 原因 |
|------|------|
| scene/weapon_ui.gd | 完全死代码，无引用 |
| scene/components/player_chain_system_stub.gd | 历史占位，无引用 |
| scene/rope_sim_2d.gd | 废弃的绳索模拟，无引用 |
| scene/Spine_plugin_diagnostic.gd | 诊断工具，无引用 |
| scene/Spine_plugin_diagnostic.gd.uid | 配套uid文件 |
| scene/components/player_chain_system.gd.backup | 备份文件 |

---

## 预留的 healing_scene preload

fusion_registry.gd: `_healing_sprite_scene` 改为 `preload` 避免运行时 `load()` 开销。
