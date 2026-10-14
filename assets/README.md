# assets/ —— 美术资源落点（等「游戏素材大师」出图后放这里）

代码已经按"**有贴图就用贴图，没有就退占位**"的双轨写好。
但**不是所有路径都已经接线**——下面每一节都标了"放进去就生效"还是"还需要改一次代码"：

| 节 | 状态 |
|---|---|
| §1 `sprites/` 走位小人 | ⚠️ **未接线**（`room_runtime.gd` 里只有常量声明、没有使用点），放图不显示 |
| §2 `closeups/` 放大图 | ✅ 放进去就生效（但 PNG 要让编辑器扫一次生成 `.import`） |
| §3 `rooms/` 房间底 | ⚠️ 未接线，需要加一层贴图判断（见该节） |
| §4 立绘 | ✅ 已在用，位置见该节 |

---

## 1. `sprites/` —— 俯视角走位时的人物（从上往下看）

> ⚠️ **目前还没有接线**：`scripts/ui/room_runtime.gd:27-34` 声明了
> `PLAYER_TEX_CANDIDATES` / `LIUYI_TEX_CANDIDATES`，但**全文没有任何使用点**，
> 小人至今是 `scripts/ui/prelude_room_draw.gd:507 _draw_person()` 用代码画的。
> 把 PNG 放到下面的路径**不会显示**，需要先加一段接线代码（十几行）。
> 另外现在没有走路序列帧、只有轻微上下浮动，所以要么出静态图（加浮动），要么出 4/8 方向各一张。

| 路径 | 用途 | 建议规格 |
|---|---|---|
| `sprites/lixing_down.png` | 李星，朝下（首选，缺失时退 `lixing.png`） | 256×256 透明底 PNG，脚点在图片下沿正中 |
| `sprites/lixing.png` | 李星，备用 |
| `sprites/liuyi_down.png` | 刘忆，朝下（首选，缺失时退 `liuyi.png`） | 256×256 透明底 PNG |
| `sprites/liuyi.png` | 刘忆，备用 |

**画风要求**：和 `assets/portraits/lixing.png` / `liuyi.png` 那两张灰白手绘立绘统一——深色中粗线、灰调块面、几乎没有高饱和颜色。
李星：深色长发、圆框眼镜、高领外套 + 黑围巾。刘忆：齐肩发、运动外套校服。
**实际尺寸参考**：代码画的小人约两格高（180~235 逻辑像素，含腿、躯干、手臂、头与发型），脚下有一个椭圆影，
所以出图请出**接近全身**（不是只要"肩膀 + 头顶"），脚点在图片下沿正中。

---

## 2. `closeups/` —— 走到物件旁点击后弹出的放大图

| 路径 | 用途 |
|---|---|
| `closeups/corridor_sign.png` | 推理社门牌 |
| `closeups/corridor_schedule.png` | 活动表 |
| `closeups/corridor_notice.png` | 社团通知 |
| `closeups/corridor_poster.png` | 电影海报 |
| `closeups/library_desk.png` | 借还书台 |
| `closeups/library_note.png` | 铅笔便签 |
| `closeups/library_notebook.png` | 三栏笔记 |
| `closeups/library_register.png` | 借还书登记簿 |
| `closeups/dorm_door.png` | 刘忆的寝室门 |
| `closeups/dorm_balconydoor.png` | 阳台门（第二幕关键伏笔） |
| `closeups/dorm_rack.png` | 晾衣绳 |

**规格**：弹窗可用宽约 852、图片高度下限 260，所以**建议 ≥ 1280×400 的横构图**，暗底 + 铅笔感，允许留白。
（占位图本身是代码画的 640×300 灰底 + 金描边 + 交叉线，那只是"这里等一张美术"的标记。）
缺失时自动显示占位图，所以不影响运行。
⚠️ 这一处的加载**没有"直接读文件"的兜底**（`room_runtime.gd:809-816 _load_first()` 只走 `ResourceLoader`），
所以 PNG 必须让 Godot 生成 `.import` 才会显示——用编辑器打开一次工程即可，别只拷文件不扫工程。

---

## 3. `rooms/` —— 整间房间的俯视角底图（可选）

| 路径 | 用途 |
|---|---|
| `rooms/corridor_end.png` | 教学楼六楼走廊尽头 |
| `rooms/library.png` | 图书馆借还书台 |
| `rooms/dorm_corridor.png` | 女生寝室六楼走廊 |

**规格**：2400×720（逻辑坐标就是 2400×720，运行时按视口缩放），或 2:1 等距菱形地块拼接亦可。
**这一项是可选的**：现在房间底由 `scripts/ui/prelude_backdrop.gd` 用铅笔线稿画出来，
如果你更想要一张画好的位图，把图放进 `rooms/` 同名即可（需要我在 `_draw_room()` 里加一层贴图判断，
这一点代码改动是必须的，因为"房间底"和"物件热区坐标"要严格对齐）。

---

## 4. 对话时的立绘（已经在用）

七张立绘放在 **`assets/portraits/`**：`lixing.png`、`liuyi.png`、`teacher.png`、`warden.png`、`student_c.png`、`student_d.png`、`student_e.png`。
`scripts/ui/dialogue_runtime.gd:52-60` 的 `ART` 常量直接引用这七行；没有登记在 `ART` 里的角色**不会生成占位立绘**（`:1118-1131` 直接 return）。
换图放同名文件即可；加人则要改 `ART`。
> 注：**没有表情差分接口**——`prelude_ui.gd` 的 `setup()` 不吃表情参数，现在每人都只有一张。
