extends RefCounted
class_name WeaponAnimProfiles

## 武器动画名映射表
## 区分 PlayerSpine 上的动画名 与 武器 SpineSprite 上的动画名

const PROFILES: Dictionary = {
	"CHAIN": {
		"locomotion": {
			"idle": &"chain_/idle",
			"walk": &"chain_/walk",
			"run": &"chain_/run",
			"jump_up": &"chain_/jump_up",
			"jump_loop": &"chain_/jump_loop",
			"jump_down": &"chain_/jump_down",
			"hurt": &"chain_/hurt",
			"die": &"chain_/die",
		},
		"action": {
			"chain_L": &"chain_/chain_L",
			"chain_R": &"chain_/chain_R",
			"chain_cancel_L": &"chain_/anim_chain_cancel_L",
			"chain_cancel_R": &"chain_/anim_chain_cancel_R",
			"fuse_hurt": &"chain_/fuse_hurt",
			"fuse_progress": &"chain_/fuse_progress",
			"knife_light_idle": &"chain_/knife_light_idle",
			"knife_light_move": &"chain_/knife_light_move",
			"sword_light_air": &"chain_/sword_light_air",
			"sword_light_idle": &"chain_/sword_light_idle",
			"sword_light_move": &"chain_/sword_light_move",
		},
	},
	"GHOST_FIST": {
		"locomotion": {
			"idle": &"ghost_fist_/idle",
			"walk": &"ghost_fist_/walk",
			"run": &"ghost_fist_/run",
			"jump_up": &"ghost_fist_/jump_up",
			"jump_loop": &"ghost_fist_/jump_loop",
			"jump_down": &"ghost_fist_/jump_down",
			"idle_anima": &"ghost_fist_/idle_anima",
			"hurt": &"ghost_fist_/hurt",
			"die": &"ghost_fist_/die",
		},
		"action": {
			"attack_1": &"ghost_fist_/attack_1",
			"attack_2": &"ghost_fist_/attack_2",
			"attack_3": &"ghost_fist_/attack_3",
			"attack_4": &"ghost_fist_/attack_4",
			"cooldown": &"ghost_fist_/cooldown",
			"enter": &"ghost_fist_/enter",
			"exit": &"ghost_fist_/exit",
		},
		## 武器端动画（在 ghost_fist_L/R SpineSprite 上播放）
		"weapon_action": {
			"attack_1": &"ghost_fist_/attack_1",
			"attack_2": &"ghost_fist_/attack_2",
			"attack_3": &"ghost_fist_/attack_3",
			"attack_4": &"ghost_fist_/attack_4",
			"cooldown": &"ghost_fist_/cooldown",
			"enter": &"ghost_fist_/enter",
			"exit": &"ghost_fist_/exit",
			"idle": &"ghost_fist_/idle",
			"idle_anima": &"ghost_fist_/idle_anima",
		},
	},
}


static func get_profile(weapon_key: String) -> Dictionary:
	return PROFILES.get(weapon_key, {})
