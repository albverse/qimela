extends Area2D

func get_host() -> MonsterBase:
	return get_parent() as MonsterBase
