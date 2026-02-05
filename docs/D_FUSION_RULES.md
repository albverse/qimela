# D_FUSION_RULES.md（融合规则表）

> **唯一真相**：所有融合规则以此表为准。
> 此表必须与 `autoload/fusion_registry.gd` 中的 `_rules` 保持同步。

---

## 1. 融合结果类型

| 类型 | 枚举值 | 说明 | UI显示 |
|------|--------|------|--------|
| SUCCESS | 0 | 成功融合，生成新奇美拉 | ui_yes |
| FAIL_HOSTILE | 1 | 失败，生成敌对怪物 | ui_die |
| FAIL_VANISH | 2 | 失败，双方泯灭，生成治愈精灵 | ui_die |
| FAIL_EXPLODE | 3 | 失败，双方爆炸（仅奇美拉+奇美拉） | ui_die |
| HEAL_LARGE | 4 | 型号不同，大型回血小型消失 | - |
| REJECTED | 5 | 拒绝融合（同物种/无规则） | ui_no |
| WEAKEN_BOSS | 6 | 特殊，削弱Boss | - |

---

## 2. 成功融合规则（SUCCESS）

| 规则键 | 组合 | 产物 | 说明 |
|--------|------|------|------|
| `fly_light + walk_dark` | 飞怪(光) + 走怪(暗) | ChimeraA | 光暗异属性组合 |
| `fly_light + neutral_small` | 飞怪(光) + 无属性怪 | ChimeraA | 无属性可融合任何 |
| `neutral_small + walk_dark` | 无属性怪 + 走怪(暗) | ChimeraA | 无属性可融合任何 |
| `fly_light + hand_light` | 飞怪(光) + 手怪(光) | Chimera_StoneSnake | 同属性特殊组合 |

---

## 3. 失败规则 - 敌对怪物（FAIL_HOSTILE）

| 规则键 | 组合 | 产物 | 说明 |
|--------|------|------|------|
| `fly_light + fly_light_b` | 飞怪(光) + 飞怪B(光) | MonsterHostile | 同属性不同变体 |
| `walk_dark + walk_dark_b` | 走怪(暗) + 走怪B(暗) | MonsterHostile | 同属性不同变体 |

---

## 4. 隐式规则（代码逻辑，不在_rules表中）

| 条件 | 结果 | 触发位置 |
|------|------|---------|
| 同 species_id | REJECTED | check_fusion() |
| 无匹配规则 + 同属性同型号 | FAIL_VANISH | check_fusion() |
| 无匹配规则 + 光+暗 | REJECTED | check_fusion() |

---

## 5. UI显示逻辑

锁链槽UI（chain_slots_ui.gd）根据融合结果显示不同图标：

```
SUCCESS        → ui_yes（绿色勾）
REJECTED       → ui_no（红色叉）
其他（失败类） → ui_die（骷髅）
```

---

## 6. 添加新规则步骤

1. 在 `autoload/fusion_registry.gd` 的 `_rules` 字典中添加规则
2. 更新本文档（D_FUSION_RULES.md）
3. 如果是新实体，更新 C_ENTITY_DIRECTORY.md
4. 测试融合是否正常

### 规则格式示例
```gdscript
"species_a + species_b": {
    # 注释：说明组合和产物
    "result_scene": "res://scene/产物场景.tscn",
    "result_type": FusionResultType.SUCCESS
},
```

---

## 7. 自动校验（建议添加）

在 FusionRegistry._ready() 中添加校验逻辑：

```gdscript
func _validate_rules() -> void:
    for key in _rules:
        var rule = _rules[key]
        
        # 校验场景路径存在
        if rule.has("result_scene"):
            if not ResourceLoader.exists(rule["result_scene"]):
                push_error("[FusionRegistry] 规则 %s 的 result_scene 不存在: %s" % [key, rule["result_scene"]])
        
        if rule.has("hostile_scene"):
            if not ResourceLoader.exists(rule["hostile_scene"]):
                push_error("[FusionRegistry] 规则 %s 的 hostile_scene 不存在: %s" % [key, rule["hostile_scene"]])
    
    print("[FusionRegistry] 规则校验完成，共 %d 条规则" % _rules.size())
```

---

## 8. 版本历史

| 日期 | 变更 |
|------|------|
| 2026-02-02 | 初始化文档，从fusion_registry.gd同步 |
| 2026-02-02 | 添加 fly_light + hand_light → Chimera_StoneSnake 规则 |
