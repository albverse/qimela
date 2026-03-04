# StoneMaskBird shoot_face 防回归最小复现步骤

> 目标：验证 StoneMaskBird 在进入 `shoot_face` 后，不会因为自身发射的面具弹命中自己而切到 `HURT`，并且 `shoot_face_committed` 与 `mode` 在动画结束前后保持一致。

## 1. 准备

1. 在测试场景放置 1 只 `StoneMaskBird` 与玩家。
2. 将该鸟的 `debug_shoot_face_mode_log` 置为 `true`。
3. 让玩家进入 `face_shoot_range_px` 触发 `ActShootFace`。

## 2. 观察点

### 必须满足

- 进入 `SHOOTING` 后日志出现：
  - `enter SHOOTING mode=FLYING_ATTACK`
- 发射期间即使出现面具弹碰撞，日志应出现（可选）：
  - `ignore self face bullet while committed`
- `SHOOTING` 期间不应出现：
  - `mode changed in SHOOTING: FLYING_ATTACK -> HURT`
- 动画结束后按预期收敛：
  - `clear committed: shoot_face_anim_finished`
  - `set mode: RETURN_TO_REST (shoot_face finished)`

### 失败判定

- `shoot_face` 动画未结束就切换到 `HURT`。
- `shoot_face_committed=false` 但 `mode` 仍停留在 `FLYING_ATTACK + shoot_face`。
- 出现 `skip clear committed on unexpected interrupt mode=HURT`（代表仍存在异常中断路径）。

## 3. 建议脚本化检查（日志断言）

- 抓取包含 `[StoneMaskBird][ShootFace][DEBUG]` 的日志。
- 断言：在同一轮 shoot_face 周期内，`enter SHOOTING` 与 `set mode: RETURN_TO_REST` 成对出现。
- 断言：不存在 `-> HURT` 的 mode 变更记录。
