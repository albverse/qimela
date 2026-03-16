## 镰刀不在手时的兜底：原地待机，等待镰刀回航
extends ActionLeaf
class_name ActP3IdleNoScythe

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss := actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0
	boss.anim_play(&"phase3/idle_no_scythe", true)
	return RUNNING
