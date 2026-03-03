# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Qimela (奇美拉)** — Godot 4.5 GDScript, 2D horizontal action-puzzle game.

Core mechanics: dual chain-launching, monster weakening/fusion, chimera generation.

**To run:** Open the project in the Godot 4.5 editor. Main scene is `MainTest.tscn`. There is no build script — use the Godot editor Play button or `godot --path /path/to/qimela_git`.

## Documentation

`docs/` contains comprehensive reference material. Start here before modifying any system:

| File | Purpose |
|------|---------|
| `docs/GAME_ARCHITECTURE_MASTER.md` | **Primary AI entry point** — module index with key files and doc links |
| `docs/0_ROUTER.md` | Navigation guide and quick reference tables |
| `docs/C_ENTITY_DIRECTORY.md` | Single source of truth for all entities (species_id, attributes, HP) |
| `docs/D_FUSION_RULES.md` | Authoritative fusion formula table |
| `docs/A_PHYSICS_LAYER_TABLE.md` | Collision layer/bitmask reference |
| `docs/B_GAMEPLAY_RULES.md` | Complete gameplay rules |
| `docs/detail/*.md` | Deep-dive for each system (animation, chain, entity, fusion, etc.) |

## Code Conventions

**File naming:**
- `.tscn` scenes: `PascalCase`
- `.gd` scripts: `snake_case`
- `class_name`: `PascalCase`

**Forbidden GDScript patterns:**
```gdscript
# ❌ No ternary operator (not supported in GDScript 4)
var x = cond ? A : B

# ❌ No Variant type inference on instantiate
var n := scene.instantiate()

# ❌ No bare bitmask numbers without comments
collision_mask = 5
```

**Required patterns:**
```gdscript
# ✅ Use if/else expression
var x = A if cond else B

# ✅ Explicit type annotation on instantiate
var n: Node = (scene as PackedScene).instantiate()

# ✅ Always comment collision layer numbers (see docs/A_PHYSICS_LAYER_TABLE.md)
collision_mask = 4 | 64  # EnemyBody(3)+ChainInteract(7)
```

**Physics layer bitmask formula:** Layer N → bitmask = `1 << (N-1)`

| Layer | Name | Bitmask |
|-------|------|---------|
| 1 | World | 1 |
| 2 | PlayerBody | 2 |
| 3 | EnemyBody | 4 |
| 4 | EnemyHurtbox | 8 |
| 5 | ObjectSense | 16 |
| 6 | hazards | 32 |
| 7 | ChainInteract | 64 |

## Architecture

### Player System (Component Orchestrator)

`scene/player.gd` is a tick dispatcher — not a monolithic script. Each `_physics_process` calls components in fixed order:

```
1. Movement.tick(dt)       → horizontal velocity, gravity, jump
2. move_and_slide()        → Godot physics (is_on_floor valid after this)
3. LocomotionFSM.tick(dt)  → Idle/Walk/Run/Jump state machine → Track0 anim
4. ActionFSM.tick(dt)      → None/Attack/Fuse/Hurt/Die + timeout protection
5. Health.tick(dt)         → invincibility frames, knockback
6. Animator.tick(dt)       → dual-track arbitration + Spine/Mock playback
7. ChainSystem.tick(dt)    → Verlet rope update (reads bone positions set by Animator)
8. _commit_pending_chain_fire → delayed chain fire (avoids same-frame race)
```

Components live in `scene/components/` and hold a back-reference `var player: Player`.

### Dual-Track Animation

- **Track 0 (Locomotion):** Always reflects LocomotionFSM state
- **Track 1 (Action):** Overlays ActionFSM actions when active
- Driver: `AnimDriverSpine` (Spine skeletal) or `AnimDriverMock` (fallback)
- See `docs/detail/ANIMATION_SYSTEM.md` for animation name tables

### Chain System (Independent Overlay)

`player_chain_system.gd` is **intentionally NOT managed by ActionFSM**:
- Two independent slots can have different states simultaneously
- Persists across frames (FLYING → STUCK/LINKED → DISSOLVING → IDLE)
- Can fire while moving or airborne
- Uses Verlet physics for rope simulation

State machine: `IDLE → FLYING → STUCK | LINKED → DISSOLVING → IDLE`

Fire: direct input → `_pending_chain_fire_side` → `ChainSystem.fire()`
Cancel: X key → `ChainSystem.force_dissolve_all_chains()`

### Entity Hierarchy

```
EntityBase (entity_base.gd)
├── MonsterBase (monster_base.gd)         — HP, weak state, stun, lightning reactions
│   ├── MonsterWalk (DARK attribute)
│   ├── MonsterFly (LIGHT attribute)
│   ├── MonsterNeutral (NORMAL attribute)
│   ├── MonsterHand
│   └── MonsterHostile (fusion failure product, no weak state)
└── ChimeraBase (chimera_base.gd)         — fusion product, following/wandering/decomposition
    ├── ChimeraA (standard following chimera)
    └── ChimeraStoneSnake (attack type, fires projectiles, cannot be chain-linked)
```

**Weak state rule:** When monster HP ≤ `weak_hp`, it enters weak state (`hp_locked = true`) and cannot be killed by normal attacks — only fusion can finish it.

### Fusion System

`autoload/fusion_registry.gd` — singleton rule engine. Matches `(species_id_a, species_id_b)` pairs:

| Result | Effect |
|--------|--------|
| `SUCCESS` | Spawn chimera, both originals vanish |
| `FAIL_HOSTILE` | Spawn hostile monster (no weak state) |
| `FAIL_VANISH` | Both vanish, spawn healing sprites |
| `FAIL_EXPLODE` | Both explode + mud splash (chimera + chimera) |
| `HEAL_LARGE` | Heal/damage the larger entity |
| `REJECTED` | Blocked (same species, no rule) |

**Authoritative entity data:** `docs/C_ENTITY_DIRECTORY.md` and `docs/D_FUSION_RULES.md` — do not infer species_ids or fusion outcomes from code alone.

### Boss Enemy (StoneMaskBird)

Located in `scene/enemies/stone_mask_bird/`. Uses the **Beehave** behavior tree addon (in `addons/beehave/`) instead of a hardcoded FSM. Contains 11 action nodes and 7 condition nodes under `actions/` and `conditions/`.

### Autoloads (Global Singletons)

- `autoload/event_bus.gd` — global signal hub (thunder, healing, chain, fusion events). Emit via `EventBus.emit_*()`.
- `autoload/fusion_registry.gd` — fusion rule engine, loaded at startup.

### Input Mapping

| Action | Key |
|--------|-----|
| Move left/right | A / D |
| Jump | W |
| Cancel chains | X |
| Fuse | Space |
| Use healing sprite | C |
| Healing burst | Q |
| Fire chain | Mouse left click (direct input, not action-mapped) |
| Switch weapon | Z (direct input) |
