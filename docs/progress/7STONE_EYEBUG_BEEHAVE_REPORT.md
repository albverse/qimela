# StoneEyeBug 行为与动画逻辑总览（按当前代码）

> 本文为“当前代码已实现逻辑”的自然语言快照，便于对照调试与验收。

## 1. 状态与总流程

StoneEyeBug 目前有 5 个核心状态：

- `NORMAL`：正常巡走/待机。
- `RETREATING`：正在缩壳（进入壳体过程）。
- `IN_SHELL`：缩壳完成后的壳内阶段。
- `FLIPPED`：被翻倒阶段。
- `EMPTY_SHELL`：软体分离后的空壳冻结阶段。

Beehave 主优先级为：

`FLIPPED > RETREATING > ATTACK > IN_SHELL > WANDER`

含义：
- 一旦翻倒，优先执行翻倒流程；
- 其次执行缩壳流程；
- 再判断是否在壳内可攻击；
- 然后才是壳内等待出壳；
- 最后才是走路/待机兜底。

---

## 2. 动画命名与旧名

当前代码统一使用：

- `normal_to_flip`
- `flip_to_normal`
- `escape_split`
- `empty_loop`
- `hit_shell`
- `hit_shell_small`

旧拼写 `flip` / `nomal_to_flip` / `flip_to_nomal` 视为历史名，不再作为现行逻辑入口。

---

## 3. 翻倒（FLIPPED）完整规则

### 3.1 入场

进入 `FLIPPED` 后先播：

`normal_to_flip`（一次）→ `struggle_loop`（循环）

### 3.2 恢复为缩壳流

`struggle_loop` 期间满足任一条件会进入恢复：

1. 被以下来源命中一次：
   - `ghost_fist`
   - `chimera_ghost_hand_l`
   - `stone_mask_bird_face_bullet`
2. 或翻倒持续超时 5 秒。

恢复动画链：

`flip_to_normal -> idle`，随后立刻切 `RETREATING`（进入缩壳流）。

### 3.3 分裂逃出（escape_split）

`struggle_loop` 期间，如果 SoftHurtbox 被“非上面三类来源”命中累计超过 3 次：

- 播放 `escape_split`（不可打断）；
- 在 `escape_spawn` 事件点生成 `Mollusc`；
- 壳体进入 `EMPTY_SHELL`，播放 `empty_loop`。

---

## 4. 缩壳流（RETREATING / IN_SHELL）与攻击窗口

### 4.1 缩壳动作链

缩壳流程动作是：

- 若 `is_thunder_pending == true`：先播 `hit_shell`；
- 然后播 `retreat_in`；
- 进入 `IN_SHELL` 后播 `in_shell_loop`；
- 壳内安全时间到（`shell_safe_time`）后播 `emerge_out`，回 `NORMAL`。

### 4.2 攻击只在壳内触发

攻击条件是双门：

1. `mode == IN_SHELL`；
2. `attack_enabled_after_player_retreat == true` 且冷却到时。

因此：

- 行走/idle（`NORMAL`）不会触发攻击；
- 只有进入壳内后才会做 `attack_stone -> attack_lick`。

### 4.3 攻击窗口开启/关闭

- 缩壳流开始时（`_start_retreat`）会开启攻击窗口并设置冷却起点；
- 每次攻击动作结束会关闭窗口（避免普通移动态连发）。

---

## 5. LightFlower 触发规则（重点）

当前边界是：

- StoneEyeBug **不直接响应全局 thunder_burst**；
- StoneEyeBug 只通过 `on_light_exposure()` 响应 LightFlower 光照释放。

触发效果：

- 非缩壳态下：立即进入 `is_thunder_pending + RETREATING`，由壳流动作播放 `hit_shell -> retreat_in`；
- 已在 `RETREATING/IN_SHELL` 时：LightFlower 触发无效（不刷新壳计时），避免壳流程被反复续时。

---

## 6. 被击中规则（apply_hit）

### 6.1 可触发翻倒的来源

以下来源可触发翻倒：

- `ghost_fist`
- `chimera_ghost_hand_l`
- `stone_mask_bird_face_bullet`

并且在 `NORMAL`、`RETREATING`、`IN_SHELL` 下都可使其转入 `FLIPPED`（缩壳中也可被中断翻倒）。

### 6.2 空壳阶段

`EMPTY_SHELL` 下受击交互基本冻结（只等软体回壳通知）。

### 6.3 壳体无效受击反馈

对“无效伤害命中壳体”统一走 `hit_shell_small` 反馈：

- 关键动画/关键状态时不插播，仅闪白；
- 非关键阶段可插播 `hit_shell_small`。

---

## 7. 锁链命中规则（on_chain_hit）

- `FLIPPED + SoftHurtbox`：计入 escape_split 次数。
- `NORMAL + SoftHurtbox`：触发缩壳并可打开攻击窗口。
- `EMPTY_SHELL`：不接受链交互。
- 链命中壳体无效伤害：也会触发与 `apply_hit` 一致的 `hit_shell_small` 反馈路径。

---

## 8. Hurtbox / LightReceiver 开关逻辑

按状态实时切换：

- `NORMAL`：壳体、软体、LightReceiver 全开。
- `RETREATING/IN_SHELL`：壳体开，软体关，LightReceiver 开。
- `FLIPPED`：壳体关，软体按 `soft_hitbox_active`，LightReceiver 开。
- `EMPTY_SHELL`：壳体开，软体关，LightReceiver 关。

这保证了空壳不会继续吃光照链路，回壳后再恢复。

---

## 9. 空壳与回壳

### 9.1 进入空壳

`notify_become_empty_shell()` 会：

- 设为 `EMPTY_SHELL`；
- 关闭翻倒/攻击窗口相关标志；
- 重置弱化/锁血相关状态；
- 保留空壳等待软体回壳。

### 9.2 软体回壳

`notify_shell_restored()` 会：

- 回到 `IN_SHELL`；
- 重新启用 `LightReceiver`；
- 播放 `in_shell_loop`。

---

## 10. 软体（Mollusc）补充

- StoneEyeBug 会在 `escape_spawn` 事件点优先从 `MolluscSpawnMark` 位置生成软体；
- `ActMolluscAttack` 已去除不存在的 die 字段依赖，仅按受击状态中断。

---

## 11. 本文件用途

该文档只描述“当前代码已经实现的行为事实”，用于：

- 玩法验收对照；
- 动画联调核对；
- 回归测试时快速判断“是逻辑变更还是资源事件缺失”。
