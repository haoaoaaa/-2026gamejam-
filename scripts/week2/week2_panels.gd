class_name Week2Panels
extends RefCounted
## ============================================================================
##  《寻星》二周目 —— 小游戏面板登记表
## ============================================================================
##  对话脚本里写 ["panel", id]，dialogue_runtime 会先查一周目的表、再查这张表。
##  新增一关 = 这里加一行 + 写一个 scripts/week2/panel_<id>.gd（继承 scripts/week1/panel_base.gd）。
## ============================================================================

const SCRIPTS := {
	"reason": "res://scripts/week2/panel_reason.gd",
	"alibi": "res://scripts/week2/panel_alibi.gd",
	## 两张"具体图示"（文档要求在推理处出现图）：剖面图 / 水迹成圆
	"slant": "res://scripts/week2/panel_slant.gd",
	"circle": "res://scripts/week2/panel_circle.gd",
}


static func has_panel(id: String) -> bool:
	return SCRIPTS.has(id)


static func script_for(id: String) -> String:
	return str(SCRIPTS.get(id, ""))
