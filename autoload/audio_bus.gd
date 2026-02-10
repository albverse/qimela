extends Node

## AudioBus — 全局唯一音频入口（autoload）
##
## 规则：工程内任何脚本禁止直接使用 AudioStreamPlayer.play()。
##       所有音频播放必须通过本单例：
##         AudioBus.play_sfx("hit_light")
##         AudioBus.play_bgm("area_forest")
##         AudioBus.play_ui("confirm")
##
## 架构：
##   - 4 条 Godot 音频总线：Master / BGM / SFX / UI（_ready 自动创建）
##   - 1 个 BGM 播放器（支持 crossfade）
##   - 1 个 SFX 对象池（AudioStreamPlayer / AudioStreamPlayer2D）
##   - 限频 + 并发上限 护栏
##   - 数据化 catalog：sfx_id → 资源路径，换音效只改表不改代码

# =============================================================================
# 配置常量
# =============================================================================

## SFX 对象池大小（同时能发出的最大音效数）
const SFX_POOL_SIZE: int = 16

## 同一 sfx_id 的最小触发间隔（毫秒），防止同帧爆音
const SFX_COOLDOWN_MS: int = 80

## 同一 sfx_id 同时播放的最大并发数
const SFX_MAX_CONCURRENT: int = 3

## BGM crossfade 时长（秒）
const BGM_FADE_TIME: float = 0.8

# =============================================================================
# 音频总线名（与 Godot AudioServer bus 一一对应）
# =============================================================================
const BUS_MASTER: StringName = &"Master"
const BUS_BGM: StringName    = &"BGM"
const BUS_SFX: StringName    = &"SFX"
const BUS_UI: StringName     = &"UI"

# =============================================================================
# 音频目录（sfx_id / bgm_id / ui_id → 资源路径）
# 后期可替换为 .tres / .json 外部文件；MVP 阶段用字典即可
# =============================================================================

## SFX 目录
## 格式：&"sfx_id": "res://audio/sfx/xxx.wav"
## 占位 ID 先注册，资源路径留空字符串表示"尚无资产"
var sfx_catalog: Dictionary = {
	# ── 战斗 ──
	&"chain_fire":        "",   # 锁链发射
	&"chain_hit":         "",   # 锁链命中（普通受击扣血）
	&"chain_bind":        "",   # 锁链链接成功
	&"chain_release":     "",   # 锁链断开/溶解
	&"chain_cancel":      "",   # 手动取消锁链
	&"hit_light":         "",   # 轻攻击命中
	&"hit_heavy":         "",   # 重攻击命中
	&"swing_chain":       "",   # 锁链挥动/甩出
	&"swing_sword":       "",   # 剑轻攻击挥砍
	&"swing_knife":       "",   # 刀轻攻击挥砍

	# ── 怪物 ──
	&"monster_hurt":      "",   # 怪物受击（通用）
	&"monster_stun":      "",   # 怪物进入眩晕
	&"monster_weak":      "",   # 怪物进入虚弱
	&"monster_die":       "",   # 怪物死亡

	# ── 融合 ──
	&"fusion_start":      "",   # 融合开始
	&"fusion_success":    "",   # 融合成功
	&"fusion_fail":       "",   # 融合失败
	&"vanish_fusion":     "",   # 泯灭融合一次

	# ── 玩家 ──
	&"player_hurt":       "",   # 玩家受击
	&"player_die":        "",   # 玩家死亡
	&"player_land":       "",   # 落地
	&"player_jump":       "",   # 跳跃
	&"heal_pickup":       "",   # 拾取治愈精灵
	&"heal_use":          "",   # 使用治愈精灵回血
	&"healing_burst":     "",   # 治愈精灵大爆炸

	# ── 环境 ──
	&"thunder":           "",   # 雷击
	&"thunder_flower":    "",   # 雷花绽放
}

## BGM 目录
var bgm_catalog: Dictionary = {
	&"title":             "",   # 标题画面
	&"area_forest":       "",   # 森林区域
	&"area_cave":         "",   # 洞窟区域
	&"boss":              "",   # Boss 战
}

## UI 音效目录
var ui_catalog: Dictionary = {
	&"confirm":           "",   # 确认
	&"cancel":            "",   # 取消
	&"select":            "",   # 选择切换
	&"pause":             "",   # 暂停
	&"unpause":           "",   # 取消暂停
	&"weapon_switch":     "",   # 武器切换
	&"slot_switch":       "",   # 锁链槽位切换
}

# =============================================================================
# 内部状态
# =============================================================================

# BGM
var _bgm_player_a: AudioStreamPlayer = null
var _bgm_player_b: AudioStreamPlayer = null  # crossfade 用
var _bgm_current_id: StringName = &""
var _bgm_fade_tween: Tween = null

# SFX pool
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_idx: int = 0  # 轮询索引

# UI player（单独一个，UI 音效不需要池子）
var _ui_player: AudioStreamPlayer = null

# 限频表：sfx_id → 上次播放时间戳（msec）
var _sfx_last_time: Dictionary = {}

# 并发计数：sfx_id → 当前正在播放的数量
var _sfx_concurrent: Dictionary = {}


# =============================================================================
# 生命周期
# =============================================================================

func _ready() -> void:
	_ensure_audio_buses()
	_create_bgm_players()
	_create_sfx_pool()
	_create_ui_player()


# =============================================================================
# 公共 API — SFX
# =============================================================================

## 播放音效
## sfx_id: 目录中注册的 ID（如 &"hit_light"）
## volume_db: 音量偏移（默认 0）
## pitch_scale: 音高（默认 1.0，可做随机微调）
func play_sfx(sfx_id: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	# 查找资源
	var path: String = sfx_catalog.get(sfx_id, "") as String
	if path == "":
		# 资源尚未配置，静默跳过（开发期正常）
		return

	# 限频护栏
	var now_ms: int = Time.get_ticks_msec()
	var last_ms: int = _sfx_last_time.get(sfx_id, 0) as int
	if (now_ms - last_ms) < SFX_COOLDOWN_MS:
		return

	# 并发护栏
	var concurrent: int = _sfx_concurrent.get(sfx_id, 0) as int
	if concurrent >= SFX_MAX_CONCURRENT:
		return

	# 加载音频流
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		return

	# 从池中取一个空闲播放器
	var player: AudioStreamPlayer = _acquire_sfx_player()
	if player == null:
		return

	# 播放
	player.stream = stream
	player.bus = BUS_SFX
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

	# 更新护栏数据
	_sfx_last_time[sfx_id] = now_ms
	_sfx_concurrent[sfx_id] = concurrent + 1

	# 播放结束时回收并发计数
	if not player.finished.is_connected(_on_sfx_finished):
		player.finished.connect(_on_sfx_finished.bind(sfx_id))
	else:
		# 重连（因为 bind 参数不同）
		player.finished.disconnect(_on_sfx_finished)
		player.finished.connect(_on_sfx_finished.bind(sfx_id))


# =============================================================================
# 公共 API — BGM
# =============================================================================

## 播放 BGM（自动 crossfade，相同 ID 不重复播放）
func play_bgm(bgm_id: StringName, volume_db: float = 0.0) -> void:
	if bgm_id == _bgm_current_id:
		return

	var path: String = bgm_catalog.get(bgm_id, "") as String
	if path == "":
		return

	var stream: AudioStream = _load_stream(path)
	if stream == null:
		return

	_crossfade_bgm(stream, volume_db)
	_bgm_current_id = bgm_id


## 停止 BGM（淡出）
func stop_bgm() -> void:
	if _bgm_current_id == &"":
		return
	_fade_out_bgm()
	_bgm_current_id = &""


## 获取当前 BGM ID
func get_current_bgm() -> StringName:
	return _bgm_current_id


# =============================================================================
# 公共 API — UI
# =============================================================================

## 播放 UI 音效
func play_ui(ui_id: StringName, volume_db: float = 0.0) -> void:
	var path: String = ui_catalog.get(ui_id, "") as String
	if path == "":
		return

	var stream: AudioStream = _load_stream(path)
	if stream == null:
		return

	_ui_player.stream = stream
	_ui_player.bus = BUS_UI
	_ui_player.volume_db = volume_db
	_ui_player.play()


# =============================================================================
# 公共 API — 音量控制
# =============================================================================

## 设置 BGM 音量（linear 0.0 ~ 1.0）
func set_volume_bgm(linear: float) -> void:
	_set_bus_volume(BUS_BGM, linear)

## 设置 SFX 音量（linear 0.0 ~ 1.0）
func set_volume_sfx(linear: float) -> void:
	_set_bus_volume(BUS_SFX, linear)

## 设置 UI 音量（linear 0.0 ~ 1.0）
func set_volume_ui(linear: float) -> void:
	_set_bus_volume(BUS_UI, linear)

## 设置 Master 音量（linear 0.0 ~ 1.0）
func set_volume_master(linear: float) -> void:
	_set_bus_volume(BUS_MASTER, linear)

## 获取音量（返回 linear 0.0 ~ 1.0）
func get_volume_bgm() -> float:
	return _get_bus_volume(BUS_BGM)

func get_volume_sfx() -> float:
	return _get_bus_volume(BUS_SFX)

func get_volume_ui() -> float:
	return _get_bus_volume(BUS_UI)

func get_volume_master() -> float:
	return _get_bus_volume(BUS_MASTER)

## 静音/取消静音某条总线
func set_mute(bus_name: StringName, muted: bool) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)

func is_muted(bus_name: StringName) -> bool:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return AudioServer.is_bus_mute(idx)
	return false


# =============================================================================
# 公共 API — Catalog 管理
# =============================================================================

## 运行时注册/更新 SFX 资源路径
func register_sfx(sfx_id: StringName, resource_path: String) -> void:
	sfx_catalog[sfx_id] = resource_path

## 运行时注册/更新 BGM 资源路径
func register_bgm(bgm_id: StringName, resource_path: String) -> void:
	bgm_catalog[bgm_id] = resource_path

## 运行时注册/更新 UI 资源路径
func register_ui(ui_id: StringName, resource_path: String) -> void:
	ui_catalog[ui_id] = resource_path


# =============================================================================
# 内部：音频总线初始化
# =============================================================================

func _ensure_audio_buses() -> void:
	## 确保 BGM / SFX / UI 三条子总线存在（幂等）
	for bus_name: StringName in [BUS_BGM, BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx: int = AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)


# =============================================================================
# 内部：播放器创建
# =============================================================================

func _create_bgm_players() -> void:
	_bgm_player_a = AudioStreamPlayer.new()
	_bgm_player_a.name = "BGM_A"
	_bgm_player_a.bus = BUS_BGM
	add_child(_bgm_player_a)

	_bgm_player_b = AudioStreamPlayer.new()
	_bgm_player_b.name = "BGM_B"
	_bgm_player_b.bus = BUS_BGM
	add_child(_bgm_player_b)


func _create_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%02d" % i
		p.bus = BUS_SFX
		add_child(p)
		_sfx_pool.append(p)


func _create_ui_player() -> void:
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UI"
	_ui_player.bus = BUS_UI
	add_child(_ui_player)


# =============================================================================
# 内部：SFX 池管理
# =============================================================================

func _acquire_sfx_player() -> AudioStreamPlayer:
	## 轮询取一个空闲（或最早的）播放器
	var start: int = _sfx_pool_idx
	for _i in SFX_POOL_SIZE:
		var idx: int = (_sfx_pool_idx + _i) % SFX_POOL_SIZE
		var p: AudioStreamPlayer = _sfx_pool[idx]
		if not p.playing:
			_sfx_pool_idx = (idx + 1) % SFX_POOL_SIZE
			return p
	# 全部在播：强占最早那个
	var p: AudioStreamPlayer = _sfx_pool[start]
	p.stop()
	_sfx_pool_idx = (start + 1) % SFX_POOL_SIZE
	return p


func _on_sfx_finished(sfx_id: StringName) -> void:
	var c: int = _sfx_concurrent.get(sfx_id, 0) as int
	if c > 0:
		_sfx_concurrent[sfx_id] = c - 1


# =============================================================================
# 内部：BGM crossfade
# =============================================================================

func _crossfade_bgm(new_stream: AudioStream, volume_db: float) -> void:
	if _bgm_fade_tween != null:
		_bgm_fade_tween.kill()
		_bgm_fade_tween = null

	# 确定哪个播放器正在播、哪个空闲
	var old_player: AudioStreamPlayer = _bgm_player_a if _bgm_player_a.playing else _bgm_player_b
	var new_player: AudioStreamPlayer = _bgm_player_b if old_player == _bgm_player_a else _bgm_player_a

	# 新播放器：设置流并以静音开始
	new_player.stream = new_stream
	new_player.volume_db = -80.0
	new_player.play()

	# crossfade tween
	_bgm_fade_tween = create_tween().set_parallel(true)
	# 淡入新
	_bgm_fade_tween.tween_property(new_player, "volume_db", volume_db, BGM_FADE_TIME)
	# 淡出旧
	if old_player.playing:
		_bgm_fade_tween.tween_property(old_player, "volume_db", -80.0, BGM_FADE_TIME)
		_bgm_fade_tween.set_parallel(false)
		_bgm_fade_tween.tween_callback(old_player.stop)


func _fade_out_bgm() -> void:
	if _bgm_fade_tween != null:
		_bgm_fade_tween.kill()
		_bgm_fade_tween = null

	_bgm_fade_tween = create_tween()
	if _bgm_player_a.playing:
		_bgm_fade_tween.tween_property(_bgm_player_a, "volume_db", -80.0, BGM_FADE_TIME)
		_bgm_fade_tween.tween_callback(_bgm_player_a.stop)
	if _bgm_player_b.playing:
		_bgm_fade_tween.tween_property(_bgm_player_b, "volume_db", -80.0, BGM_FADE_TIME)
		_bgm_fade_tween.tween_callback(_bgm_player_b.stop)


# =============================================================================
# 内部：工具函数
# =============================================================================

var _stream_cache: Dictionary = {}

func _load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		push_warning("[AudioBus] Resource not found: %s" % path)
		return null
	var stream: AudioStream = load(path) as AudioStream
	if stream != null:
		_stream_cache[path] = stream
	return stream


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	if linear <= 0.0:
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


func _get_bus_volume(bus_name: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	var db: float = AudioServer.get_bus_volume_db(idx)
	if db <= -80.0:
		return 0.0
	return db_to_linear(db)
