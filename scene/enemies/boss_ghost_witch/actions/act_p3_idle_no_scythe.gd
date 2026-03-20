extends ActionLeaf
class_name ActP3IdleNoScythe

## 镰刀不在手时的兜底：原地待机，等待镰刀回航

func tick(actor: Node, _bb: Blackboard) -> int:
	var boss: BossGhostWitch = actor as BossGhostWitch
	if boss == null:
		return FAILURE
	actor.velocity.x = 0.0
	boss.anim_play(&"phase3/idle_no_scythe", true)
	return RUNNING
