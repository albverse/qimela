extends RefCounted
class_name HitData

## 通用命中数据容器
## 由武器模块创建，传给 MonsterBase.apply_hit()

## 命中标记位
class Flags:
	const NONE: int = 0
	const STAGGER: int = 1      ## 硬直
	const KNOCKBACK: int = 2    ## 击退
	const PIERCE: int = 4       ## 穿透护甲

var damage: int = 1
var source: Node2D = null       ## 攻击发起者（Player）
var weapon_id: StringName = &"" ## 武器标识（"ghost_fist", "chain" 等）
var flags: int = Flags.NONE

static func create(dmg: int, src: Node2D, wid: StringName, f: int = Flags.NONE) -> HitData:
	var h := HitData.new()
	h.damage = dmg
	h.source = src
	h.weapon_id = wid
	h.flags = f
	return h
