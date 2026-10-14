extends SceneTree
## 写一份 llm.cfg 模板到 user://（key 留空 = 面板里不出现「自己打字问」）
## 跑法：godot --headless --path <项目> --script tools/write_llm_config.gd
## 想自己试：把 api_key 填上（服务商的 key），需要的话改 base_url / model。

const PATH := "user://llm.cfg"


func _initialize() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		print("写不进去：", PATH, "，错误码 ", FileAccess.get_open_error())
		quit(1)
		return
	f.store_line("# 《寻星》海龟汤「自己打字问」用的模型配置")
	f.store_line("# 这个文件在 user:// 下（项目目录之外），导出时不会被打包。")
	f.store_line("# api_key 留空 = 游戏里保留原来的点按钮模式，不会出现「自己打字问」。")
	f.store_line("")
	f.store_line("[llm]")
	f.store_line("base_url=\"https://api.deepseek.com/v1\"")
	f.store_line("api_key=\"\"")
	f.store_line("model=\"deepseek-chat\"")
	f.store_line("timeout=20.0")
	f.close()
	# 【坑 42】不要用 ConfigFile 读回来：它对"开头有注释行"的这份小文件会报
	# `parse error ... Expected value, got 'ERROR'`。这里跟 LlmClient 一样按行看。
	var vals := {}
	if FileAccess.file_exists(PATH):
		for raw in FileAccess.get_file_as_string(PATH).split("\n"):
			var line := raw.strip_edges()
			if line == "" or line.begins_with("#") or line.begins_with(";") or not line.contains("="):
				continue
			var eq := line.find("=")
			vals[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	print("已写入 ", ProjectSettings.globalize_path(PATH))
	print("  base_url = ", str(vals.get("base_url", "")))
	print("  model    = ", str(vals.get("model", "")))
	print("  api_key  = ", "（空：不出现「自己打字问」）" if str(vals.get("api_key", "")) == "" else "（已填写）")
	quit(0)
