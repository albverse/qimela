# Zip2 Chain System 修复完成

## 已修改文件

### 1. player_animator.gd
**修正**: 锚点骨骼名
- `hand_r/hand_l` → `chain_anchor_r/chain_anchor_l`
- 保留 Marker2D fallback

### 2. player_chain_system.gd  
**新增接口** (Phase 2):
- `pick_fire_slot() -> int` - 选择发射槽位（优先 active_slot）
- `pick_fire_side() -> String` - 返回 "R"/"L"
- `fire_by_slot(slot_index) -> bool` - 按槽位发射
- `cancel_volatile_on_damage()` - 受击时只取消 FLYING/STUCK
- `cancel_all_on_weapon_switch()` - 切武器时取消所有链

### 3. player_action_fsm.gd
**修改**:
- 新增变量 `_pending_fire_slot: int`
- `on_m_pressed()`: Chain 武器调用 `pick_fire_slot()` 决定槽位
- `_physics_process()`: 使用 `fire_by_slot()` 替代 `fire(side)`

### 4. player_health.gd
**修改**: 
- `apply_damage()`: 调用 `chain_sys.cancel_volatile_on_damage()`

### 5. weapon_controller.gd
**修改**:
- `switch_weapon()`: 离开 Chain 时调用 `cancel_all_on_weapon_switch()`

---

## 核心逻辑变化

### Before (Zip2 旧版)
```
M_pressed → ActionFSM 判断 slot_R_available
          → 固定发射 slot0 (右手)
          → active_slot 切换但没用
```

### After (Zip2 新版 - 对齐 Zip1)
```
M_pressed → ChainSystem.pick_fire_slot() (基于 active_slot)
          → ActionFSM 存储 slot_index
          → fire_by_slot(slot_index)
          → active_slot 自动切换到另一个
```

---

## 验收要点

### 1. 锚点正确
- [ ] 发射点从 `chain_anchor_r/l` 骨骼读取
- [ ] 左右手发射点位置不同

### 2. 双发恢复
- [ ] 第一次M: slot0 (右手) 发射
- [ ] 第二次M (立即): slot1 (左手) 发射
- [ ] 日志显示: `chain slot=0 side=R` → `chain slot=1 side=L`

### 3. 受击策略
- [ ] slot0=FLYING 时受击 → slot0 dissolve
- [ ] slot0=LINKED 时受击 → slot0 保持
- [ ] UI slot 状态正确更新

### 4. 武器切换
- [ ] Chain → Sword: 所有链条取消（包括 LINKED）
- [ ] Sword → Chain: 正常工作

### 5. UI 同步
- [ ] EventBus 信号正确触发
- [ ] chain_slots_ui 显示 busy/idle 正确

---

## 关键映射（固定不变）

- **slot0** = 右手 = chain_R = chain_anchor_r
- **slot1** = 左手 = chain_L = chain_anchor_l

---

## 测试步骤

1. **锚点测试**
   - 站立时发射右手链，观察发射点
   - 第二次发射左手链，发射点应不同

2. **双发测试**
   - 快速按两次M
   - 应看到两条链从不同点发射
   - UI 两个槽位都显示 busy

3. **受击测试**
   - 发射一条链（FLYING）
   - 受击 → 链应取消
   - 绑定怪物（LINKED）
   - 受击 → 链不断开

4. **切武器测试**
   - 发射链并绑定怪物
   - 按Z切换到Sword
   - 链应立即取消

---

## 如果出现问题

### 问题1: 仍然只从右手发射
**检查**: 
- 日志是否显示 `chain slot=0` / `chain slot=1` 切换
- `pick_fire_slot()` 是否被调用

### 问题2: 锚点位置不对
**检查**:
- Spine 骨骼名是否确实是 `chain_anchor_r/l`
- `get_bone_world_position()` 是否返回有效值

### 问题3: 受击时 LINKED 也断了
**检查**:
- `cancel_volatile_on_damage()` 逻辑
- 是否误调用了其他 cancel 方法

### 问题4: UI 不同步
**检查**:
- EventBus 信号是否正确 emit
- chain_slots_ui 是否连接信号
