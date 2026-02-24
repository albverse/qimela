extends Node
class_name WeaponController

## WeaponController: 管理武器切换与动画选择
## 功能：
## - 维护当前武器（Chain/Sword）
## - 根据 Context + 武器配置返回动画名
## - Z键切换武器

enum WeaponType { CHAIN, SWORD, KNIFE, GHOST_FIST }
enum AttackMode { 
	OVERLAY_UPPER,      # 上半身叠加（Chain）
	OVERLAY_CONTEXT,    # 上半身叠加 + context 选择（Sword/Knife）
	FULLBODY_EXCLUSIVE  # 全身独占（重攻击/特殊武器）
}

var current_weapon: int = WeaponType.CHAIN
var _player: CharacterBody2D = null

# 武器定义（WeaponDef）
var _weapon_defs: Dictionary = {}


func setup(player: CharacterBody2D) -> void:
	_player = player
	_init_weapon_defs()
	current_weapon = WeaponType.CHAIN


func _init_weapon_defs() -> void:
	# Chain: OVERLAY_UPPER - 动画与移动状态无关，只看左右手
	_weapon_defs[WeaponType.CHAIN] = {
		"name": "Chain",
		"attack_mode": AttackMode.OVERLAY_UPPER,
		"lock_anim_until_end": true,  # Chain起手后不随context变化
		"anim_map": {
			# context -> side -> anim_name
			"ground_idle": { "R": "chain_/chain_R", "L": "chain_/chain_L" },
			"ground_move": { "R": "chain_/chain_R", "L": "chain_/chain_L" },
			"air": { "R": "chain_/chain_R", "L": "chain_/chain_L" },
		},
		"cancel_anim": {
			"R": "chain_/anim_chain_cancel_R",
			"L": "chain_/anim_chain_cancel_L",
		}
	}
	
	# Sword: OVERLAY_CONTEXT - 动画根据移动状态自动选择
	_weapon_defs[WeaponType.SWORD] = {
		"name": "Sword",
		"attack_mode": AttackMode.OVERLAY_CONTEXT,
		"lock_anim_until_end": false,  # Sword允许context变化时切换动画
		"anim_map": {
			# context -> anim_name（无需side）
			"ground_idle": "chain_/sword_light_idle",
			"ground_move": "chain_/sword_light_move",
			"air": "chain_/sword_light_air",
		},
		"cancel_anim": {
			# Sword暂无cancel动画，返回空
			"any": "",
		}
	}
	
	# Knife: OVERLAY_CONTEXT - 最小第三武器（验证扩展性）
	_weapon_defs[WeaponType.KNIFE] = {
		"name": "Knife",
		"attack_mode": AttackMode.OVERLAY_CONTEXT,
		"lock_anim_until_end": true,  # Knife起手后不变
		"anim_map": {
			# 独立动画名（Phase1验证结构）
			"ground_idle": "chain_/knife_light_idle",
			"ground_move": "chain_/knife_light_move",
			"air": "chain_/knife_light_air",
		},
		"cancel_anim": {
			"any": "",
		}
	}

	# GhostFist: FULLBODY_EXCLUSIVE - 攻击由 GhostFist 模块自行管理
	_weapon_defs[WeaponType.GHOST_FIST] = {
		"name": "GhostFist",
		"attack_mode": AttackMode.FULLBODY_EXCLUSIVE,
		"lock_anim_until_end": true,
		"ghost_fist": true,  # 标记：攻击由 GhostFist 模块管理，不走标准动画选取
		"anim_map": {},
		"cancel_anim": {},
	}


## attack: 获取攻击动画名
## context: "ground_idle" / "ground_move" / "air"
## side: "R" / "L" (仅OVERLAY_UPPER需要)
## 返回: { "mode": AttackMode, "anim_name": String, "lock_anim": bool }
func attack(context: String, side: String = "R") -> Dictionary:
	var weapon_def: Dictionary = _weapon_defs.get(current_weapon, {})
	if weapon_def.is_empty():
		push_error("[WeaponController] No def for weapon=%d" % current_weapon)
		return { "mode": AttackMode.OVERLAY_UPPER, "anim_name": "", "lock_anim": false }
	
	var mode: int = weapon_def.get("attack_mode", AttackMode.OVERLAY_UPPER)
	var anim_map: Dictionary = weapon_def.get("anim_map", {})
	var lock_anim: bool = weapon_def.get("lock_anim_until_end", true)
	var anim_name: String = ""
	
	match mode:
		AttackMode.OVERLAY_UPPER:
			# Chain: anim_map[context][side]
			var context_map: Dictionary = anim_map.get(context, {})
			anim_name = context_map.get(side, "")
		
		AttackMode.OVERLAY_CONTEXT, AttackMode.FULLBODY_EXCLUSIVE:
			# Sword/Knife/Fullbody: anim_map[context]
			anim_name = anim_map.get(context, "")
	
	return { 
		"mode": mode, 
		"anim_name": anim_name,
		"lock_anim": lock_anim
	}


## cancel: 获取取消动画名
## side: "R" / "L" (仅OVERLAY_UPPER需要)
## 返回: { "anim_name": String }
func cancel(side: String = "R") -> Dictionary:
	var weapon_def: Dictionary = _weapon_defs.get(current_weapon, {})
	if weapon_def.is_empty():
		return { "anim_name": "" }
	
	var cancel_map: Dictionary = weapon_def.get("cancel_anim", {})
	var anim_name: String = ""
	
	var mode: int = weapon_def.get("attack_mode", AttackMode.OVERLAY_UPPER)
	match mode:
		AttackMode.OVERLAY_UPPER:
			anim_name = cancel_map.get(side, "")
		_:
			anim_name = cancel_map.get("any", "")
	
	return { "anim_name": anim_name }


## switch_weapon: 切换武器（硬切，中断当前动作）
func switch_weapon() -> void:
	var old_weapon: int = current_weapon
	var old_name: String = _weapon_defs.get(old_weapon, {}).get("name", "?")
	
	# Chain → Sword → Knife → GhostFist → Chain（循环）
	match current_weapon:
		WeaponType.CHAIN:
			current_weapon = WeaponType.SWORD
		WeaponType.SWORD:
			current_weapon = WeaponType.KNIFE
		WeaponType.KNIFE:
			current_weapon = WeaponType.GHOST_FIST
		WeaponType.GHOST_FIST:
			current_weapon = WeaponType.CHAIN
		_:
			current_weapon = WeaponType.CHAIN
	
	var new_name: String = _weapon_defs.get(current_weapon, {}).get("name", "?")
	
	if _player != null and _player.has_method("log_msg"):
		_player.log_msg("WEAPON", "changed from=%s to=%s" % [old_name, new_name])


## get_weapon_name: 获取当前武器名（用于日志）
func get_weapon_name() -> String:
	return _weapon_defs.get(current_weapon, {}).get("name", "?")


## is_ghost_fist: 当前武器是否为 GhostFist
func is_ghost_fist() -> bool:
	return current_weapon == WeaponType.GHOST_FIST
