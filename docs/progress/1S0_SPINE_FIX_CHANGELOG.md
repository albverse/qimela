# S0 Spine 修正 — 变更说明

> 日期：2026-02-08  
> 目标：恢复 anim_end → FSM 解锁 的完整链路；解决 Attack 叠加层停留最后一帧；修复 chain anchor 断链

---

## 修改文件清单

### 1. `scene/components/anim_driver_spine.gd`（核心修复）

**S0-1：set_animation 参数顺序修正**
- **根因**：旧版第106行写的是 `anim_state.set_animation(anim_str, loop, track)` — 参数顺序为 `(name, loop, track)`
- **修正**：新增 `_detect_api_signature()` 方法在 setup 时自动探测 Spine runtime 的签名（检查第一个参数名是否含 "track"/"index"）
- **默认**：按 spine_quick_test 确认的推荐签名 `(track, name, loop)` 调用
- **影响**：动画现在会被正确播放到指定 track → `animation_completed` 信号能正常触发 → FSM 不再依赖 TIMEOUT 解锁

**S0-2：SpineSprite 更新模式检查**
- setup 时打印 `update_mode` 和 `process_mode`，便于排查"Spine 不走时间"导致的 completed 不触发
- 如果是 Manual 模式，日志中会明确显示，需要用户手动改为 Process/Physics

**S0-3：animation_completed 回调加固**
- 回调中始终打印 track_id / anim_name / is_loop（S0 阶段保留详细日志）
- 双重 loop 校验：检查 track_entry.get_loop() 和 _track_states 记录，防止 loop 动画误触发 end 事件
- null 防护完善

**S1：track1 自动混出（解决停在最后一帧）**
- 新增 `_mix_out_track(track, mix_duration)` 方法
- `stop(1)` 现在调用 `set_empty_animation(1, 0.08)` 而非 `clear_track(1)`
- `_on_spine_animation_completed` 中，track1 播完后自动 mix_out
- 效果：Attack/Hurt 动画播完后会平滑退出，不会冻结在最后一帧

**S2：新增 `get_bone_world_position(bone_name)` 方法**
- 通过 `skeleton.find_bone(name)` → `get_world_x/Y()` → `to_global()` 获取骨骼全局坐标
- 供 chain system 的 `_get_hand_position()` 使用

---

### 2. `scene/components/player_chain_system.gd`（anchor 修复 + anim_fsm 安全化）

**S2：_get_hand_position 重写**
- 优先级变为：Spine driver 骨骼 → 旧 anim_fsm（兼容） → Marker2D → player 坐标
- 新增路径：`player.animator._driver.get_bone_world_position("hand_r" / "hand_l")`
- 旧 `player.anim_fsm.get_chain_anchor_position()` 路径保留但加了 `has_method` 保护

**anim_fsm 调用安全化**
- 所有 `player.anim_fsm.play_chain_fire()` 和 `play_chain_cancel()` 调用增加 `has_method()` 检查
- 当 anim_fsm 为 null（新架构下正常情况）时不会报错，跳过即可（动画由 Animator tick 驱动）

---

## 未修改但需关注的文件

| 文件 | 说明 |
|------|------|
| `player_animator.gd` | 无需修改。第199行 `_driver.stop(TRACK_ACTION)` 现在会触发 Spine driver 的 mix_out |
| `player_action_fsm.gd` | 无需修改。anim_end 事件链路恢复后，resolver 正常工作 |
| `player_locomotion_fsm.gd` | 无需修改。Jump_down 的 anim_end 链路恢复后，TIMEOUT 退回保底角色 |
| `player.gd` | `anim_fsm = null` 仍保留（兼容字段），chain system 已安全化 |

---

## 验收检查清单

### T1：Jump 闭环（不触发 TIMEOUT）
```
期望日志：
[ANIM] play track=0 name=jump_down loop=false
[AnimDriverSpine] play: track=0 name=jump_down loop=false entry=...
[AnimDriverSpine] animation_completed: track=0 name=jump_down loop=false
[ANIM] end track=0 name=jump_down
[LOCO] EVENT=anim_end_jump_down ...
[LOCO] TRANS=Jump_down->Idle ...

禁止出现：
[LOCO] TIMEOUT! Jump_down stuck ...
```

### T2：Chain Attack 闭环
```
期望日志：
[ANIM] play track=1 name=chain_R loop=false
[AnimDriverSpine] animation_completed: track=1 name=chain_R loop=false
[AnimDriverSpine] mix_out track=1 duration=0.08
[ANIM] end track=1 name=chain_R
[ACTION] EVENT=anim_end_attack
[CHAIN] release(R)

禁止出现：
[ACTION] TIMEOUT! Attack stuck ...
```

### T3：Sword/Knife 不残留最后一帧
```
期望：攻击动画播完后角色回到 idle/walk/jump 循环，不冻结
```

### T4：Chain anchor 跟手
```
期望：[AnimDriverSpine] 的 get_bone_world_position 返回有效坐标
如果骨骼名不匹配（hand_r/hand_l vs 实际 Spine 骨骼名），会 fallback 到 Marker2D
```

---

## 已知风险

1. **Spine 骨骼名不确定**：`get_bone_world_position("hand_r")` 假设骨骼名为 "hand_r"/"hand_l"。如果 Spine 工程中用的是其他名字（如 "chain_anchor_r"），需要用户确认后调整
2. **API 签名探测**：`_detect_api_signature()` 通过检查参数名推断签名。如果当前 Spine runtime 的参数名不含 "track"/"anim" 关键字，会 fallback 到签名1。setup 日志会打印实际参数名
3. **S0 阶段日志量大**：AnimDriverSpine 会打印每次 play/completed/mix_out，确认稳定后可减少
