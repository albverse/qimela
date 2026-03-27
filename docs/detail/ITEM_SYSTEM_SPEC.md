# Item System Spec v0.2

## 1. Overview

Unified, configurable, extensible item template system.
- All items driven by `ItemData` resources (`.tres` files)
- Drop appearance (`drop_sprite`) and inventory display (`inventory_icon`) are separately configured
- Classification and behavior strictly constrained
- Decoupled from inventory: item system defines, inventory system holds and uses

## 2. Classification System

### 2.1 MainCategory
| Value | Name | Description |
|-------|------|-------------|
| 0 | USABLE | Can be actively used |
| 1 | NON_USABLE | Cannot be actively used |

### 2.2 SubCategory
| Value | Name | Description |
|-------|------|-------------|
| 0 | CONSUMABLE | Consumables (sprite bottles, potions, one-time attack magic) |
| 1 | KEY_ITEM | Important items (scene/NPC interaction, cannot sell/drop) |
| 2 | MATERIAL | General drops (can sell, quest delivery, cannot consume) |

### 2.3 UseType (behavior dispatch, decoupled from classification)
| Value | Name | Description |
|-------|------|-------------|
| 0 | NONE | No active effect (KEY_ITEM / MATERIAL) |
| 1 | HEAL | Restore HP |
| 2 | SUMMON_SPRITE | Release healing sprite |
| 3 | ATTACK_MAGIC | One-time attack spell |
| 4 | DEPLOY_PROP | Deploy scene object (puzzle) |
| 5 | SUMMON_CHIMERA | Chimera capsule |

### 2.4 Legal Matrix
- USABLE only pairs with CONSUMABLE
- NON_USABLE pairs with KEY_ITEM or MATERIAL
- CONSUMABLE must have use_type != NONE

## 3. ItemData Fields

| Field | Type | Description |
|-------|------|-------------|
| id | StringName | Globally unique, stable |
| display_name | String | UI display name |
| desc_short | String | Short description |
| main_category | MainCategory | USABLE / NON_USABLE |
| sub_category | SubCategory | CONSUMABLE / KEY_ITEM / MATERIAL |
| use_type | UseType | Behavior dispatch type |
| drop_sprite | Texture2D | World pickup appearance |
| inventory_icon | Texture2D | Backpack icon |
| max_stack | int (>=1) | Stack limit |
| cooldown_sec | float | Use cooldown |
| usable_in_combat | bool | Usable during combat |
| target_mode | TargetMode | SELF / GROUND / ENEMY / NONE |
| consume_on_use | bool | Consumed after use |
| sell_value | int (>=0) | Sale price |
| can_drop | bool | Can be dropped |
| can_sell | bool | Can be sold |
| tags | PackedStringArray | Optional tags (quest, rare, magic) |

Category-specific fields: `hp_restore`, `use_scene_path`, `deploy_scene_path`, `chimera_species_id`, `chimera_scene_path`

## 4. Validation Rules (ItemValidator)

1. KEY_ITEM => can_sell=false, can_drop=false
2. MATERIAL => main_category=NON_USABLE, consume_on_use=false
3. USABLE => sub_category=CONSUMABLE
4. CONSUMABLE => use_type != NONE
5. HEAL => hp_restore > 0
6. drop_sprite and inventory_icon cannot both be null
7. max_stack >= 1, sell_value >= 0

## 5. Inventory Integration

### 5.1 Storage Routing
- CONSUMABLE / KEY_ITEM: Main backpack (9 slots, capacity-limited)
- MATERIAL: OtherItems list (independent capacity, max 99)

### 5.2 Sort Priority (main backpack)
1. CONSUMABLE
2. KEY_ITEM
3. Empty slots

### 5.3 Pickup Failure
- CONSUMABLE/KEY_ITEM with full backpack and no stackable slot: ERR_INV_FULL
- MATERIAL: enters OtherItems, does not use main backpack capacity

## 6. Drop & Discard

### 6.1 World Drop
- Drop instance shows `drop_sprite`, retains `item_id` and `count`
- Pickup judgment unified through inventory system

### 6.2 Discard Behavior
- Source: OtherItems panel (materials primarily)
- Flow: Select item -> Confirm discard -> Spawn WorldItem at player feet
- Failure: ERR_DROP_FORBIDDEN for KEY_ITEM, ERR_INVALID_DROP_POS if no valid position

## 7. File Organization

```
inventory/
  item_data.gd          # ItemData resource class
  item_registry.gd      # Autoload: registration & query
  item_validator.gd     # Startup validation
  item_drop_helper.gd   # Autoload: monster drop management
  world_item.gd         # Pickupable world item
  inventory_test_loader.gd  # Debug utility
  items/                # .tres item definitions
    heal_potion_small.tres
    heal_potion_large.tres
    healing_sprite_bottle.tres
    key_old_medallion.tres

scene/components/
  player_inventory.gd   # Inventory logic (9-slot + OtherItems)

ui/
  inventory_ui.gd       # Main UI controller
  inventory_slot_ui.gd  # Individual slot rendering
  item_tooltip_ui.gd    # Tooltip with lock-on behavior
  other_items_panel_ui.gd   # MATERIAL items panel
  drop_confirm_dialog_ui.gd # Discard confirmation
```

## 8. EventBus Signals

```
inventory_opened()
inventory_closed()
inventory_selection_changed(slot_idx: int)
inventory_item_added(slot_idx: int, item: Resource, count: int)
inventory_item_removed(slot_idx: int)
inventory_item_used(item_id: StringName, slot_idx: int)
inventory_item_failed(item_id: StringName, slot_idx: int, err_code: int)
inventory_full()
inventory_pickup_failed(item_id: StringName, reason: int)
inventory_open_other_items()
inventory_close_other_items()
inventory_drop_item(item_id: StringName, count: int)
inventory_slots_sorted()
```

## 9. State Machine

```
Closed -> Opening -> OpenMain -> OpenOther -> Closing -> Closed
                  \-> Closing <-/          <-/
```

- B on Closed -> Opening
- Opening done -> OpenMain
- OpenMain + "+" slot + E -> OpenOther
- OpenOther + B/Esc -> OpenMain
- OpenMain + B -> Closing
- Closing done -> Closed
- Die/Petrified -> force Closing

## 10. New Item Workflow

1. Create .tres in `inventory/items/` with all required fields
2. ItemValidator checks on startup
3. Configure drop table in `item_drop_helper.gd`
4. If USABLE, bind effect via `use_type` dispatch
5. Test: pickup, sort, use/fail feedback, sell/discard constraints
