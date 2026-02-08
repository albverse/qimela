# 武器系统（Chain + Sword）验收测试

## 前提条件

**场景结构要求**：
在 Player 的 Components 节点下添加：
```
Player
└── Components
    ├── WeaponController (新增)
    ├── ActionFSM
    ├── Movement
    └── ...
```

**Spine 动画要求**（暂时使用占位）：
- `sword_light_idle` (占位)
- `sword_light_move` (占位)  
- `sword_light_air` (占位)

如果 Spine 文件中没有这些动画，会 fallback 到 chain_R/L。

---

## 测试 1：武器切换（Z键）

**步骤**：
1. 运行游戏
2. 按 Z 键

**期望日志**：
```
[WEAPON] changed from=Chain to=Sword
```

3. 再按 Z 键

**期望日志**：
```
[WEAPON] changed from=Sword to=Chain
```

**验证点**：
- ✅ Z 键可以切换武器
- ✅ 日志显示武器名称正确

---

## 测试 2：Chain 武器出招（M键）

**步骤**：
1. 确保当前武器是 Chain（启动时默认）
2. 按 M 键

**期望日志**：
```
[ACTION] EVENT=M_pressed
[ACTION] TRANS=None->Chain_R reason=M_pressed policy=R pr=5
[ANIM] play track=1 name=chain_R loop=false
```

**验证点**：
- ✅ 状态转换到 Chain_R
- ✅ 播放 chain_R 动画
- ✅ 链条发射（如果 chain_sys 正常）

---

## 测试 3：Sword 武器出招（M键）

**步骤**：
1. 按 Z 切换到 Sword
2. **站立不动**，按 M 键

**期望日志**：
```
[WEAPON] changed from=Chain to=Sword
[ACTION] EVENT=M_pressed
[ACTION] TRANS=None->Chain_R reason=M_pressed weapon=Sword context=ground_idle pr=5
[ANIM] play track=1 name=sword_light_idle loop=false  # 如果有动画
# 或
[ANIM] play track=1 name=chain_R loop=false  # fallback
```

3. **移动中**，按 M 键

**期望日志**：
```
[ACTION] TRANS=None->Chain_R reason=M_pressed weapon=Sword context=ground_move pr=5
[ANIM] play track=1 name=sword_light_move loop=false  # 如果有动画
```

4. **空中**，按 M 键

**期望日志**：
```
[ACTION] TRANS=None->Chain_R reason=M_pressed weapon=Sword context=air pr=5
[ANIM] play track=1 name=sword_light_air loop=false  # 如果有动画
```

**验证点**：
- ✅ Sword 不需要 slot（没有 `[CHAIN] fire` 日志）
- ✅ 动画根据 context 自动选择
- ✅ ground_idle / ground_move / air 三种情况动画不同

---

## 测试 4：武器切换硬切中断

**步骤**：
1. Chain 武器按 M 发射链条（进入 Chain_R 状态）
2. **立即**按 Z 切换武器

**期望日志**：
```
[ACTION] TRANS=None->Chain_R reason=M_pressed policy=R pr=5
[CHAIN] fire(R) ...
[ACTION] EVENT=weapon_switched
[CHAIN] cancel(R) ...  # 如果链条还在飞行
[ACTION] TRANS=Chain_R->None reason=weapon_switched pr=99
[WEAPON] changed from=Chain to=Sword
```

**验证点**：
- ✅ Z 键可以中断当前动作
- ✅ 链条被取消
- ✅ 状态回到 None
- ✅ 武器切换成功

---

## 测试 5：Sword 切换到 Chain 正常工作

**步骤**：
1. Sword 武器按 M 出招
2. 按 Z 切换回 Chain
3. 按 M 发射链条

**期望日志**：
```
# Sword 出招
[ACTION] TRANS=None->Chain_R reason=M_pressed weapon=Sword context=ground_idle pr=5

# 切换武器
[ACTION] EVENT=weapon_switched
[ACTION] TRANS=Chain_R->None reason=weapon_switched pr=99
[WEAPON] changed from=Sword to=Chain

# Chain 出招
[ACTION] EVENT=M_pressed
[ACTION] TRANS=None->Chain_R reason=M_pressed policy=R pr=5
[CHAIN] fire(R) ...
```

**验证点**：
- ✅ 切换回 Chain 后，M 键恢复链条发射
- ✅ slot 机制正常工作

---

## 关键日志标记

### Chain 武器特征：
- `reason=M_pressed policy=R/L` (slot 选择)
- `[CHAIN] fire(R/L)` (发射链条)
- 动画固定为 `chain_R` / `chain_L`

### Sword 武器特征：
- `reason=M_pressed weapon=Sword context=ground_idle/ground_move/air`
- **无** `[CHAIN] fire` 日志
- 动画根据 context 变化：`sword_light_idle/move/air`

### 武器切换特征：
- `[WEAPON] changed from=X to=Y`
- `[ACTION] EVENT=weapon_switched`
- `[ACTION] TRANS=*->None reason=weapon_switched pr=99`

---

## 已知限制（当前版本）

1. **Spine 动画占位**：
   - `sword_light_*` 动画暂时不存在
   - Fallback 到 `chain_R` / `chain_L`
   - 更新 Spine 文件后即可看到正确动画

2. **Sword 状态复用**：
   - 当前 Sword 复用 `Chain_R` 状态
   - 后续可扩展为独立的 `SWORD_ATTACK` 状态

3. **Cancel 动画**：
   - Sword 暂无 cancel 动画
   - 切换武器时直接硬切

---

## 架构验证

### WeaponDef 可配置：
```gdscript
# weapon_controller.gd 中的定义
_weapon_defs[WeaponType.SWORD] = {
    "name": "Sword",
    "attack_mode": AttackMode.OVERLAY_CONTEXT,
    "anim_map": {
        "ground_idle": "sword_light_idle",
        "ground_move": "sword_light_move",
        "air": "sword_light_air",
    }
}
```

### 委托调用流程：
```
User 按 M
  ↓
Player._unhandled_input
  ↓
ActionFSM.on_m_pressed()
  ↓
WeaponController.attack(context, side)
  ↓
返回 { mode, anim_name }
  ↓
Animator.tick() 读取 anim_name
  ↓
播放动画
```

---

## 下一步扩展

1. 添加实际的 Sword Spine 动画
2. 扩展更多武器类型（Bow / Gun / ...）
3. 添加武器切换动画（而非硬切）
4. 实现 FULLBODY 攻击模式
5. 添加武器专属的 UI 指示器
