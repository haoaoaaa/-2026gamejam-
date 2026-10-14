extends "res://scripts/prelude/prelude_base.gd"
## ============================================================================
##  《寻星》一周目（游戏最开头的一幕）
## ============================================================================
##  六关：七色镜廊（调整镜面，把七束光送回同色的口子）+ 手势密码 → 手机备忘录+凯撒密码 → 书架九本书 → 书桌七处偏差
##        → 海龟汤 → 衣柜密码盒
##        第 5 关与第 6 关之间插一段**回忆**（s4b_1089：刘忆的「读心术」，按《附录2》，
##        面板 id 是 mindread）——它没有解密关卡那么重，是这一夜里唯一一段温的。
##
##  【新链】六关播完 **先演前日谈**，前日谈两幕演完再回到这一幕的收尾
##  （["title", "第二天", "寝室里没有人"]），收尾播完才接【二周目】：
##      走廊 → 进寝室 → 一周目六关 → 前日谈（prelude_1 → prelude_2）
##        → 一周目收尾（s6_ending）→ 二周目
##  所以这一幕会被进入两次，靠 PreludeState 的 prelude_done 标记区分：
##    · 没演过前日谈 → 播六关（DAY_ONE_SEQS），播完转前日谈第一幕；
##    · 演过了（prelude_2 的出口把标记立起来）→ 只播收尾（ENDING_SEQS），
##      播完转二周目。这样"从前日谈回来"既不会重播六关，也不是回到开头。
## ============================================================================

## 二周目（收尾播完接这里）
const WEEK2_SCENE := "res://scenes/week2/week2_1.tscn"
## 前日谈第一幕（六关播完接这里）
const PRELUDE_1_SCENE := "res://scenes/prelude/prelude_1.tscn"

## 「前日谈已经演过」标记的键名。
## 【注意】scripts/prelude/prelude_2.gd 里的同名常量必须与它一致（那边立起来，这边读）。
const PRELUDE_DONE_FLAG := "prelude_done"

## 六关（第一天的当天）。s4b_1089 是第 5、6 关之间的回忆段（按 Kerry：1089 回忆放在一周目 5、6 关之间）。
const DAY_ONE_SEQS := ["s0_maze", "s1_phone", "s2_books", "s3_desk", "s4_soup", "s4b_1089", "s5_wardrobe"]
## 收尾（从前的 s5_wardrobe 尾部拆出来的独立一段）：
## ["space", …] + ["hide", "李星"] + ["title", "第二天", "寝室里没有人"]。
## 它必须等前日谈演完才播，所以单独立一段、由 chapter_sequences() 决定要不要播。
const ENDING_SEQS := ["s6_ending"]


func data_path() -> String:
	return "res://data/week1_dialogue.json"


func chapter_id() -> String:
	return "week1"


## 这一幕要播的段：前日谈没演过就播六关，演过了（= 从 prelude_2 回到这里）只播收尾。
func chapter_sequences() -> Array:
	return ENDING_SEQS if _prelude_done() else DAY_ONE_SEQS


func return_scene() -> String:
	return "res://scenes/week1/week1_1.tscn"


## 这一幕播完之后接哪一幕（探针直接断言这个函数，不用真的切场景）。
func next_scene_after_chapter() -> String:
	return WEEK2_SCENE if _prelude_done() else PRELUDE_1_SCENE


func _prelude_done() -> bool:
	return bool(PreludeState.get_flag(PRELUDE_DONE_FLAG, false))


func _on_chapter_end() -> void:
	if runtime != null:
		runtime.visible = false
	if _prelude_done():
		# 收尾（["title", "第二天", …]）播完了 → 进二周目
		_show_intermission("第一天 结束   ·   点击 / 空格  继续", _goto_next_scene)
	else:
		# 六关播完了 → 先去前日谈，前日谈演完再回到这一幕的收尾
		_show_intermission("第一天 结束   ·   点击 / 空格  进入前日谈", _goto_next_scene)


func _goto_next_scene() -> void:
	# 不 reset：一周目的笔记（笔记 Tab）带进二周目，玩家才有"我查过一遍了"的连续性。
	get_tree().change_scene_to_file(next_scene_after_chapter())
