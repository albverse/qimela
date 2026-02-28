# StoneMaskBird behavior notes

## Shoot vs Dash ranges are intentionally isolated

Current design uses **two hard-separated radius systems** and this is intentional:

- `face_shoot_range_px`
  - only for **has_face** shoot logic (`ActShootFace` + `CondPlayerInFaceShootRange`)
  - controls whether face-shot should start / remain eligible while in hover phase
- `attack_range_px` (+ `AttackArea`)
  - only for **no_face** dash logic (`ActAttackLoopDash` + `CondPlayerInAttackRange`)

Do not merge these into one radius unless combat design changes.

## has_face chase handoff rule

In `ActChasePlayer`, when `has_face == true`:

- if player is still within `face_shoot_range_px`, keep running and let upper Shoot branch take over
- only return to rest when player is outside `face_shoot_range_px`

This prevents semantic conflict between chase and shoot branch gating.
