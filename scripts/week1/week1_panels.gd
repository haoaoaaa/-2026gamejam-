class_name Week1Panels
extends RefCounted
## ============================================================================
##  《寻星》一周目 —— 小游戏面板登记表
## ============================================================================
##  对话脚本里写 ["panel", id]，dialogue_runtime 到这里查脚本路径。
##  新增一关 = 在这里加一行 + 写一个 scripts/week1/panel_<id>.gd（继承 panel_base.gd）。
## ============================================================================

const SCRIPTS := {
	"maze": "res://scripts/week1/panel_maze.gd",
	"gesture": "res://scripts/week1/panel_gesture.gd",
	"memo": "res://scripts/week1/panel_memo.gd",
	"bookshelf": "res://scripts/week1/panel_bookshelf.gd",
	"desk": "res://scripts/week1/panel_desk.gd",
	"soup": "res://scripts/week1/panel_soup.gd",
	"mindread": "res://scripts/week1/panel_mindread.gd",
	"wardrobe": "res://scripts/week1/panel_wardrobe.gd",
}


static func has_panel(id: String) -> bool:
	return SCRIPTS.has(id)


static func script_for(id: String) -> String:
	return str(SCRIPTS.get(id, ""))
