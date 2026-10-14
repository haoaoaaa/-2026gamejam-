# 《寻星》· 前日谈 交接说明（HANDOFF）

项目根目录：`E:\Godot\yongxian`
引擎：**Godot v4.7.2.stable.official.ed1daf0bf**
可执行文件：`E:\Godot_v4.7.2-stable_win64_console.exe`（**console 版才有 stdout**，
调试一律用它；同目录的 `Godot_v4.7.2-stable_win64.exe` 是没有控制台输出的）

---

## 一、怎么跑

```powershell
# 导入素材（改了 png / tscn 之后跑一次）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --import

# 整个游戏（封面 → 第一天六关 → 前日谈 → 第一天收尾 → 第二天 → 标题）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --path 'E:\Godot\yongxian' --rendering-driver opengl3

# 跳过封面，直接进一周目
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --path 'E:\Godot\yongxian' --rendering-driver opengl3 res://scenes/week1/week1_1.tscn

# 第一幕（编辑器里 F6 选 prelude_1.tscn 同理）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --path 'E:\Godot\yongxian' --rendering-driver opengl3 res://scenes/prelude/prelude_1.tscn

# 第二幕
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --path 'E:\Godot\yongxian' --rendering-driver opengl3 res://scenes/prelude/prelude_2.tscn

# 只跑某个俯视角房间（调试用：没有 walk_room 标记会退回对话场景）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --path 'E:\Godot\yongxian' --rendering-driver opengl3 res://scenes/prelude/prelude_walk.tscn
```

`project.godot` 的 `run/main_scene` 指向 `res://scenes/title/title.tscn`（封面），
所以直接 F5 是封面 → 点一下进第一天六关；整条链是
**封面 → 第一天六关 → 前日谈（两幕）→ 第一天收尾 → 第二天 → 回标题页**（详见坑 58）。

**操作**：鼠标左键 / 空格 = 推进对话；走过场时 **WASD 或方向键**走动，
空格 / E / 点击 = 查看身边物件，弹窗里再按空格收起；**Tab** 打开笔记页，
**Esc** 也可以（另外 `T` 也能开笔记）。

### 验证脚本（改完一定要跑）

```powershell
node tools/check_gdscript.mjs      # GDScript 静态结构自检
node tools/validate_prelude.mjs    # 剧本 JSON 校验（序列数 / 行数 / 出错项）

# 一周目端到端自检：八个面板 + 三次走位 + 幕间 + 章节链（209 项，全绿才算过）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_week1.gd

# 二周目端到端自检：四个面板 + 一次现场走位 + 章节链（85 项，全绿才算过）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_week2.gd

# 走位房间自检：镜头是否 1:1 跟随 / 靠近判定 / 弹窗（19 项，全绿才算过）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_walk.gd

# 走位 → 对话 恢复自检：把整幕按真实流程走一遍（21 项，全绿才算过）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_resume.gd

# 家具碰撞自检：挡路块数 / 撞得住 / 能滑开 / 出生点（18 项，全绿才算过）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_collide.gd

# 立绘抠图自检：七张立绘逐个报"人物本体被抠掉 0 px"（走 PreludeUI.load_texture）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_portrait.gd

# 七色镜廊自检：静态布局 + 真实光线追踪 + 点格子 + 判胜（60 项，全绿才算过）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_maze.gd
# 镜廊求解器：全枚举每个框的空/／/＼，打印解数与所有解（改题目数据后必须仍为「解数 = 1」）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/solve_maze.gd

# 海龟汤自检：16 题点满 10 个解锁挑词 / 16 选 6 对错路径 / 连错 3 次给「看汤底」（42 项）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_soup.gd

# 回看 / 自动存档 / 笔记 / 标题页自检（62 项）
# ⚠ 它会真写 user://xunxing_save.json，但**开跑前会把玩家原档备份、结束时还原**
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_save.gd

# 暂停菜单 / 设置自检（73 项）：Esc 开合、paused 联动、六颗按钮、
# process_mode 必须 ALWAYS、blocks_pause 让位、自动播放计时、坏配置行不崩
# ⚠ 它也会写 user://xunxing_settings.cfg，同样备份 + 还原
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/probe_pause.gd

# 素材入库（幂等；**只管封面与道具**，七张立绘是 Kerry 自己抠好的、不在清单里）
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/import_assets.gd

# 立绘对照图：并排拼出 _pv.png（深色底实看）与 _pva.png（alpha 一眼看漏抠），看完全删
& 'E:\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'E:\Godot\yongxian' --script tools/preview_portraits.gd
```

`probe_week1.gd` 是**一周目的总闸**：静态检查剧本 / 房间物件 / 面板登记 / 面板顺序，
然后把整幕从标题卡一路点到幕间——八个面板用 `close_panel()` 替玩家过关、三次走位模拟
"走到目标物件跟前看了它"、校验过关结果与恢复点、追加台词、最后确认能到幕间。
改了一周目的任何文件（剧本、面板、`week1_1.gd`）都先跑它。

`probe_week2.gd` 是**二周目的总闸**，做法一样，差别有两点：①它多查**章节链**——从
`week1_1.gd` / `week2_1.gd` 的常量读出"这一幕播完接哪个场景"并确认文件真的存在，
再去 `prelude_2.gd` 的正文里找"回到一周目 + 清存档"；②二周目那次走位是**没有目标物件、
要求把房间看全**，所以探针会把 `dorm_after` 里七件东西全部标成"看过"再放行。
改了二周目的剧本 / 面板 / `week2_1.gd` / `prelude_rooms.json` 都先跑它。

`probe_walk.gd` 不依赖游戏进程，改完 `room_runtime.gd` / `prelude_room_draw.gd`
或 `prelude_rooms.json` 之后跑一次，比手点快得多；它对着的是"用户报过的两个 bug"：
镜头跟随时人物钉不钉在屏幕中心、站到道具旁边出不出提示。

`probe_maze.gd` 是**七色镜廊的总闸**：它直接实例化面板、读面板里那份题目数据，再调用面板自己的
`_trace()` / `_blue_is_s()` 真跑一遍光线，最后模拟"点 11 格摆出答案"。改 `panel_maze.gd` 必跑——
它抓到过"逻辑对但画面点不下去"（可放镜格写成了双奇坐标）和"预置镜只画不参与光路"这两类问题。

`import_assets.gd` / `preview_portraits.gd` 是**美术侧**的两个 headless 工具：
前者幂等地把 Kerry 给的图搬进 `assets/`（抠底、裁边、按三视图切主视图），
后者把八张立绘并排拼成对照图，一眼看"哪块被误抠成透明"。改了抠图规则就跑这两个。

`probe_resume.gd` 同理，但它跑的是**整幕**：一路点到第一段走位 → 记下"走位里看了什么"
→ 重建对话场景（= 玩家点完「看完了」切回来）→ 检查恢复点 → 继续点到下一段走位……
改完 `_start_free()` / `_restore_after_walk()` / `_skip_consumed_rows()`，
或者剧本里挪动了 `["room"]` + `["free"]` 的位置，一定要跑。

**渲染问题必须用 `--rendering-driver opengl3` 验证，不能只看 `--headless`。**
headless 用的是 dummy 渲染器，会报出真实渲染器下不存在的 shader 假错。

---

## 二、目录结构

```
project.godot                     项目配置（1280x720、autoload、输入动作、msaa_2d）
icon.svg                          占位图标
李星.png / 刘忆.png               两张主角立绘（灰白手绘，真 PNG，不是 WebP）

assets/                           Kerry 给的素材（立绘是他自己抠好的；道具/封面由 tools/import_assets.gd 抠底裁边）
  cover/chase_the_star.png        封面（16:9，开场画面用）
  portraits/lixing.png            李星立绘（Kerry 自己抠的透明底成品）
  portraits/liuyi.png             刘忆立绘（同上）
  portraits/student_c.png         同学 C 立绘
  portraits/student_d.png         同学 D 立绘
  portraits/student_e.png         同学 E 立绘
  portraits/teacher.png           班主任立绘
  portraits/warden.png            宿管阿姨立绘
  props/pegboard.png              洞洞板（书桌面板的底衬）
  props/usb_drive.png             附录5 ⑧ 品红色 U 盘
  props/playing_cards.png         附录5 ⑨ 一盒花切牌
  props/book_zoo.png              动物园（九本书之一）
  props/branch.png                附录5 ⑪ 神秘树枝
  props/smiley_lamp.png           笑脸灯（书桌面板的台灯）
  props/alarm_clock.png           闹钟（暂时没用上）
  books/week1_spines.jpg          九本书脊（书架面板按 9 列等分）

data/
  prelude_dialogue.json           前日谈全部剧本（按幕分组：act1 / act2）
  week1_dialogue.json             一周目剧本（chapter = week1，六段）
  week2_dialogue.json             二周目剧本（chapter = week2，七段；附录6 的真相文本也在这里）
  prelude_rooms.json              五间俯视角房间的数据（几何 / 陈设 / 可查看物件）

scenes/prelude/
  prelude_1.tscn                  前日谈第一幕入口
  prelude_2.tscn                  前日谈第二幕入口
  prelude_walk.tscn               俯视角走位场景入口（由对话脚本切进来）

scenes/title/
  title.tscn                      **封面 = 游戏入口**（project.godot 的 main_scene）

scenes/week1/
  week1_1.tscn                    **一周目入口**（封面上点一下 / 空格进来）

scenes/week2/
  week2_1.tscn                    二周目入口（一周目演完自动切进来）

scripts/prelude/
  prelude_state.gd                autoload「PreludeState」：记录卡 / 旗标 / 已查看物件 / 回看流水(history)
  save_game.gd                    autoload「SaveGame」：自动存档（user://xunxing_save.json）+ 继续上次
  prelude_base.gd                 对话场景基类：装运行时、幕间黑幕、跳场景
  prelude_1.gd                    前日谈第一幕：5 个序列
  prelude_2.gd                    前日谈第二幕：2 个序列 + 收尾（按钮立 prelude_done 后回一周目收尾）
  week1_1.gd                      一周目：**新链**六关 → 前日谈；带 prelude_done 时只播 s6_ending 收尾 → 二周目
  week2_1.gd                      二周目：7 个序列，打完回标题页（bridge/结尾 CG 到位后改接 bridge）
  prelude_walk.gd                 走位场景宿主（把 room_id 推给 room_runtime）

scripts/week1/
  panel_base.gd                   小游戏面板基类（压暗层 + 面板框 + finished/close_panel）
  week1_panels.gd                 面板登记表（id → 脚本路径）
  panel_maze.gd                   …七个面板：镜面光路 / 手势密码 / 备忘录 / 书架 / 书桌 / 海龟汤 / 衣柜

scripts/week2/
  week2_panels.gd                 二周目的面板登记表（id → 脚本路径）
  panel_reason.gd                 推理问答（附录7 的五道题，一次一题）
  panel_alibi.gd                  不在场证明 + 动机勾选表（五人 × 有时间 / 有动机）
  panel_slant.gd                  具体图示①：寝室地面剖面（阳台高 / 门低、水往下流）
  panel_circle.gd                 具体图示②：地上的水（实际是圆 vs 地斜会流成一条）

scripts/ui/
  prelude_ui.gd                   UI 工具箱（class_name PreludeUI；含 load_texture() 兜底读图）
  dialogue_runtime.gd             GAL 对话运行时（脚本行解释器；立绘表 ART / 左右 SIDE 也在这里）
  title_screen.gd                 开场画面：铺封面 + 「点击 / 空格 开始」
  prelude_backdrop.gd             对话场景的手绘矢量背景（铅笔线稿风）
  room_runtime.gd                 俯视角走位运行时（移动 / 靠近 / 弹窗 / 返回）
  prelude_room_draw.gd            俯视角房间渲染器（灰阶实体，被 backdrop 调用）

shaders/
  portrait_frame.gdshader         立绘白纸剔除 + 边缘溶解

tools/
  check_gdscript.mjs              GDScript 静态自检
  validate_prelude.mjs            剧本校验
  import_assets.gd                素材入库（拷图 + 抠底 + 裁边，幂等，改了抠底规则要重跑）
  probe_week1.gd                  一周目端到端自检（209 项）
  probe_week2.gd                  二周目端到端自检（85 项，含章节链）
  probe_maze.gd                   七色镜廊自检（60 项）
  solve_maze.gd                   七色镜廊求解器（全枚举，应打印「解数 = 1」）
  probe_walk.gd                   走位自检（19 项）
  probe_resume.gd                 走位 → 对话 恢复自检（21 项）
  probe_collide.gd                家具碰撞自检（18 项）
  probe_portrait.gd               立绘抠图自检
  probe_soup.gd                   海龟汤自检（42 项：16 题点满 10 个解锁挑词 / 16 选 6 对错路径 / 连错 3 次给「看汤底」）
  probe_save.gd                   回看 / 自动存档 / 笔记 / 标题页自检（62 项；会真写档，但开跑前备份、结束时还原）
  probe_pause.gd                  暂停菜单 / 设置自检（73 项；会真写设置文件，同样备份 + 还原）
```

---

## 三、三条玩法流水线

### 0. 一周目（封面之后，六关）

入口 `scenes/week1/week1_1.tscn` → `scripts/prelude/week1_1.gd`
（继承 `prelude_base.gd`，六个序列）→ 剧本 `data/week1_dialogue.json`（chapter = `week1`）。
六个小游戏面板都在 `scripts/week1/`，从 `panel_base.gd` 继承，只覆盖
`panel_title()` / `panel_hint()` / `build_body(body)`；过关时调 `close_panel(result)`，
结果由运行时写进 `PreludeState` 的 `week1_result_<id>`。

**第 1 关「七色镜廊」**（`panel_maze.gd`，Kerry 的 DOCX + 手绘图改版）：
- 场地 9×7、格子 42px（这个数是被面板高度逼出来的，见文件头注释）；**能放镜的是"带圈的铅笔格"**＝棋盘格
  `(x+y)%2==0`，共 32 格；14 个黑框（一个框只放一块镜、框本身不挡光）；
- 七色各一对进出口（边框外一格，带 ▶/◀ 方向），要"每种颜色都接到自己的口子上"；
- 交互：点一下 ／、两下 ＼、三下拿空（`CYCLE`）；预置的黑镜动不了（提示"这块黑色的镜子是题目给的"）；
- **预置镜也真的参与反射**（`_trace()` 会把 `PRESETS` 合进镜子表）——不然玩家会觉得"这镜子是假的"；
- 判胜不只是"七色都亮"：还要 `_blue_is_s()`——把玩家摆出来的蓝色光路和答案光路逐格比，
  必须是那笔标准 S（三横落在 y=1/3/5）。差一点时状态行会说「七色都接上了——可蓝色那道光还没走出那笔 S。」
- **UI 可读性（Kerry 反馈"哪里能摆镜子指示不清楚"之后改的）**：每个能放镜的格子画一个淡圆环、
  鼠标悬停时那一格连同它的**黑框**一起高亮并显示一个半透明的"ghost 镜"；状态行第一句直接写
  「点带圈的铅笔格放镜子：一下 ／、两下 ＼、三下拿空」；没接上的口子压到 45% 亮度、接上的全亮。
- 【坑】`_draw_mirror()` 画斜度时屏幕 y 向下：**／ 是 `Vector2(k, -k)`、＼ 是 `Vector2(k, k)`**。
  一开始写反了，逻辑全对但每面镜子都反着画，看起来就是"光没按镜子反射"（Kerry 一眼看出：
  「你这光路不对啊，都不遵循反射定律」）。

对话运行时为它加了两种行：`["goal", 物件名]`（走位只要求走到这件东西跟前）和
`["panel", 面板id]`（弹出小游戏，开着的时候 `_on_advance()` 不推进）。

六个小游戏的内容（2026-01 按 Kerry 的两份新文档改过）：
①`panel_maze.gd` 七色光线反射镜（黑框/铅笔格/点一下 `/`、再点 `\`、第三下拿掉；蓝光那条路是 S）；
②`panel_gesture.gd` 九点手势，按 S 点亮；背景那层蓝色是**手机壁纸**——壁纸上按 S 铺着上一关那道蓝光
（文档要求的"壁纸 = 蓝色光路"，等于把答案画在手机上了）；
③`panel_memo.gd` 五个**罗马数字** `XV VI XXI VI IXX` → 15/6/21/6/19 → 减密钥 5 → `JAPAN`（原来的 `OFUFS` 已删）；
④`panel_bookshelf.gd` 九本推理小说：**书脊上没有数字**，六本日本作者的书要一本一本翻开，
详情页里的借阅卡数字按书架顺序读出来就是 `053714`（书脊图见 `assets/books/week1_spines.jpg`）；
⑤`panel_desk.gd` 书桌找不同；⑥`panel_soup.gd` 海龟汤 + 衣柜 `panel_wardrobe.gd`。

**第 5 关海龟汤**（`panel_soup.gd`）：面板进来直接就是 16 道预设问题（乱序），
玩家点问题看答录，**问满 `QUESTION_GATE` = 10 个问题才解锁挑词**；
挑 **`PICK_COUNT` = 6 个词**（衣柜 · 憋笑 · 室友 · 捉迷藏 · 赢 · 开心）才算过关；
挑错可以回去接着问（答录与已问记录一行不丢，`_asked_count` 已经 ≥ 10 所以挑词立刻还在），
连续挑错 3 次才会多出一个出口按钮 `SoupGiveUp`「不想了，直接看汤底」（结果里带 `given_up`）。
**2026-01 Kerry 拍板砍掉了原来的"自己打字问"那条大模型路径**（原因：发行时不能把自己的 API key
打进包里给玩家用，会被扒出来盗刷，还得替每个玩家的每一次提问付钱）；
代码连同 `llm_client.gd` / `write_llm_config.gd` 一起归档到了 `_archive/llm/`（带 `.gdignore`，Godot 不扫描）。
**不要往回接**：真要接大模型，得先解决 key 的归属（自己的中转服务，或干脆不做）。

三处走位都在寝室 `dorm_room`（书架 / 室友的书桌 / 衣柜）。**顺序必须是
`["room"]` → `["goal"]` → `["peek"]` → `["free"]`**：`["peek"]` 是注册行，
写在 `["free"]` 后面的话，进走位时 `_peeks` 里还没有这个名字，回来就没有追加台词（见坑 25）。
同一间房被用三次，所以 `_start_free()` 的 done_key 是 `walk_done_<房间>_<段>_<行>`。

打完一周目六关 → `_on_chapter_end()` → 幕间「第一天 结束   ·   点击 / 空格  进入前日谈」
→ 切到**前日谈第一幕**（`prelude_1.tscn`）。前日谈演完回到这一幕时只播收尾 `s6_ending`，
由它自己接**二周目** `scenes/week2/week2_1.tscn`（`next_scene_after_chapter()` 按 `prelude_done` 二选一）。

附录5 的 11 件氛围道具已全部落地（①小纸片 ②吧唧 ③jajo可乐 ⑥杯垫 ⑦神秘的书 ⑩马克杯在寝室房间的
`items[]` 里；④破损眼镜 ⑤爱心摆件 ⑪神秘树枝是 `panel_desk.gd` 的普通热区；⑧品红色 U 盘 ⑨花切牌在
`panel_soup.gd` 的 `AMBIENT` 常量里，点开给一段描述）。要给房间加彩蛋就往 `items[]` 里加一条 8 元组，
`detail` 支持 BBCode（`[i][color=#6d6a72]…[/color][/i]` 用来做"模糊化"的那一小段）。

### 0b. 二周目（接在前日谈与第一天收尾之后，七段）

入口 `scenes/week2/week2_1.tscn` → `scripts/prelude/week2_1.gd`，剧本 `data/week2_dialogue.json`
（chapter = `week2`）。**进入二周目不 reset**：一周目攒下的笔记要带过来，玩家才有"我查过一遍"的连续性；
真正清存档的是前日谈结尾那个按钮（清掉之后回一周目开场）。

七段与文档的对应关系（`chapter_sequences()` 必须与 json 的键完全一致）：

| 段 | 内容 | 用到的面板 / 房间 |
|---|---|---|
| `s0_scene` | 自白「B 不可能自杀」→ 回寝室看现场（七件东西看全才放行） | 房间 `dorm_after` |
| `s1_method` | 自白「这是人造的密室」+ 一周目马克杯的回忆 → 推理问答 | `panel_slant`（剖面图）+ `panel_reason`（附录7） |
| `s2_motive` | 找动机 | 附录8 的文本 |
| `s3_classroom` | 教室走访 C / D / E / 班主任 / 宿管阿姨 | 背景 `classroom`（附录9） |
| `s4_alibi` | 不在场证明与动机的勾选表 | `panel_alibi` |
| `s5_cup` | 打翻马克杯 → 水摊成圆形 → 地板不是斜的 | `panel_circle`（水迹对比图） |
| `s6_truth` | 明白不是他杀 → 情感寻星（附录6） | — |

新房间 `dorm_after`（加在 `data/prelude_rooms.json`）：复用寝室的几何与家具碰撞，可看物件是
药瓶 / 散落的药片 / 扫帚 / 马克杯 / 阳台门 / 阳台的栏杆 / 桌上摊着的照片；**它故意不写 `goal_item`**，
所以 `room_runtime._goal_item` 为空 → 「看完了」要求把这一间全部看完（见 `room_runtime.gd:758`）。

二周目的小游戏和一周目一样继承 `panel_base.gd`，只是登记表换成 `scripts/week2/week2_panels.gd`，
运行时 `_open_panel()` 先查 `week1_panels.gd`、再查 `week2_panels.gd`。

`panel_alibi.gd` 的判定表有个**必须守住的约束**：结论是「有时间的没动机，有动机的没时间」，
所以 `PEOPLE` 里**不能有人同时 time=true + motive=true**。C 与 E 的动向里都写明了证人
（同学作证 / 社长作证）→ 两人都是 `time=false`；D、班主任没动机 → `time=true`；
宿管阿姨在教工食堂被班主任看见 → `time=false, motive=true`。
另外 `panel_hint()` **不能写结论**（原稿直接把「有时间的没动机，有动机的没时间」挂在面板底部，
等于开面板就报答案），现在写的是「先看他们的动向：谁真的抽得出时间，谁又把刘忆当成了威胁」。

打完二周目 → 幕间「第二天 结束   ·   点击 / 空格  回到标题」→ 切回封面 `scenes/title/title.tscn`
（前日谈**没演过**的老存档仍然送 `prelude_1.tscn`，见坑 58；bridge / 结局 CG 到位后出口改成接 bridge）。

### 1. GAL 对话（已跑通）

`dialogue_runtime.gd` 逐行解释 `data/prelude_dialogue.json` 里的脚本行。

| 行类型 | 含义 |
|---|---|
| `["n", 文本]` | 旁白 |
| `["d", 说话人, 文本]` | 对白 |
| `["m", 文本]` | 李星内心独白 |
| `["card", 文本]` | 记录卡（点掉后继续，同时进笔记页） |
| `["title", 大标题, 副标题]` | 标题卡 |
| `["space", 背景键, 立绘数组]` | 切场景、清空立绘与热区 |
| `["who", 立绘键]` | 切说话人（其他人变暗） |
| `["show"/"hide", 立绘键]` | 显示 / 隐藏立绘 |
| `["item", 名称, 详情, [x,y,w,h]]` | 氛围物品热区（就地调查模式，走位模式下不用） |
| `["peek", 物品名, [追加行]]` | 看过某物品后插入的追加台词 |
| `["room", 房间id]` | **声明这一段进哪间可走房间**（物件清单只在 prelude_rooms.json 里维护） |
| `["free"]` | 停下来等玩家走完这间房（有 room 就切走位场景，没有才走就地调查） |
| `["choice", 提示, [选项…], [分支…]]` | 选项（分支行内联插入继续执行） |

### 2. 俯视角走位 + 弹窗放大（本次新增）

对话播到 `["room", id]` + `["free"]` 时切到 `prelude_walk.tscn`：

1. `dialogue_runtime._start_free()` 写入一串旗标
   （`walk_room` / `walk_chapter` / `walk_resume_seq` / `walk_resume_row` /
   `walk_resume_peeks` / `walk_resume_active`）然后 `change_scene_to_file`。
2. `prelude_walk.gd` 读 `walk_room`，在 `add_child` **之前**
   `rt.call("configure", room_id)`，再交给 `room_runtime.gd`。
3. `room_runtime` 读 `data/prelude_rooms.json` 建地板 / 陈设 / 可查看物件，
   用 WASD 走动（`WALK_SPEED = 250`，判定点是**脚下**那个点），走到物件
   `reach × 0.8` 范围内提示条浮出，空格或点击 → 弹窗放大细节。
   房间比屏幕宽时镜头横向跟随：**人物恒在屏幕中心、场景严格 1:1 移动**
   （别做成"人物在屏幕上滑、场景不动"，那样看着就是人物比场景快一倍）。
4. 物件全部看完 → 「看完了」→ 按 `walk_chapter` 切回 `prelude_1.tscn` /
   `prelude_2.tscn`；`_restore_after_walk()` 用 `walk_resume_*` 回到刚才那一行，
   并把走位里看过的物件的 `["peek", …]` 追加台词补播。

**三间房**：`corridor_end`（教学楼·六楼走廊尽头）、`library`（图书馆·借还书台）、
`dorm_corridor`（女生寝室·六楼走廊）。

`data/prelude_rooms.json` 里每个物件是一条 8 元组：
`[x, y, w, h, reach, 名称, 详情, closeup贴图路径]`。
`reach` 的语义：**从脚下到物件矩形的距离**上限，实际触发值是 `reach × 0.8`
（145~160 → 116~128px，大约一个身位），所以是"走到旁边就看得见"，
不需要叠在物件上。已经亮着的那一个再乘 1.18 迟滞，边界上来回走不会闪。
**名称与详情必须和 `prelude_dialogue.json` 里的 `["item"/"peek", …]` 逐字一致**，
peek 的追加台词靠"名字相同"对接。

---

## 四、美术：代码绘制 → 贴图的双轨

现在场景、房间、面板仍以**代码绘制**为主（`prelude_backdrop.gd` + `prelude_room_draw.gd` +
各面板自己画），但 Kerry 已经给了第一批真素材，它们走的是**"有贴图就用贴图、没有就退回代码绘制"**
的双轨（书脊、面板道具、开场封面、立绘都是这样）。

**已经接上的真素材**（都在 `assets/`；立绘是 Kerry 自己抠的，其余由 `tools/import_assets.gd` 生成）：
- 封面 `assets/cover/chase_the_star.png` → 开场画面 `scenes/title/title.tscn`
- 七张立绘 `assets/portraits/{lixing,liuyi,student_c,student_d,student_e,teacher,warden}.png` →
  登记在 `dialogue_runtime.gd` 的 `const ART` / `const SIDE` 里，说话就带立绘（左右交替站位）；
  没登记的角色**不会**再生成占位水印（`_spawn_portrait()` 里那道 `if not ART.has(who): return`）
- 九本书脊 `assets/books/week1_spines.jpg` → 书架面板按 9 列等分（`AtlasTexture`）
- 道具 `assets/props/*.png` → 书桌面板（洞洞板 / 笑脸灯 / 树枝）、海龟汤面板（U 盘 / 花切牌）

**读图统一走 `PreludeUI.load_texture(path)`**：先 `ResourceLoader`，失败再 `Image.load_from_file`
兜底。从外面拷进来的图**没有 `.import`**，只写前者的话，从源码跑起来这些图会"看不见"、
而在编辑器里又一切正常（坑 29、34）。反过来也要小心：**同一个文件被替换过、却留着旧的 `.import`**
时，`ResourceLoader` 会拿到**旧缓存**（坑 35）。

**立绘是带透明底的成品**（Kerry 自己抠的，四角 a=0）：运行时的 `build_bg_mask()` 只按
**alpha 的连通性 / 面积**判断"哪块是背景"，**不看亮度**（原因见 shader 文件头：白衬衫、脸、
眼镜反光的亮度和纸一模一样，按亮度切必然破洞）。
`tools/import_assets.gd` 里那套白底抠图规则仍然留着，但现在只服务**道具图与封面**（坑 36）。

**正在说话的人更"实"**：`Portrait.set_dim(dimmed)` 现在同时设两个 uniform —— 听众
`dim=0.60 / focus=0`，说话人 `dim=0 / focus=1`。`focus=1` 表示"不吃边缘溶解、只吃一点点
纸张软过渡，再提一点亮度"（`shaders/portrait_frame.gdshader` 的 `focus`），
这样一屋子里站着几个人时，说话的那位最实、最亮。

下面这些还是占位，代码已经按**"有贴图就用贴图、没有就退占位"**写好，出图之后**一行代码都不用改**：

| 路径 | 用途 | 规格 |
|---|---|---|
| `assets/sprites/lixing.png` | 李星俯视角行走小人 | 256×256，透明底，脚点在下沿正中 |
| `assets/sprites/liuyi.png` | 刘忆俯视角行走小人 | 同上 |
| `assets/closeups/*.png` | 各物件的放大图（弹窗用） | 约 640×300 |
| `assets/rooms/*.png` | 整间房的底图（可选） | 2400×720 |

画风要求：与 `李星.png` / `刘忆.png` 统一 —— 灰白手绘、深色中粗线、灰调块面、
无高饱和色。详见 `assets/README.md`。

---

## 五、踩过的坑（别踩回去）

1. **`set_anchors_preset()` 只改 anchor、不动 offset**，而且在 `_init()` 里调用时
   节点还没进树、父级尺寸按 0 算 → 控件会变成 0×0（连全屏推进按钮都会变 0，
   鼠标点击永远没反应）。一律用
   `set_anchors_and_offsets_preset(preset, PRESET_MODE_MINSIZE, 0)`，
   或者**先 `add_child` 再设**。自己写死 offset 的控件必须先设 preset 再赋 offset。
2. **`set_anchors_and_offsets_preset` 不写接收者 = 作用在 `self`**。
   我写过裸调用 `set_anchors_and_offsets_preset(PRESET_TOP_WIDE)`，
   结果把运行时自己改成了 TOP_WIDE，面板反而没布局（弹窗挤成一条竖条）。
3. **`anchor_top = 0.0` 这种属性赋值无效**，必须用 `set_anchor(SIDE_TOP, 0.0)`。
4. **节点名不能叫 `NameLabel` / `Text`**，会和 Control 内建属性冲突，
   Godot 会改名成 `@NameLabel@N`，`get_node("NameLabel")` 就找不到了。
   现在用 `SpeakerLabel` / `BodyText`。
5. **`var x := null` 会报类型推断错误**，必须写 `var x: Node = null`。
6. **`sin()` / `abs()` 推断不出类型**（float 与 double 混算），
   凡是 `var a := 0.3 + 0.3 * abs(sin(t))` 都要显式写 `var a: float = ...`。
7. **凹四边形会让 `draw_colored_polygon` 三角化失败**（刷屏
   `Invalid polygon data, triangulation failed.`）。
   判断方法：四个点的叉积符号翻转就是凹的。几何体一律优先用三角形。
8. **`draw_set_transform` 在这个项目里不要用**（对 `draw_rect` 生效、对
   `draw_polyline` / `draw_colored_polygon` 失效，会出现"边框缩放了、内容没缩放"
   的诡异错位）。缩放平移统一用 `draw_set_transform_matrix`。
   **但"画完复位成 `Transform2D.IDENTITY`"只在整帧画完时才对**：
   房间是靠 `draw_room()` 开头一次 `draw_set_transform_matrix(xform(win))` 统一的，
   你在人物 / 光斑这种**绘制中途**复位，就等于把后面所有东西踢回 1:1 屏幕坐标
   ——踩过一次，见第 20 条。子函数里干脆别碰它（椭圆用 `_draw_ellipse` 多边形画）。
9. **shader 里不要写带 `sampler2D` 参数的辅助函数**，会报
   `Condition "!actions.custom_samplers.has(...)" is true.`；
   `TEXTURE` / `TEXTURE_PIXEL_SIZE` 只在 `fragment()` 作用域可见。
10. **立绘抠图绝对不要"按亮度"判断哪块是纸**（Kerry 报的"角色内部的白色也被扣了"）：
	这两张立绘的**白色连帽衫和整张脸** luma 就是 0.90~1.00，跟白纸根本分不开。
	实测旧做法（剪影内"透明或很亮(luma≥0.80)"都算纸 + 从四边 BFS）会抠掉
	39,417 px 不透明像素（整件白衣服），shader 里那条 `interior_cut = 0.985`
	再削掉 24,045 px（脸直接没了，占人物内部 13.8%）。
	现在的判据只有**连通性 / 面积**（`scripts/ui/prelude_ui.gd` 的 `build_bg_mask()`）：
	  · 透明的像素 → 背景；
	  · 不透明但面积 < 0.3% 的孤岛 → 背景残渣（画面里漂的小点、纸屑）；
	  · 其余不透明像素 = 人物本体 → shader 里**原样保留** `a = c.a`，不再削。
	回归判据：`tools/probe_portrait.gd` 必须报"人物本体被抠掉 0 px"
	（它会打印数值并输出 `_cut_*.png` 对照图：红 = 本体被误抠）。
	另外立绘必须带 alpha 通道（背景透明）——本项目的两张都是四角 a=0。
11. **`--script` 跑的 SceneTree 脚本里 `current_scene` 是 null**，
	必须自己 `instantiate()` + `add_child()` 并保存根节点；
	也拿不到 autoload 的全局类名（`PreludeState` 要按节点找）。
12. **自定义 SceneTree 脚本若解析失败就不会调 `quit()`，进程永久挂住**，
	一律加 `--quit-after` 兜底。
13. **`Input.action_press(a)` 与 `Input.action_release(a)` 在同一次脚本迭代里
	会互相抵消**，`_unhandled_input` 读不到。要"造一次按键"就用
	`InputEventAction.new()` + `Input.parse_input_event(ev)`。
14. **一次按键会同时触发"收起弹窗"和"打开弹窗"两条分支**：
	`_close_popup()` 之后同一次 `_unhandled_input` 会继续往下跑。
	修法是加输入冷却（`room_runtime.gd` 的 `_act_lock = 0.22`）。
15. **照相机取景的 clamp 范围要和"内容盒"分开**：
	`_geom_rect()` 为了铺底色故意向左右各外扩了 2400，
	拿它做镜头 clamp 会让镜头停在房间外、左边露一条底色黑带。
	镜头用 `_cam_rect()`（真正的房间横向范围）。
	（`_geom_rect()` 已经没有调用者了，已删；见第 21 条的新取景规则。）
16. **整间房必须靠一次 `draw_set_transform_matrix(xform(win))` 缩放到屏幕**。
	忘了设就变成 1:1 绘制，2400 宽的走廊只有屏幕左边四分之一可见。
17. **可交互物件的 y 必须落在可走地板带里**，否则脚点永远够不着，
	表现为"走到物件正下方也显示太远"。（判定距离本身怎么算，见第 22 条。）
18. **超宽水平渐变不要用 `GradientTexture2D`**（拉到 2400 宽会失控、整面墙发白），
	横向渐变一律手写色带。
19. **`res://assets/**` 是可选路径**，`check_gdscript.mjs` 对它的缺失跳过检查
	（代码按"有则用、无则退占位"写）。
20. **人物 / 光斑曾经是在屏幕坐标里画的**（Kerry 报的"人物走到边缘后比场景快得多"）：
	`_draw_person()` 画影子时用 `draw_set_transform_matrix(压扁矩阵)`、`_draw_light_pool()`
	同理，画完都复位成 `Transform2D.IDENTITY`。房间是靠 `draw_room()` 开头那一次
	`draw_set_transform_matrix(xform(win))` 统一缩放的，这两处一复位，
	**它之后的东西——人物、近端压暗、两端渐隐、四角压暗、光斑——全部退回 1:1 屏幕坐标**：
	镜头跟随时场景在动、人物却按"逻辑坐标"原地画，看起来就是人物乱飘、速度是场景的两倍。
	修法：子函数里不要碰变换矩阵，影子/光斑用带缩放参数的多边形画
	（`_draw_ellipse(ci, 中心, 半轴x, 半轴y, 色)`，自己算椭圆点集；
	`_draw_person()` 现在就是用两次 `_draw_ellipse(foot, sw*1.05, sw*1.05*0.40, …)`
	画影子，`_draw_light_pool()` 同理）。
	回归判据就是这个 bug：`tools/probe_walk.gd` 断言"走遍整条可走带，
	人物屏幕 x 恒等于屏幕中心"（现在最大偏差 0.00px）。
21. **镜头 clamp 必须在两端各外扩 `view_w * 0.5`**。原来是
	`off_x = clampf(_player.x - view_w*0.5, cam.position.x, cam.end.x - view_w)`：
	房间两端各有约 514px 的区间 clamp 生效、镜头被钉死，人物只好在屏幕上滑行
	——"人物比场景快"的另一半原因（走廊起点 x=400 正好落在这个死区里）。
	现在两端各加一个 `pad`，对可走带内的每个 x 都不再触发 clamp，
	人物恒在屏幕中心、场景严格 1:1；越界露出来的部分靠
	`_lateral_extend()` 多铺地面（**必须是整格 96 的整数倍**，否则砖缝错位）
	+ `_draw_end_fade()` 渐隐到黑收边（替代了 `_draw_vignette()` 里那两条 260px 硬黑边）。
22. **"靠近"要从脚下量到物件矩形，不是量到物件中心**。旧 `_update_near()` 的判定点写的是
	`_player + Vector2(0, PLAYER_BODY_R * 1.2)`（往下探 57.6px），可绘制层就是把
	`_player` 当**脚点**画的，等于身位算了两遍；距离又量到中心，280px 宽的门牌
	站在正下方反而更远 → 表现为"走到旁边不给交互"。现在：
	`foot = _player`；`_distance_to_rect(foot, d)`（点在矩形内为 0）；
	`dist <= reach * NEAR_FACTOR(0.8)`；已经亮着的那一个乘 `NEAR_HYST(1.18)` 迟滞，
	免得边界上来回走时提示闪。走廊 reach 145~160 → 116~128px，约一个身位。
	另外**地面家具（`_solids`）会挡路**，交互物件不挡（"走廊地面（水渍）"这类要能踩上去），
	移动走 `_try_move()`（整步 → 只走 x → 只走 y → 停住）。
23. **从走位切回对话时，要先把序列指针"静默快进"到走位时那一段**（Kerry 报的
	"看完三栏笔记 → 看完了 → 再按空格直接回到最开头"）。`_begin()` 发现自己在恢复走位时
	调的是 `_next_sequence(false)`，指针停在**序列 0**；而 `_restore_after_walk()` 里原来那句
	`if seq_i != _seq_index: return` 会把恢复直接放弃 → 玩家被扔回序列 0 →
	再按一下空格就重播「前日谈」标题卡。
	走廊尽头那次走位刚好在第 0 段（`s0_open`），所以一直没有露馅；图书馆那次在
	`s3_montage`（第 3 段）才炸出来。修法：`while _seq_index < seq_i: _next_sequence(false)`
	（**不播任何行**，所以玩家看不出中间被跳过），然后还原 `_peeks`（`walk_resume_peeks`
	快照）、把身后那行 `["free"]` 置空、再把追加台词插在**恢复点**上（`_queue_peek` 插的就是
	当前 `_row_index`；插在 `peek_at` 会先吞掉第一条追加台词，还会让旧 `["free"]` 复活）。
	回归判据：`tools/probe_resume.gd` 必须 21 项全绿（把这句话加回去会红 3 项，实测过）。
24. **`sequence_finished` 信号以前根本没人接**——运行时在"序列播完"时会
	`sequence_finished.emit(chapter_id)`，可全工程一个 `connect` 都没有，
	于是子类覆盖的 `_on_chapter_end()`（幕间转场 / 结局按钮）永远跑不到：
	玩家按到最后只看到对话框里一句「（本章已结束。）」就卡住。
	现在 `prelude_base.gd` 在 `add_child(runtime)` 之后接上，而且**必须经过一层转发**：
	信号带一个 `sequence_id` 实参，直接 `connect(..., Callable(self, "_on_chapter_end"))`
	（0 参数）会在运行时刷屏报
	`Error calling from signal 'sequence_finished' ... Method expected 0 argument(s), but called with 1.`
	（`_on_sequence_finished(_sequence_id)` → `_on_chapter_end()`）。
	这条也是在写 `tools/probe_week1.gd` 时才炸出来的。
25. **`["peek", 物件名, [行…]]` 是"注册行"，必须写在 `["free"]` 之前**。
	写在后面时：进走位那一刻 `_peeks` 里还没有这个名字，`walk_resume_peeks` 快照自然也没有，
	回来就没有追加台词可插；更糟的是那行注册会在回来之后被当普通行执行掉
	（玩家感觉"少播了一句"）。正确顺序：`["room", …]` → `["goal", …]` → `["peek", …]` → `["free"]`。
	判据：`probe_week1.gd` 的三条"接着播的正是「X」的追加台词"。
26. **一周目面板里踩到的两个运行时坑**：
	① `RichTextLabel` 在 4.7 **没有 `set_v_scroll()`**（静态校验查不出，运行时报
	`Method not found: RichTextLabel::set_v_scroll`）——要滚到底得
	`get_v_scroll_bar().call_deferred("set_value", bar.max_value)`；
	② `PreludeUI.apply_button_skin()` 的形参类型是 `Button`，把 `LineEdit` 传进去直接编译失败
	（`argument 1 should be "Button" but is "LineEdit"`）——输入框要自己套 `StyleBoxFlat`。
	另外：**在 `--script` 环境里不要用 `class_name` 引用新类**（`.godot/global_script_class_cache.cfg` 是旧的，
	会报 `Identifier "Week1Panels" not declared in the current scope`），用 `preload("res://…")` 常量代替。
27. **`["space", 背景键, …]` 里的"背景键"和 `["room", 房间id]` 里的"房间 id"是两个命名空间**。
	`prelude_backdrop.gd` 只认七个背景键（`hallway` / `classroom` / `montage` / `roofline` /
	`dorm_corridor` / `dorm_room` / `black`）；写成房间 id（我在二周目里写过
	`["space", "dorm_after", []]`）**不报错**，只是背景悄悄退化成默认色——最难查的那类 bug。
	二周目要"同一间寝室"就直接用 `dorm_room`（房间里发生什么由 `["room", …]` 决定）。
28. **`_spawn_portrait()` 会给没有立绘的说话人生成一块占位水印**。立绘表 `ART` 里只有
	`李星` / `刘忆`（`dialogue_runtime.gd:50-53`），但占位逻辑对任何名字都会画一块
	**写着名字的 64 号透明大字**并 `push_warning("未找到立绘贴图")`。二周目教室里
	C / D / E / 班主任 / 宿管阿姨五个人一起叠着画，糊成一团。
	现在遇到 `ART` 里没有的名字直接 `return`（只在对话框上显示名字、不高亮），
	一周目只用到李星 / 刘忆，行为没变。
29. **从外面直接拷进来的图片素材没有 `.import`，`ResourceLoader` 是"看不见"它的**。
	`assets/books/week1_spines.jpg` 就是这么放进来的（旁边没有 `.import`，也没被编辑器导入过），
	于是 `ResourceLoader.exists()` 返回 **false**、`load()` 也拿不到 —— 代码只好静默退回手绘版，
	表现为"美术明明放进去了，游戏里却是占位图"。两种解法：
	①在编辑器里打开一次项目让它导入（会生成 `.import` 与 `.godot/imported/*.ctex`）；
	②**不等编辑器**，运行期直接读原始文件：
	`Image.load_from_file("res://…jpg")` → `ImageTexture.create_from_image(img)`
	（工程是从源码跑的，运行期读 res:// 原始文件是允许的）。`panel_bookshelf.gd`
	的 `_load_spines_texture()` 现在是"先试 `ResourceLoader`，失败再走 `Image.load_from_file`"。
30. **面板里"能看见多少行"要按尺寸账算，别靠肉眼估**。`panel_bookshelf.gd` 改用 Kerry 的书脊图后，
	书架要 300px 高，右侧栏总共只有约 327px，扣掉密码框 118px，详情区可视高只剩约 137px（≈4 行）；
	原来那段 5 行的欢迎语就被**拦腰截断**（第 5 行只露出上半截，看着像渲染坏了）。
	修法不是加滚动条（滚动条本来就有），而是**把静置状态的文案压到 4 行以内**、
	顺手删掉密码框下面那行与面板 hint 重复的小字。
	教训：给面板加一行文案之前先算还剩几行；RichTextLabel 的滚动截断不会留"安全边距"。
31. **绝对定位的 Label 不要用 `make_text()` 的默认换行**。`panel_gesture.gd` 壁纸角上那行"壁纸"
	是直接 `position = …` 摆的（不在容器里，宽度为 0），而 `make_text()` 默认
	`autowrap_mode = AUTOWRAP_WORD_SMART` → 两个字被拆成两行、压到左上角那个点上。
	绝对定位的短标签要么 `autowrap_mode = TextServer.AUTOWRAP_OFF`，要么给 `custom_minimum_size`。
32. **桥接（`godot_command eval`）里绝不要跨场景切换连续驱动**。我在一个 eval 循环里连点
	`_on_advance()`，中途 `["room"]` 行把宿主场景 `change_scene_to_file` 掉了，循环继续访问旧节点 →
	`SCRIPT ERROR: Invalid access to property or key 'name' on a base object of type 'null instance'`；
	**挂了调试器时每次脚本错误都会变成 Debugger Break 并冻结游戏**（桥接随即超时，
	`godot_get_debug_output` 能一次倒出几十 MB 的 `Enter "help" for assistance.`）。
	要驱动多步就用 `tools/probe_*.gd`（headless），或在循环里每轮重新取
	`get_tree().current_scene` 并判 null / `has_method("_on_advance")` 再决定要不要继续点；
	实例一旦冻死只能 `godot_stop_project` → `godot_run_project`。
33. **"抠白底"不能按亮度一刀切**。`tools/import_assets.gd` 第一版把所有 `r,g,b > 0.90` 的像素
	抠成透明，结果人物**内部的**白（脸上高光、白衬衫、浅色袖口）也一起没了，
	深色背景上看就是"脸上破了个洞"。正确做法两条：
	· 本来就带透明背景的图（webp/png 立绘，四角 a=0）→ **原样保留，根本不抠**；
	· 整张不透明的 jpg → 从四边做**连通性 flood fill**，只吃"和边框连通的近白"，
	  人物内部的白不连通，留得住。
	同一批素材还有两个连带坑：
	· jpg 读进来是 **RGB8（没有 alpha 通道）**，此时写 alpha 会被直接丢掉（存出来四角仍是纯白），
	  必须先 `if not img.detect_alpha(): img.convert(Image.FORMAT_RGBA8)`；
	· 挂载给我们的素材文件**没有扩展名**，`Image.load_from_file()` 报
	  `Failed to load image. Error 15`，得自己嗅文件头（`FF D8 FF` = jpg / `RIFF….WEBP` / `89 50` = png）
	  再走 `load_jpg_from_buffer` / `load_webp_from_buffer` / `load_png_from_buffer`。
34. **`Image.set_data()` 是 5 个参数**（宽、高、mipmap、格式、字节）。
	写成 `img.set_data(bytes)` 会报 `Too few arguments for "set_data()" call. Expected at least 5`，
	正确写法 `img.set_data(w, h, false, Image.FORMAT_RGBA8, data)`。
	还有一个**容器里的 TextureRect 必须给宽度**的坑：`custom_minimum_size = Vector2(0, 96)` 配
	`size_flags_horizontal = SIZE_SHRINK_CENTER`，宽度会被收缩成 0 → 图完全看不见（只留下 96px 空白），
	要给成 `Vector2(340, 104)` 这种有宽度的值。
35. **替换素材后旧的 `.import` 会让 `ResourceLoader` 拿到旧图**。`assets/portraits/*.png` 在
	还是"没抠好的版本"时被编辑器导入过一次，那些 `.import` 一直留着；后来我用脚本
	**原地覆盖**了同名 png，`ResourceLoader.load()` 仍然返回旧的 `.ctex` 缓存
	（`load_texture()` 走的是第一条分支，根本轮不到 `Image.load_from_file` 兜底），
	表现就是"脚本改了、图也重新生成了，游戏里还是老样子"。
	解法：删掉那些 `.import`（`assets/{portraits,props,cover,books}/*.import`，保留 `icon.svg`
	与两张老立绘的），从源码跑时就会走 `Image.load_from_file` 读真实文件。
36. **灰白手绘立绘的"纸"和"人物身上的白"在亮度上完全分不开**（**这条现在只对道具/封面生效**：
	立绘已经改成 Kerry 自己抠好的透明底成品，不再走这套规则）。
	用 `tools/probe_lum.gd`（已删，需要时照 37 的思路重写）量过：纸是 **1.000（min 也是 1.000）**，
	而人物外套/袖子的受光面**也是 1.000**（区域均值 0.97~0.99）。
	所以"调低亮度阈值"这条路是死的 —— 阈值 0.78 会把袖子抠成半透明（实机就是"身上蒙了层灰雾"），
	阈值 0.95 又会顺着线稿的缺口漏进去，抠出来的 alpha 上是一条条黑带。
	`tools/import_assets.gd` 现在的做法（改之前请先读完）：
	· 亮度阈值只取"比纸低 **0.005**"（≈0.995），只吃真正的纸，**不用它去区分人物**；
	· 漏进来的细通道用**形态学闭运算**补掉（`_close_paper`：人物掩码先膨胀 3 次、再腐蚀 3 次，
	  比 6px 窄的漏光缝就没了，外轮廓不变）；
	· 紧贴背景、亮度 ≥0.93 的那一圈是 jpg 压出来的光晕，**啃掉 1px**；
	· 软边只对 ≥0.985 的像素做（人物那层 0.96~0.99 的受光面不能被削）。
	另外记住运行时的前提：`build_bg_mask()` 需要贴图**本来就带透明底**，它只按 alpha 的
	连通性/面积判背景；把一张白底 jpg 直接塞给 `Portrait` 是没用的。
37. **说话人 / 听众的区分是 shader 的两个 uniform，不是一个**。只设 `dim` 的话
	（听众 0.60、说话人 0）看起来仍然"两个人一样虚"——因为**边缘溶解 `dissolve`** 和
	纸张软过渡会把两个人的 alpha 都削一遍。要让说话人"实"，得同时给 `focus`：
	`set_dim(false)` → `dim=0 / focus=1`，`set_dim(true)` → `dim=0.60 / focus=0`。
38. **长详情页会把"答案"压到看不见的地方**（2026-01 修，Kerry 报「书架那关我一直过不了」）。
	第 3 关的翻书详情（书名 / 作者 / 简介 / 借阅卡）很长，而贴图版右栏的可视高度只有约 100px，
	**借阅卡上的那个数字写在正文最末**——玩家看到简介就以为翻完了，数字永远不露面，
	于是"逻辑没错但过不了"。修法：刚翻到的那张卡的数字固定显示在顶部一行
	（`_digit_label`「卡上数字：0」，与「已翻开 N / 9」同排，不占额外高度）；`_open_book()` 里
	顺手 `_scroll.scroll_vertical = 0`。**凡是"答案藏在滚动区末尾"的设计都要复查一遍。**
39. **三个带输入框的面板都要处理焦点与空提交**（同上一批修的，`panel_memo` / `panel_bookshelf` /
	`panel_wardrobe`）：`LineEdit` 不点一下就不拿焦点，玩家直接敲键盘毫无反应；而"空输入提交"
	原来是**静默 return**，画面上什么都不发生 —— 两件事叠起来就像卡死。现在面板一开就
	`call_deferred("grab_focus")`（衣柜是切到密码屏时），空提交给一句提示并重新聚焦。
	另：`HBoxContainer` 里 `make_text()` 造的 Label 必须关 `autowrap_mode`，否则「卡上数字：0」
	会被竖着排成一列、把旁边的滚动区挤成 0 高。
40. **同一侧站多个立绘会完全重叠，说话的人可能被挡在后面**（2026-01 修，Kerry 报的
	「人物在说话的时候把他放在最前面」）。`SIDE` 只分左右两档，教室里右侧一次站三个人，
	`Portrait.setup()` 原来给同侧的是同一组 offset → 后生成的把先生成的整个盖住。
	两处修：①`dialogue_runtime._show_speaker()` 里给说话人 `z_index = 1`（其余 0），
	只影响同一层的绘制顺序、不动布局；②`Portrait.setup(..., slot := 0)` +
	`_make_portrait()` 按"这一侧已经站了几个"算槽位：第 n 个往里错开 96px、身高减 34px。
	改完两条端到端探针都复跑过（week1 100/100、week2 70/70）。
41. **给立绘提 `z_index` 之后，它会盖住对话框和面板**（2026-01 修，Kerry 报「你的人物提的太前面了，
	对话框台词都盖住了！」）。坑 40 把说话人设成 `z_index = 1`，而对话框、面板原来都是 0 ——
	`z_index` 比的是**整棵树上的层级**，不是"同层之内"。现在层级是明确定死的（写在
	`dialogue_runtime.gd` 的注释里）：立绘层 `0`（说话人 `1`）< 对话框 `_dbox = 5` < 记录卡 `_card = 6`
	< 小游戏面板 `p.z_index = 7`（`_open_panel` 里设）< 标题卡 `9` < 幕间黑幕 / 幕间文字 `12 / 13`
	（`prelude_base.gd`）。**以后再往里插新层，先想清楚它该落在哪一档。**
42. **`ConfigFile` 读不了"开头带注释/带 BOM"的小配置文件**（2026-01，做海龟汤 `user://llm.cfg` 时踩的）：
	同一个文件，`ConfigFile.parse()` 有时报
	`parse error ... Expected value, got 'ERROR'`、有时 parse 成功但 `get_value()` 全是空。
	**凡是"给人用记事本改"的配置文件都不能赌他的编辑器**。海龟汤那条路已经砍了
	（`llm_client.gd` 归档在 `_archive/llm/`），但结论留着：`llm_client.load_config()` 当年是自己按行解析的——
	跳过空行与 `#` / `;` 注释，取 `key=value`，引号可有可无，同时支持 `key = "value"` 这种松散写法；
	游戏自己的 `game_settings.gd` 读写 `user://xunxing_settings.cfg` 用的是同一套手写解析（配合坑 56）。
43. **自动存档会把"跑探针"当成"玩家在玩"，一跑就把真存档冲掉**（2026-01，加 `SaveGame` 时想到的）：
	探针是 `godot --headless --script tools/xxx.gd` 起的，**`get_tree().current_scene` 是 null**
	（场景是探针自己 `add_child` 上去的），所以 `SaveGame.write()` 必须在 `scene_path == ""` 时**直接返回不写盘**。
	同理 `disabled` 开关、以及"章节对不上的续播不能消耗待领状态"（`take_resume()` 每段都会来问一次，
	一问就作废的话玩家真进到那一段反而续不上）。**以后再往存档里加东西，先想清楚探针会不会走到。**
44. **`JSON.parse_string()` 遇到坏档会往日志里刷一条 ERROR**（2026-01，`SaveGame.peek()`）：
	我们本来就把坏档当"没有存档"处理，玩家不该在日志里看到红色报错。
	改用 `var j := JSON.new()` + `j.parse(txt) != OK` 判断，失败静默返回空字典。
45. **`PanelContainer` 只设 `offset_*` 会被压成一条**（2026-01，回看面板打开后"只有表头、正文空白"）：
	锚点还是默认的左上角时，`offset_right = -170 / offset_bottom = -60` 算出的是负宽度，容器被压扁，
	里面的 `ScrollContainer` 自然一行都露不出来（画面上只剩标题行）。正确做法是先在 `_ready()` 里
	`set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)`，**再**设四个 offset；`PreludeUI.NotesPanel`
	与 `HistoryPanel` 都补了这一行。以后写全屏弹层照这个顺序来。
46. **书本关的数字不能印在借阅卡上**（2026-01，Kerry《好多错误》第 6 条 + 《几个小问题》第 2 条）：
	数字要让玩家从**书名/作者名的谐音**里发现（青崎有吾→5、岛田庄司→4、泡坂妻夫→7…），
	面板上只能留一句「想想上一关的答案」。加"卡上数字：X"那种提示等于把谜题送掉。
47. **手势密码的 S 与 2 是左右镜像**（2026-01，Kerry：「手势密码是s 不是2 反了」）：
	S = 上横 + **左上**竖 + 中横 + **右下**竖 + 下横；2 = 上横 + 右上竖 + 中横 + 左下竖 + 下横。
	`panel_gesture.gd` 的 `PATTERN` 用九宫格坐标写死（现在是 `(2,0)(1,0)(0,0)(0,1)(1,1)(2,1)(2,2)(1,2)(0,2)`），
	注释里贴了两种形状的 ASCII 对照 —— **不要"顺手翻转"回去**。
48. **把小图塞进小热区前先裁到本体**（2026-01，树枝"又小又竖"）：`branch.png` 是 400x1300 的大图，
	树枝本体只占 x 36..192、上下还有深色横杠；直接等比塞进 100x26 的热区，树枝只剩约 8px 宽。
	正确做法是按 `BRANCH_CROP` 裁掉多余部分，再用 `_sprite_rot()`（裁切 + 绕中心旋转）横过来摆。
49. **`--script` 模式下 `panel_gesture.gd` 编译不过**（2026-01，写行为探针时踩到）：
	它在 `_win()` 里直接用了自动加载标识符 `PreludeState`，`--script` 模式注册太早会报
	`Identifier not found: PreludeState`。要么按场景跑探针（`godot --headless <项目> res://tools/_tmp_xxx.tscn`），
	要么把那行改成 `get_node_or_null("/root/PreludeState")`。本次是**按场景跑**的。
50. **二周目的"密室现场"与真相是"文档缺失时自造"的**（2026-01，对照审计 e913279f 的 A5/F2）：
	`data/week2_dialogue.json:2` 的 `_readme` 自己写着"附录6 在原文档里缺失、由我代写"，
	但 `_docs\附录6.txt` 其实一直在。作者在《好多错误》第 12 条点名"二周目的密室现场部分几乎全错"。
	**2026-01 已整段重做**（见进度第 28 条）：药瓶/药片挪到**门口地上**（紧贴门缝）、
	补上可点击的**地板**与**朝里开的寝室门**、扫帚挪到**阳台栏杆旁**、
	真相改成"她自己锁门→把药盒碰翻在门口→去阳台拿扫帚时坠楼"（李星**没有**进屋，
	"是我把现场弄乱的"那段错误归因已删），水只往一边流的真因改成**阳台门开着、风吹的**。
	→ 这条留着的教训是：`dorm_after` 的物件集合一动，**必须同步 `probe_week2.gd` 的
	"十二件全看过"硬断言**（那时是七件）与 `probe_collide.gd` 的挡路块数。
51. **热区不要给玩家看见框**（2026-01，Kerry 原话「找不同的时候道具上面的框不要显示」）：
	`panel_desk.gd` 的 12 个热区原来 normal 就画一圈 1px 淡边、找过的换成 2px 暗红描边，
	整张桌子像贴了网格图。现在 normal 用 `StyleBoxEmpty`（全透明，只留鼠标手型 + tooltip），
	悬停才亮一层淡暖光；"已找到"只留一层 `alpha 0.13` 的暖色块、**不画轮廓**，
	"找过哪几处"交给右侧清单文字。→ 以后做热区默认按这个来：**框只出现在鼠标底下的那一瞬间**。
52. **别在 agent 改脚本的中途用实例加载那个脚本**（2026-01，实测）：
	`panel_maze.gd` 有一版把提示表写成 `const HINTS := PackedStringArray([...])` —— GDScript 里
	**不是常量表达式**，会报 `Parser Error: Assigned value for constant "HINTS" isn't a constant expression.`；
	更糟的是**已经跑着的实例**一旦加载到它会掉进 Debugger Break 循环，日志一口气刷到 **71MB**、
	实例完全没响应（`godot_get_debug_output` 读到的就是那份刷屏）。两条规矩：
	① 这类数组常量一律写 `const X := [...]`（普通 Array）或 `static var X := [...]`，
	**不要** `PackedStringArray([...])`；
	② 并行 agent 正在改某个脚本时，别拿交互实例去加载它 —— 先 `godot_validate_script`，0 错再开实例。
	真撞上了就 `godot_stop_project` 停掉自己起的托管实例（可以杀），然后重开。
53. **暂停菜单必须 `PROCESS_MODE_ALWAYS`**（2026-01，新加 Esc 菜单时踩到）：
	写成 `PROCESS_MODE_WHEN_PAUSED` 时，游戏**还没暂停**的那些帧里 `_input()` 根本不触发 →
	Esc 永远打不开菜单（现象是"按 Esc 没反应"，很容易怀疑按键映射写错）。
	只有 `ALWAYS` 才能同时做到"没暂停时收 Esc 打开菜单"和"暂停时按钮还点得动"。
	`tools/probe_pause.gd` 第 ⑧ 组专门断言了 `can_process()`，就是防这个。
54. **同侧立绘只错开 96px 等于没错开**（2026-01，Kerry：「右侧两个立绘重叠了」）：
	立绘宽 370~440px，同侧第二人至少推 **150px**；人多时还要按在场人数先压基准高
	（`_make_portrait(who, total)`：5 人 560 / 4 人 600 / 3 人 630，再每个 slot −40，最低 460）。
	另外记住：**说话人置顶是 `z_index`，对话框是 5、面板 7**（坑 40、41）。
55. **玩家可见文本里不许出现"周目""B""文档代号"**（2026-01，Kerry 第 3、7 条 + 《问题》第 3 条）：
	`B` 一律写「刘忆」、「一周目/二周目」一律写「第一天/第二天」，`_readme` 与注释里可以留内部 id。
	改完 grep 一遍 `周目|B 的|代写` 确认玩家看不到。
56. **坏配置行不许把玩家音量清零**（2026-01，`probe_pause.gd` 发现）：
	`volume = clampf(val.to_float(), 0, 1)` 遇到 `volume=abc` 会得 0.0 —— 静默静音。
	正确写法是 `if val.is_valid_float(): volume = ...`，坏行只忽略这一行、别影响后面的好值。
57. **改 `prelude_rooms.json` 的房间宽度/家具位置后，`probe_collide.gd` 会红**（2026-01）：
	它里面两条"撞上去停得住"的期望是**写死坐标**（"往上顶书桌 ≈396"起点 430、
	"往左顶衣柜 ≈376"）。把寝室 `floor_w` 2160→1440、家具重摆之后必须同步这两处，
	否则你会以为是碰撞逻辑坏了。同理 `probe_week2.gd` 里"案发现场物件够多"的清单也要跟着物件集合改。
58. **章节链改成"一周目 → 前日谈 → 一周目收尾 → 二周目 → 标题"后，别让二周目再接前日谈**（2026-01）：
	顺序由 `PreludeState` 里的 `"prelude_done"` 标志驱动（`week1_1.gd:25` / `prelude_2.gd:17` /
	`week2_1.gd:25` 各写了一遍，探针里也有两份——想单点化就把它挪进 `prelude_state.gd`）。
	`week1_1.chapter_sequences()` 按标志在"六关"与"只播 `s6_ending`"之间二选一，
	`next_scene_after_chapter()` 在 `prelude_1` 与 `week2` 之间二选一；
	`week2_1.next_scene_after_chapter()` **必须仍然把"前日谈没演过"的老存档送回 `prelude_1`** ——
	否则老档从二周目续上会走成「收尾 → 二周目 → 前日谈 → 收尾 → 二周目」的死循环。
	改链之后 `probe_week1` 从 100 项涨到 119 项、`probe_week2` 从 77 涨到 85 项（两条分支 + `prelude_2` 源码四查）。
59. **`_unhandled_input` 里"先切场景、后收事件"会冻住调试构建**（2026-01，Kerry：「玩完前日谈第一幕后，没进第二幕就结束了」）：
	`prelude_base.gd` 的幕间推进原是 `_gate_continue(_intermission_cb)` 之后紧接
	`get_viewport().set_input_as_handled()`。而 `_gate_continue()` 内部会
	`change_scene_to_file()` —— 这一下已经把本节点摘出场景树（Godot 4.7 实测：切完 `get_viewport()` 就是 `null`），
	于是下一行报 `Cannot call method 'set_input_as_handled' on a null value.`。
	**在 `-d` 调试构建里这条错会弹 Debugger Break 并把游戏冻在那里**，玩家的体验就是"第一幕一结束，游戏就没了"，
	同时 `godot.log` 一口气刷到几百 MB（我这边实测 160MB→328MB，`godot_get_debug_output` 也被它堵死）。
	正确顺序：先 `var vp := get_viewport()` → 判空 → `set_input_as_handled()` → **最后**再 `_gate_continue()`。
60. **`_ready()` 里不许直接 `change_scene_to_file()`**（2026-01，`prelude_walk.gd` 的兜底分支）：
	父节点正在挂子节点时切场景会报
	`Parent node is busy adding/removing children, remove_child() can't be called at this time.`，
	转场直接失败、卡在走位场景（玩家看到的就是"黑屏/空场景"）。
	写成 `get_tree().call_deferred("change_scene_to_file", PATH)` 延到帧末。
61. **「线索」光写进物品文案不够，画面上得有那个形状**（2026-01，Kerry 重提《问题》第 10 条）：
	第 4 关"笔记本上那个后来才画上去的红爱心"是第 5 关衣服颜色的线索，文案里一直写着"红笔的爱心"，
	可 `panel_desk.gd` 的现状页只画了一个 6×6 的红方块（看着像墨点，不像爱心），而桌上那个**红爱心摆件对照页也有**、
	根本不是"后来画上去的"那一笔。已把现状页的标记改成两颗圆瓣 + 一个尖的真爱心（只有现状页有，对照页没有）。
	教训：凡是"靠玩家一眼看出来"的线索（爱心、折痕、红笔标记、被折到背面的半张合照），
	画面里必须画出来，否则玩家会照文案去找、然后找不到；而且线索物要和**同时存在的相似物**区分开
	（红爱心摆件 vs 笔记本上的红爱心）。
62. **固定高度的容器 + 会自动换行的 Label = 文字画到隔壁去**（2026-01，Kerry：「摸衣服口袋那一段文字重叠了」）：
	衣柜第①屏原来是"四张按钮卡片一排"，卡片里那个 `AUTOWRAP_WORD_SMART` 的 Label 需要 **147px** 高，
	而容器 `ScreenHost` 固定 268px、内容最小高度 279px，VBox 压不动只能让内容溢出；
	于是每件衣服的描述文字都画到了隔壁那件衣服的名字上——**可见文字块两两求交 9 对重叠**。
	正确做法不是调行距，而是**不让文字参与排版**：整面柜子（含衣服名字）全部 `draw_*` 画在
	一张固定尺寸的子 Control 画布里（现在是 840×266），容器里一个 Label/Button 都不放。
	`tools/probe_week1.gd` 现在有 4 条几何断言守着这件事（可见文字两两求交 = 0 对、没有被挤爆的、
	第①屏没有参与排版的文字节点）；探针留了 `DSH_WARDROBE_SCRIPT=<脚本路径>` 对照钩子，
	把那 4 条套到旧版布局上**必须变红** —— 断言必须能失败，否则它只是摆设。

63. **设计稿写「此处可闪回一周目」时，一周目那一侧可能根本不存在**（2026-01，Kerry 让重看《附录2》《附录6》《二周目具体流程（详细版）》）：
	《附录6》与二周目第 6 关都要求「水只往一边流，真因是阳台门开着、风吹的」这条**一周目伏笔**，
	可是 grep 整份 `data/week1_dialogue.json`：**一周目里根本没有倒水 / 马克杯这一场**
	（只有 s0_maze 的窗帘、s1_phone 的阳台收衣服）。于是 `s5_cup` 的「我又想起那天的画面。窗帘一直在动」
	指的是一个不存在的画面，`s1_method` 的回忆卡同样是空指。
	补法是**回到一周目把伏笔演出来**（现在写在 `s4_soup` 结尾：手肘碰倒马克杯 → 水从桌沿淌到地上 →
	「水不往阳台那一头去，只往寝室门那一头去」，同一段交代阳台门开着、窗帘在动），
	再把二周目侧的字改成与它逐字呼应（`s5_cup` 改成「拿书时把马克杯带倒」，`s1_method` 回忆卡标题从「那时的桌面」改成「那天的地面」）。
	教训：跨周目的呼应要**两边都 grep 一次关键词**（水 / 马克杯 / 窗帘 / 阳台门），只改引用的一方等于把线索接在空气上。

64. **往章节表中间插新段，会让旧存档的段号错位**（2026-01，1089 回忆插进一周目第 5、6 关之间）：
	`SaveGame` 存的位置是 `chapter_id / scene_path / seq_index`（**数字下标**，见 `scripts/prelude/save_game.gd` 的
	`write()` / `read()` / `peek()`），不是段名字符串。所以 `scripts/prelude/week1_1.gd` 的 `DAY_ONE_SEQS`
	中间插一段之后，落在插入点之后的**老存档**续上时会跳到隔壁那一段（现在的表现是：第二天之前存的档
	从第 5、6 关续上会先播 1089 回忆）。影响很小、进度不丢，但要知道：
	**存档兼容性取决于段表的顺序，不是段名**。真要做兼容，就在存档里同时写段名（`seq_name`），
	读档时先按名字找下标、找不到再退回下标。

65. **弹窗"主视图"别写死画哪一件**（2026-01，Kerry：「围巾的主视图居然是衣服，改一下」）：
	`scripts/week1/panel_wardrobe.gd` 的 `_draw_coat_view()` 里原来是
	`var c := Color(0.62, 0.24, 0.26)` + 一句注释「主视图一律按红外套画（文档里被翻的就是它）」——
	于是**点围巾、点卫衣，弹出来的都是一件红外套**（点第三件才"碰巧"对）。
	现在颜色读 `cloth_color(_pick)`、形状读 `CLOTHES[i].pockets`：三件外套走 `_draw_jacket_view()`、
	围巾走 `_draw_scarf_view()`，并且**围巾不画口袋、`_pocket_at()` 也直接返回 -1**（画面上没有的东西，
	不该留一块看不见的命中区）。教训：凡是"点了第 N 个对象弹出来的详情"，画的内容必须由被点的下标驱动；
	只要看到详情函数里出现**字面量颜色 / 字面量坐标**，就该警惕它是不是写死了某一件。
	回归钩子：`probe_week1` 里新增的 7 条（颜色逐件对上 `CLOTHES`、围巾无口袋、点围巾标题不是外套、
	点第三件标题是红色外套且右侧那块仍是「右上袋」）。

---

## 六、已知占位与待办

- 立绘只有正面半身像，**没有表情差分**，所有情绪靠文字和场景调度表达。
  （2026-01：李星 / 刘忆 / 同学C / 同学D / 同学E / 班主任 / 宿管阿姨 七张都是 Kerry 自己抠好的透明底成品，
  放在 `assets/portraits/`，`import_assets.gd` 不再碰立绘。）
- 场景与俯视角房间**全部是代码手绘矢量**，没有位图素材（原因见第四节的说明）。
- 氛围物件的放大图是代码手绘的"占位框"（灰底 + 交叉对角线），不是成品美术。
- 走位小人同样是代码绘制的灰阶剪影（齐肩发 / 长直发 + 眼镜 区分两人），
  没有行走序列帧，只有轻微上下浮动。
- 对话时的立绘位置在左右两侧、无动作，属于静态 GAL 表现。
- 一周目六关的小游戏**全部是代码绘制的 UI 面板**（镜面光路、九点手势、备忘录、书架书脊、
  书桌热区、海龟汤问答、衣柜/密码盒），没有位图素材；谜题答案写在面板脚本里。
  - 第 3 关书脊已接入 Kerry 给的美术 `assets/books/week1_spines.jpg`：面板把整图平成九列切片显示，
	九本书的书名与作者就长在图里；**密码不由图上的数字给出**，靠书名/作者名里的谐音
	（青崎有吾→5、岛田庄司→4、泡坂妻夫→7…），面板上只留一句「想想上一关的答案」（见坑 46）。这张图**没有 `.import`**，`ResourceLoader.exists()` 看不见它，
	所以 `_load_spines_texture()` 会退回 `Image.load_from_file()` 直接读原始文件（见坑 29）；
	两道都失败才回退成代码手绘的书脊。
- 二周目的四个面板（推理问答 / 不在场证明表 / 两张「具体图示」）同样是代码绘制面板，题面与选项写在面板脚本里；
  附录6/7/8/9 **都已经拿到并落地**（`_docs\附录6.txt` 等）：现场与真相按附录6、五道题的题面/选项/答案按附录7、
  动机按附录8、走访与动向按附录9（见进度第 28 条）。改这一块时只改字符串、不要动行的类型与顺序。
- 二周目第 4 段「教室走访」现在是**对话场景**：切到 `classroom` 背景，按附录9 把同学 C / D / E、
  班主任、宿管阿姨的话逐条播出来（顺序固定）。文档写的是「切地图至教室，与同学交互对话」——
  想要**可以走动的教室、自己点人说话**，需要照 `dorm_after` 的样子再加一间 `classroom` 房间
  （五个同学做成 `items`），剧本里把这段换成 `["room"] → ["peek"] → ["free"]`。
- 一周目与二周目的台词都是自己按前日谈的笔调写的，**Kerry 可以随时替换
  `data/week1_dialogue.json` / `data/week2_dialogue.json` 的文本**
  （只改字符串，不要动行的类型和顺序；`["goal"]` 的物件名必须和 `prelude_rooms.json` 里逐字一致）。
- 前日谈只做到"待续"，Bridge、真结局还没做；现在的顺序是
  **第一天六关 → 前日谈（两幕）→ 第一天收尾 → 第二天 → 回标题页**（要重走整条链就用前日谈结尾的「回到开头」，它会连存档一起清）。
- **一周目第 1 关已换成"七色镜廊"**（Kerry 新给的文档 + 手绘图，2026-01 完成）：
  9×7 铅笔格 + **12 个不规则黑色大框**（一框最多一块镜，框不挡光）+ 七色各一进一出 + 题目预置 3 面黑镜；
  点一下 `/`、再点 `\`、第三下拿掉；`_frame_has_preset()` 把**预置镜所在的整个框焊死**
  （不封的话那一框里还能再塞一块，正是"解不唯一"的来路），其余框里只有答案位能放镜，同框重复会被拦。
  蓝光端口是 `in (9,1) L → out (-1,5) L`，折向 `["L>D","D>R","R>D","D>L"]`
  —— 与 `panel_gesture.gd` 那笔 S **同向、非镜像**（旧数据两个口都在左边界上，几何上根本摆不出 S）。
  判胜是**两条**：`_lit_count() == 7` **且** `_blue_is_s()`；七色都亮而形状不对时会明说
  「七色的口子都亮了，可题目要的形状还没出来——再顺一顺那几条光路。」（不再静默判错）。
  提示按钮四级（`HINTS`）逐级露出，**四级都不出现 "S"**、第一级也不说破是哪一路、看提示不动棋盘。
  12 面镜的数据是穷举搜索 + 独立复验出来的（`tools/solve_maze.gd` 全枚举 → **解数 = 1**），别手改 `SOL_MIRRORS`；
  面板给探针留了自检口 `blue_path()` / `blue_turns()`，收尾 `close_panel({"ok": true, "shape": "S", "blue_path": …})`。
  三处**照手绘意会、Kerry 可复核**的地方：①七个进出口的读法（现在绿光出光口在上边、橙光在下边、红光下进右出）；
  ②镜廊这条 S 是 21 格（上横 8 格），手势/壁纸那笔是 3×3 更"胖"，形状与折向一致、比例不同；
  ③12 个黑框的具体形状（画稿线条与格子边界不严格对齐）。要改任一条都得重跑求解器确认解数仍为 1。
  `panel_maze.gd` 顶部注释里记着 8 条坑（反射语义、`/` `\` 反射表别写反、面板根节点不能 `_draw` 等）。
- 回归探针都在 `tools/`（`probe_week1` / `probe_week2` / `probe_walk` / `probe_resume` /
  `probe_collide` / `probe_portrait`），它们不依赖游戏进程，改完对应文件跑一次即可。
