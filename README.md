# 《寻星》· Chase The Star

Godot 4 单机剧情解谜游戏。一周目（对话 + 六个解谜面板 + 三次俯视角走位 + 读心术回忆）→ 前日谈（两幕）→
一周目收尾 → 二周目（现场勘查 + 五个推理面板 + 走位）→ 回标题页。

> ⚠️ **这个仓库里有剧透。**
> `_docs/`、`大纲.txt`、`涌现·游戏剧情大纲（剧情顺序详细版）.txt`、`HANDOFF.md`、`progress.md`
> 里写着凶手、动机、各谜题答案和 1089 的原理。
> **仓库必须设为 Private**；如果以后要公开，先把这些文件从历史里摘出去（不是删掉就完事）。

---

## 一、先读什么

| 顺序 | 文件 | 里面有什么 |
|---|---|---|
| 1 | [`HANDOFF.md`](HANDOFF.md) | 交接主文档：怎么跑、目录结构、验证脚本、架构约定，**以及踩过的 65 个坑（改之前先扫一遍）** |
| 2 | [`progress.md`](progress.md) | 做过什么、现在到哪一步、45 条改动记录（含"为什么这么做"） |
| 3 | [`测试清单-内部策划.md`](测试清单-内部策划.md) | 十个回归探针的基线项数 + 六个谜题逐条验收标准 + bug 上报模板 |
| 4 | [`美术需求清单.md`](美术需求清单.md) | 还缺哪些美术资源（含 §8 待拍板的 7 条） |
| 5 | [`_docs/`](_docs) | 设计稿原件：剧情流程、解谜、附录 1–9、原始大纲 |

`测试清单-外部玩家.md` 是**无剧透版**，可以直接转发给测试玩家。

---

## 二、怎么跑

需要 **Godot 4.7.2**（官方 stable）。用编辑器打开本目录的 `project.godot` 即可，`run/main_scene` 已经是封面。

命令行（Windows 例子；**调试一定要用 console 版**，普通版没有 stdout）：

```powershell
# 导入素材（改了 png / tscn 之后跑一次）
& '<你的路径>\Godot_v4.7.2-stable_win64_console.exe' --headless --path '<本仓库路径>' --import

# 整个游戏（封面 → 第一天 → 前日谈 → 第一天收尾 → 第二天 → 标题）
& '<你的路径>\Godot_v4.7.2-stable_win64_console.exe' --path '<本仓库路径>' --rendering-driver opengl3

# 直接进一周目（跳过封面）
... --path '<本仓库路径>' --rendering-driver opengl3 res://scenes/week1/week1_1.tscn
```

`--headless` 用的是 dummy 渲染器，**渲染问题必须加 `--rendering-driver opengl3` 复现**，否则会看到假报错。

操作：左键 / 空格推进对话；走位时 WASD 或方向键移动，空格 / E / 点击查看身边物件；Tab 或 T 打开笔记；Esc 暂停菜单（保存 / 读档 / 设置 / 回标题 / 退出）。

玩家的存档与设置写在 `user://`（Windows 是 `%APPDATA%\Godot\app_userdata\寻星\`）：
`xunxing_save.json`、`xunxing_settings.cfg`。仓库里没有它们。

---

## 三、改完必跑（回归基线）

```powershell
node tools/check_gdscript.mjs       # GDScript 静态结构自检
node tools/validate_prelude.mjs     # 剧本 JSON 校验（序列 / 行数 / 出错项）
```

| 探针 | 基线 | 管什么 |
|---|---|---|
| `tools/probe_week1.gd` | **209** | 一周目总闸：静态检查 + 八个面板 + 三次走位 + 幕间 + 章节链 |
| `tools/probe_week2.gd` | **85** | 二周目总闸：五个面板 + 现场走位 + 章节链 |
| `tools/probe_resume.gd` | **21** | 走位 → 对话恢复（整幕按真实流程走一遍） |
| `tools/probe_walk.gd` | **19** | 走位房间：镜头 1:1 跟随、靠近判定、弹窗 |
| `tools/probe_collide.gd` | **18** | 家具碰撞块：挡得住、能滑开、出生点 |
| `tools/probe_maze.gd` | **60** | 七色镜廊：静态布局 + 真实光线追踪 + 点格子 + 判胜 |
| `tools/probe_soup.gd` | **42** | 海龟汤：16 题点满 10 个解锁挑词、16 选 6、连错 3 次给汤底 |
| `tools/probe_save.gd` | **62** | 回看 / 自动存档 / 笔记 / 标题页 |
| `tools/probe_pause.gd` | **73** | 暂停菜单与设置（Esc 开合、paused 联动、音量写盘、自动播放计时） |
| `tools/probe_portrait.gd` | 逐张 | 七张立绘抠图：人物本体被误抠必须是 0 像素 |
| `tools/solve_maze.gd` | 解数 = 1 | 镜廊求解器（改题目数据后必须仍是唯一解） |

跑法都一样：

```powershell
& '<你的路径>\Godot_v4.7.2-stable_win64_console.exe' --headless --path '<本仓库路径>' --script tools/probe_week1.gd
```

`probe_save.gd` / `probe_pause.gd` 会真写 `user://`，但**开跑前备份玩家原档、结束时还原**。
`tools/import_assets.gd`（素材入库，幂等）和 `tools/preview_portraits.gd`（立绘对照图）是美术侧工具。

---

## 四、目录结构

```
project.godot                 项目配置（1280x720、autoload、输入动作、msaa_2d）
李星.png / 刘忆.png            作者给的两张主角立绘原图（灰白手绘，风格基准）
assets/                       入库后的素材：cover / portraits（7 张透明底立绘）/ props
data/                         全部剧本与房间数据（JSON，见下）
  week1_dialogue.json         一周目：s0_maze → s1_phone → s2_books → s3_desk → s4_soup → s4b_1089 → s5_wardrobe → s6_ending
  week2_dialogue.json         二周目：s0_scene → s1_method → s2_motive → s3_classroom → s4_alibi → s5_cup → s6_truth
  prelude_dialogue.json       前日谈两幕
  prelude_rooms.json          俯视角房间：地面范围、墙、家具碰撞块、可查看物件（含放大图路径）
scenes/                       title / week1 / week2 / prelude 六个场景
scripts/                      代码（62 个 .gd）
  ui/                         对话运行时、走位运行时、封面、暂停菜单、背景与房间绘制
  week1/ week2/               两边的解谜面板（panel_*.gd）+ 面板登记表（*_panels.gd）
  prelude/                    章节驱动（week1_1 / week2_1 / prelude_1 / prelude_2）+ 存档、设置、状态
autoload/                     McpInteractionServer（调试用，见 §七）
tools/                        探针与素材工具（Node 脚本 + GDScript）
shaders/                      少量绘制着色器
_docs/                        设计稿原件（含 .gdignore，Godot 不导入）
_archive/llm/                 已废弃的大模型问答客户端（留档，见 progress 第 43 条）
```

**数据驱动**：剧情、房间、家具坐标、面板题目几乎全在 `data/*.json` 里，改文案/坐标不用碰代码。
行类型见 `HANDOFF.md`；面板与走位的接口见下。

---

## 五、改东西的规矩（踩过的坑换来的）

1. **面板脚本不要覆盖 `_ready()`**，只覆盖 `panel_title()` / `panel_hint()` / `build_body()`，
   过关调 `close_panel({...})`；框架固定 900×540，自带 `make_button` / `make_text` / `make_rich`。
2. **弹窗里画什么必须由下标驱动**：凡"点了第 N 个东西弹出来的详情"，详情函数里出现字面量颜色或坐标就是 bug
   （坑 65：围巾的主视图曾经一律画成红外套）。
3. **改房间家具坐标，必须同步 `tools/probe_collide.gd` 里写死的期望坐标**，否则碰撞探针会红（坑 57）。
4. **固定高度容器里别放自动换行的 Label**，文字会画到隔壁去（坑 62）。
5. **往章节序列中间插新段会让老存档跳段**（`SaveGame` 存的是数字下标，坑 64）。
6. 中文字体 / 立绘走 `PreludeUI.load_texture()`，别自己 `load()`。
7. 改完按 §三 跑探针；**别为了让探针变绿去放宽断言**，先确认是代码错还是期望值过期。

完整的 65 条坑在 `HANDOFF.md` 第五节。

---

## 六、现在到哪一步 / 还缺什么

**能通关**：一周目六关 + 1089 回忆 + 前日谈两幕 + 一周目收尾 + 二周目七段 + 回标题页；
存档 / 读档 / 笔记 / 回看 / 暂停 / 设置（音量、自动播放）都在。

**还没做**（按交接时点的状态）：

- **Bridge / 真结局与各结局结尾 CG** —— 剧情大纲里"b 的死亡以比较隐晦的方式呈现在 bridge 中"，
  目前二周目播完直接回标题页；`scripts/prelude/week2_1.gd` 里留了 TODO，接 bridge 时改那里。
- **音频**：游戏目前没有任何声音。
- **二周目教室不可走动**（一周目有三次走位，二周目只有现场一次）。
- **立绘表情差分**没有（现有 7 张立绘无表情参数）。
- **美术清单 §8 的 7 条待拍板**（见 `美术需求清单.md`）。
- **外部玩家测试尚未开始**（`测试清单-外部玩家.md` 还没发出去）。

---

## 七、两个给"接手的人"的说明

- `autoload/mcp_interaction_server.gd`（`McpInteractionServer`）是**开发调试用的本地交互服务**（监听
  127.0.0.1:9090），配合 AI 助手 / godot-bridge 插件检查运行中的游戏用。它和游戏玩法无关：
  不想要就在 `project.godot` 的 `[autoload]` 里删掉 `McpInteractionServer` 那一行，再删掉那个文件。
- **项目不联网**：曾经给海龟汤做过"自己打字提问"的大模型路径，因为不能把 API key 打进包、且每次提问都要付费，
  已按作者决定整条砍掉并归档到 `_archive/llm/`。不要在没有想清楚 key 归谁之前接回去（progress 第 43 条）。

---

## 八、提交建议

- 首次提交已包含全部代码、`data/`、`assets/`、设计稿与文档（约 28 MB，最大单文件 7 MB，**不需要 Git LFS**）。
- `.godot/` 已被忽略，克隆后第一次打开编辑器（或 `--import`）会自动重建。
- 建议分支：`main` 保可用版本，改动走短分支 + 自测（§三 探针全绿）再合并。
