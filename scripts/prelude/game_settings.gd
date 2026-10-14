extends Node
## ============================================================================
##  《寻星》—— 跨场景的小设置（音量 / 自动播放剧情）
## ============================================================================
##  来源（Kerry 2026-10-14）：
##    「封面界面加功能（参考第 9 条），必要的如退出游戏，读取存档，设置（音量等）」
##    「在游玩过程中缺少暂停，存档，退出/回到主菜单（封面），设置的选项
##      （如有时间也可以加自动播放剧情的选项？）」
##
##  为什么不用 ConfigFile 读这份配置？—— 见 HANDOFF 坑 42：ConfigFile 读"开头有注释行"
##  的小文件会解析失败（或 section 读成空）。这里自己按行解析
##  （跳过空行与 `#` / `;`，取 `key=value`，引号可有可无）。
##
##  挂在 autoload 上（名字 GameSettings），所以任何场景里都能直接读：
##    `GameSettings.volume` / `GameSettings.autoplay`
##  找不到 autoload 时（headless --script 探针里 autoload 不注册）请用
##  `get_node_or_null("/root/GameSettings")`，别直接写标识符。
## ============================================================================

const CFG_PATH := "user://xunxing_settings.cfg"
## 自动播放剧情时，每句停留多久（秒）。太短来不及读，太长又会烦。
const AUTO_DELAY := 2.6

var volume: float = 0.8        ## 主音量，0..1 线性
var autoplay: bool = false     ## 自动播放剧情


func _ready() -> void:
	load_settings()
	apply_volume()


func apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	apply_volume()
	save_settings()


func set_autoplay(on: bool) -> void:
	autoplay = on
	save_settings()


func save_settings() -> void:
	var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("# 《寻星》设置（暂停菜单里的音量 / 自动播放改的就是这里）")
	f.store_line("volume=%.3f" % volume)
	f.store_line("autoplay=%s" % ("1" if autoplay else "0"))
	f.close()


func load_settings() -> void:
	if not FileAccess.file_exists(CFG_PATH):
		return
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with(";"):
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		val = val.trim_prefix("\"").trim_suffix("\"")
		match key:
			"volume":
				# 【坑】乱值（volume=abc）过去会被 to_float() 当 0.0 → 静默静音。
				# 配置坏了只该忽略这一行，不该把玩家音量清零（probe_pause 第 ④ 组盯着这里）。
				if val.is_valid_float():
					volume = clampf(val.to_float(), 0.0, 1.0)
			"autoplay":
				autoplay = val == "1" or val.to_lower() == "true" or val.to_lower() == "on"
	f.close()
