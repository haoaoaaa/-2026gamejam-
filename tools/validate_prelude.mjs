#!/usr/bin/env node
// ============================================================================
//  《涌现》前日谈 —— 脚本数据校验器（Node 运行，不进 Godot 项目）
// ============================================================================
//  用法： node tools/validate_prelude.mjs
//
//  它按 scripts/ui/dialogue_runtime.gd 里 _run_next() 的 match 分支，逐条校验
//  data/prelude_dialogue.json 的每个序列、每一行，确保：
//    · 行类型是运行时认识的
//    · 参数个数 / 类型对得上（尤其 choice 的选项数与分支数必须一致）
//    · 说话人、场景键、立绘键都是已定义的
//    · 序列 id 与 prelude_1.gd / prelude_2.gd 里 chapter_sequences() 列出的对得上
// ============================================================================

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const errors = [];
const warnings = [];

function err(where, msg) {
  errors.push(`${where}: ${msg}`);
}
function warn(where, msg) {
  warnings.push(`${where}: ${msg}`);
}

// ---------------------------------------------------------------- 从运行时读取"事实"
const runtimeSrc = readFileSync(join(root, "scripts/ui/dialogue_runtime.gd"), "utf8");

/** 从 GDScript 里抠出 const NAME := "value" 形式的一串字符串 */
function gdStringArray(src, constName, kind) {
  const re = new RegExp(
    `${constName}\\s*(?::=\\s*|=\\s*)\\{([\\s\\S]*?)\\n\\}`,
    "m",
  );
  const m = src.match(re);
  if (!m) return null;
  const out = [];
  const itemRe = /"([^"]+)"\s*:\s*"([^"]*)"/g;
  let im;
  while ((im = itemRe.exec(m[1])) !== null) out.push(im[2]);
  return out;
}

function gdConstStrings(src, constName) {
  const re = new RegExp(
    `${constName}\\s*(?::=\\s*|=\\s*)\\{([\\s\\S]*?)\\n\\}`,
    "m",
  );
  const m = src.match(re);
  if (!m) return null;
  const out = [];
  const itemRe = /"([^"]+)"\s*:\s*"([^"]+)"/g;
  let im;
  while ((im = itemRe.exec(m[1])) !== null) out.push(im[2]);
  return out;
}

// ART = { "李星": "res://李星.png", ... }  → 键就是立绘键
const artBlock = runtimeSrc.match(/const ART\s*:=\s*\{([\s\S]*?)\n\}/);
const portraitKeys = artBlock
  ? [...artBlock[1].matchAll(/"([^"]+)"\s*:/g)].map((m) => m[1])
  : [];
// SIDE = { "李星": -1, ... }
const sideBlock = runtimeSrc.match(/const SIDE\s*:=\s*\{([\s\S]*?)\n\}/);
const sideKeys = sideBlock
  ? [...sideBlock[1].matchAll(/"([^"]+)"\s*:/g)].map((m) => m[1])
  : [];
// SPACE_* 常量 → 场景键
const spaceKeys = [...runtimeSrc.matchAll(/const SPACE_[A-Z_]+\s*:=\s*"([^"]+)"/g)].map(
  (m) => m[1],
);
// SPACE_TINT 里给出的场景键（场景底真正实现的那些）
const tintBlock = runtimeSrc.match(/const SPACE_TINT\s*:=\s*\{([\s\S]*?)\n\}/);
const tintKeys = tintBlock
  ? [...tintBlock[1].matchAll(/([A-Za-z_][A-Za-z0-9_]*)\s*:/g)].map((m) => m[1])
  : [];

if (portraitKeys.length === 0) err("dialogue_runtime.gd", "没能解析出 ART 立绘表");
if (spaceKeys.length === 0) err("dialogue_runtime.gd", "没能解析出 SPACE_* 场景键");

// 场景底实际画了哪些场景
const backdropSrc = readFileSync(join(root, "scripts/ui/prelude_backdrop.gd"), "utf8");
const drawnScenes = [...backdropSrc.matchAll(/^\t\t"([a-z_]+)":\s*$/gm)].map((m) => m[1]);

// ---------------------------------------------------------------- 行类型定义
// 与 dialogue_runtime.gd 的 match kind 严格对应
// [参数名, 是否必填, 期望类型]
const ROW_SPEC = {
  n: [["文本", true, "string"]],
  d: [
    ["说话人", true, "string"],
    ["文本", true, "string"],
  ],
  m: [["文本", true, "string"]],
  title: [
    ["大标题", true, "string"],
    ["副标题", false, "string"],
  ],
  space: [
    ["场景键", true, "string"],
    ["立绘数组", false, "array"],
  ],
  who: [["立绘键", true, "string"]],
  show: [["立绘键", true, "string"]],
  hide: [["立绘键", true, "string"]],
  item: [
    ["名称", true, "string"],
    ["详情", true, "string"],
    ["矩形", true, "rect"],
  ],
  peek: [
    ["物品名", true, "string"],
    ["追加行", true, "array"],
  ],
  room: [["房间id", true, "string"]],
  free: [],
  card: [["文本", true, "string"]],
  choice: [
    ["提示语", true, "string"],
    ["选项文本数组", true, "array"],
    ["分支数组", true, "array"],
  ],
};

// ---------------------------------------------------------------- 校验一棵"行树"
function checkRows(rows, where) {
  if (!Array.isArray(rows)) {
    err(where, `应当是数组，实际是 ${typeof rows}`);
    return 0;
  }
  const itemNames = new Set();
  let count = 0;
  for (let i = 0; i < rows.length; i++) {
    const at = `${where}[${i}]`;
    const row = rows[i];
    if (!Array.isArray(row) || row.length === 0) {
      err(at, `行必须是至少含一个元素的数组`);
      continue;
    }
    if (typeof row[0] !== "string") {
      err(at, `行类型必须是字符串，实际是 ${typeof row[0]}`);
      continue;
    }
    const kind = row[0];
    const spec = ROW_SPEC[kind];
    if (!spec) {
      err(at, `运行时没有的行类型 "${kind}"（合法值：${Object.keys(ROW_SPEC).join(" ")}）`);
      continue;
    }
    count++;

    // 参数个数
    const required = spec.filter((s) => s[1]).length;
    if (row.length - 1 < required) {
      err(at, `["${kind}"] 缺参数：需要至少 ${required} 个，实际 ${row.length - 1} 个`);
      continue;
    }
    if (row.length - 1 > spec.length) {
      warn(at, `["${kind}"] 多出 ${row.length - 1 - spec.length} 个参数，运行时不会用到`);
    }

    // 参数类型
    for (let p = 0; p < spec.length; p++) {
      const [pname, , ptype] = spec[p];
      const v = row[p + 1];
      if (v === undefined) continue;
      if (ptype === "string" && typeof v !== "string") {
        err(at, `["${kind}"] 的「${pname}」应当是字符串，实际是 ${typeof v}`);
      } else if (ptype === "array" && !Array.isArray(v)) {
        err(at, `["${kind}"] 的「${pname}」应当是数组，实际是 ${typeof v}`);
      } else if (ptype === "rect") {
        if (!Array.isArray(v) || v.length < 4 || v.some((n) => typeof n !== "number")) {
          err(at, `["${kind}"] 的「${pname}」应当是 [x, y, w, h] 四个数字`);
        } else {
          const [x, y, w, h] = v;
          if (x < 0 || y < 0 || x + w > 1280 || y + h > 720) {
            warn(at, `热区 ${JSON.stringify(v)} 超出 1280x720 画面（设计分辨率）`);
          }
        }
      }
    }

    // 语义检查
    if (kind === "d" || kind === "who" || kind === "show" || kind === "hide") {
      const who = row[1];
      if (!portraitKeys.includes(who)) {
        err(at, `「${who}」不在 ART 立绘表里（已有：${portraitKeys.join(" / ")}）`);
      }
      if (kind === "who" && !sideKeys.includes(who)) {
        err(at, `「${who}」在 SIDE 表里没有站位定义`);
      }
    }
    if (kind === "space") {
      const key = row[1];
      if (!spaceKeys.includes(key)) {
        err(at, `场景键「${key}」不在 SPACE_* 常量里（已有：${spaceKeys.join(" / ")}）`);
      }
      if (drawnScenes.length > 0 && !drawnScenes.includes(key)) {
        warn(at, `场景键「${key}」在 prelude_backdrop.gd 里没有对应绘制分支，会退回默认场景`);
      }
      if (Array.isArray(row[2])) {
        for (const w of row[2]) {
          if (!portraitKeys.includes(w)) {
            err(at, `space 的立绘数组里有未知角色「${w}」`);
          }
        }
      }
    }
    if (kind === "item") {
      itemNames.add(row[1]);
      if (row[1].length > 12) warn(at, `物品名「${row[1]}」偏长，热区按钮上可能显示不下`);
    }
    if (kind === "room") {
      // 声明了可走房间：peek 的物品名只要在那间房的 items 里存在就算对得上
      const rid = row[1];
      const r = ROOM_ITEMS[rid];
      if (!r) {
        err(at, `room 指向了 data/prelude_rooms.json 里没有的房间「${rid}」`);
      } else {
        for (const n of r) itemNames.add(n);
        walkRooms.add(rid);
      }
    }
    if (kind === "choice") {
      const opts = row[2];
      const branches = row[3];
      if (Array.isArray(opts) && Array.isArray(branches)) {
        if (opts.length !== branches.length) {
          err(at, `选项数 ${opts.length} 与分支数 ${branches.length} 不一致，玩家点下去会错位`);
        }
        for (const o of opts) {
          if (typeof o !== "string" || o.trim() === "") {
            err(at, `有空选项文本`);
          }
        }
        // 分支是行数组的数组：每个分支的行会内联进 _rows，因此同样要校验
        for (let b = 0; b < branches.length; b++) {
          count += checkRows(branches[b], `${at}.分支${b}(${JSON.stringify(opts[b] ?? "")})`);
        }
      }
    }
    if (kind === "peek") {
      const target = row[1];
      if (!itemNames.has(target)) {
        warn(at, `peek 指向物品「${target}」，但同一序列里在这个位置之前没有对应的 item 行`);
      }
      count += checkRows(row[2], `${at}.peek(${target})`);
    }
  }
  return count;
}

// ---------------------------------------------------------------- 读取数据
let data;
const dataPath = join(root, "data/prelude_dialogue.json");
try {
  data = JSON.parse(readFileSync(dataPath, "utf8"));
} catch (e) {
  console.error(`✗ 无法解析 ${dataPath}\n  ${e.message}`);
  process.exit(1);
}

// ---------------------------------------------------------------- 可走房间（俯视角）
// roomId → 该房间里所有可交互物件的名字；对话里 ["room", id] + ["peek", 名字, ...]
// 就是靠"名字一致"对接的，所以这里要交叉校验。
const ROOM_ITEMS = {};
const walkRooms = new Set();
try {
  const rooms = JSON.parse(readFileSync(join(root, "data/prelude_rooms.json"), "utf8"));
  for (const [rid, r] of Object.entries(rooms.rooms ?? {})) {
    ROOM_ITEMS[rid] = (r.items ?? []).map((it) => it[5]);
  }
} catch (e) {
  console.error(`✗ 无法解析 data/prelude_rooms.json\n  ${e.message}`);
  process.exit(1);
}

// ---------------------------------------------------------------- 章节 → 序列清单
// 从 prelude_1.gd / prelude_2.gd 里读 chapter_sequences() 实际返回的序列
function sequencesFromChapter(file) {
  const src = readFileSync(join(root, file), "utf8");
  const m = src.match(/func chapter_sequences\(\)[^{]*\{?[\s\S]*?return\s*\[([\s\S]*?)\]/m);
  if (!m) return { chapter: null, seqs: [] };
  const chapter = (src.match(/func chapter_id\(\)[\s\S]*?return\s*"([^"]+)"/) || [])[1] ?? null;
  const seqs = [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]);
  return { chapter, seqs };
}

const chapters = [
  sequencesFromChapter("scripts/prelude/prelude_1.gd"),
  sequencesFromChapter("scripts/prelude/prelude_2.gd"),
];

let totalRows = 0;
const usedSeqIds = new Set();

console.log("== 前日谈脚本数据校验 ==\n");
console.log(`立绘表（ART）  : ${portraitKeys.join(" / ")}`);
console.log(`站位表（SIDE） : ${sideKeys.join(" / ")}`);
console.log(`场景键         : ${spaceKeys.join(" / ")}`);
console.log(`场景底已实现   : ${drawnScenes.join(" / ") || "(未解析到)"}`);
console.log("");

for (const { chapter, seqs } of chapters) {
  if (!chapter) {
    warn("章节文件", "没能解析出 chapter_id()");
    continue;
  }
  const node = data[chapter];
  if (!node) {
    err(`prelude_dialogue.json`, `缺少章节 "${chapter}"`);
    continue;
  }
  console.log(`— 章节 ${chapter}：${seqs.length} 个序列`);
  for (const id of seqs) {
    usedSeqIds.add(`${chapter}/${id}`);
    if (!(id in node)) {
      err(`章节 ${chapter}`, `chapter_sequences() 里的序列 "${id}" 在 JSON 里不存在`);
      continue;
    }
    const n = checkRows(node[id], `${chapter}.${id}`);
    totalRows += n;
    console.log(`    ${id.padEnd(14)} ${String(n).padStart(3)} 行`);
  }
  // 反向检查：JSON 里有、但没被任何章节播放的序列
  for (const key of Object.keys(node)) {
    if (key.startsWith("_")) continue;
    if (!seqs.includes(key)) {
      warn(`章节 ${chapter}`, `序列 "${key}" 定义了但没有被 chapter_sequences() 播放`);
    }
  }
}

// JSON 里多出来的章节
for (const key of Object.keys(data)) {
  if (key.startsWith("_")) continue;
  if (!chapters.some((c) => c.chapter === key)) {
    warn("prelude_dialogue.json", `章节 "${key}" 没有被任何章节脚本使用`);
  }
}

// ---------------------------------------------------------------- 报告
console.log(`\n共校验 ${totalRows} 行脚本。\n`);
if (warnings.length) {
  console.log(`⚠ 警告 ${warnings.length} 条：`);
  for (const w of warnings) console.log(`   · ${w}`);
  console.log("");
}
if (errors.length) {
  console.log(`✗ 错误 ${errors.length} 条：`);
  for (const e of errors) console.log(`   · ${e}`);
  process.exit(1);
}
console.log("✓ 脚本数据校验通过：行类型、参数、说话人、场景键、选项分支数全部一致。");
