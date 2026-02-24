extends RefCounted
class_name WeaponAnimProfiles

## 武器动画名映射表
## 区分 PlayerSpine 上的动画名 与 武器 SpineSprite 上的动画名

const PROFILES: Dictionary = {
	"CHAIN": {
		"locomotion": {
			"idle": &"Chain/idle",
			"walk": &"Chain/walk",
			"run": &"Chain/run",
			"jump_up": &"Chain/jump_up",
			"jump_loop": &"Chain/jump_loop",
			"jump_down": &"Chain/jump_down",
			"hurt": &"Chain/hurt",
			"die": &"Chain/die",
		},
		"action": {
			"chain_L": &"Chain/chain_L",
			"chain_R": &"Chain/chain_R",
			"chain_cancel_L": &"Chain/anim_chain_cancel_L",
			"chain_cancel_R": &"Chain/anim_chain_cancel_R",
			"fuse_hurt": &"Chain/fuse_hurt",
			"fuse_progress": &"Chain/fuse_progress",
			"knife_light_idle": &"Chain/knife_light_idle",
			"knife_light_move": &"Chain/knife_light_move",
			"sword_light_air": &"Chain/sword_light_air",
			"sword_light_idle": &"Chain/sword_light_idle",
			"sword_light_move": &"Chain/sword_light_move",
		},
	},
	"GHOST_FIST": {
		"locomotion": {
			"idle": &"Ghost Fist/idle",
			"walk": &"Ghost Fist/walk",
			"run": &"Ghost Fist/run",
			"jump_up": &"Ghost Fist/jump_up",
			"jump_loop": &"Ghost Fist/jump_loop",
			"jump_down": &"Ghost Fist/jump_down",
			"idle_anima": &"Ghost Fist/idle_anima",
			"hurt": &"Ghost Fist/hurt",
			"die": &"Ghost Fist/die",
		},
		"action": {
			"attack_1": &"Ghost Fist/attack_1",
			"attack_2": &"Ghost Fist/attack_2",
			"attack_3": &"Ghost Fist/attack_3",
			"attack_4": &"Ghost Fist/attack_4",
			"cooldown": &"Ghost Fist/cooldown",
			"enter": &"Ghost Fist/enter",
			"exit": &"Ghost Fist/exit",
		},
		## 武器端动画（在 ghost_fist_L/R SpineSprite 上播放）
		"weapon_action": {
			"attack_1": &"ghost_fist_attack_1",
			"attack_2": &"ghost_fist_attack_2",
			"attack_3": &"ghost_fist_attack_3",
			"attack_4": &"ghost_fist_attack_4",
			"cooldown": &"ghost_fist_cooldown",
			"enter": &"ghost_fist_enter",
			"exit": &"ghost_fist_exit",
			"idle": &"ghost_fist_idle",
			"idle_anima": &"ghost_fist_idle_anima",
			"follow": &"ghost_fist_follow",
		},
	},
}


static func get_profile(weapon_key: String) -> Dictionary:
	return PROFILES.get(weapon_key, {})
