class_name ItemValidator
extends RefCounted

## 物品定义校验器（启动时由 ItemRegistry 调用）
## 检查所有 ItemData 是否符合分类合法矩阵与字段完整性要求


static func validate_all(defs: Dictionary) -> PackedStringArray:
	## 校验所有 ItemData，返回错误信息列表（空 = 全部通过）
	var errors: PackedStringArray = PackedStringArray()

	for id: StringName in defs:
		var item: ItemData = defs[id] as ItemData
		if item == null:
			errors.append("id=%s: ItemData is null" % id)
			continue

		# 规则 1: KEY_ITEM ⇒ can_sell=false 且 can_drop=false
		if item.sub_category == ItemData.SubCategory.KEY_ITEM:
			if item.can_sell:
				errors.append("id=%s: KEY_ITEM must have can_sell=false" % id)
			if item.can_drop:
				errors.append("id=%s: KEY_ITEM must have can_drop=false" % id)

		# 规则 2: MATERIAL ⇒ main_category=NON_USABLE 且 consume_on_use=false
		if item.sub_category == ItemData.SubCategory.MATERIAL:
			if item.main_category != ItemData.MainCategory.NON_USABLE:
				errors.append("id=%s: MATERIAL must have main_category=NON_USABLE" % id)
			if item.consume_on_use:
				errors.append("id=%s: MATERIAL must have consume_on_use=false" % id)

		# 规则 3: USABLE ⇒ sub_category=CONSUMABLE
		if item.main_category == ItemData.MainCategory.USABLE:
			if item.sub_category != ItemData.SubCategory.CONSUMABLE:
				errors.append("id=%s: USABLE must have sub_category=CONSUMABLE" % id)

		# 规则 4: CONSUMABLE 应有有效 use_type
		if item.sub_category == ItemData.SubCategory.CONSUMABLE:
			if item.use_type == ItemData.UseType.NONE:
				errors.append("id=%s: CONSUMABLE should have use_type != NONE" % id)

		# 规则 5: use_type=HEAL 时 hp_restore 应 > 0
		if item.use_type == ItemData.UseType.HEAL:
			if item.hp_restore <= 0:
				errors.append("id=%s: use_type=HEAL but hp_restore <= 0" % id)

		# 规则 6: drop_sprite 与 inventory_icon 不可同时为空
		if item.drop_sprite == null and item.inventory_icon == null:
			errors.append("id=%s: drop_sprite and inventory_icon cannot both be null" % id)

		# 规则 7: consume_on_use=true 时 max_stack 建议 > 1（仅警告）
		if item.consume_on_use and item.max_stack <= 1:
			errors.append("id=%s: consume_on_use=true but max_stack=1 (consider >1)" % id)

		# 规则 8: max_stack 必须 >= 1
		if item.max_stack < 1:
			errors.append("id=%s: max_stack must be >= 1" % id)

		# 规则 9: sell_value 不可为负
		if item.sell_value < 0:
			errors.append("id=%s: sell_value must be >= 0" % id)

	return errors
