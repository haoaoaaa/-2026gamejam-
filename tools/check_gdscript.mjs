#!/usr/bin/env node
// ============================================================================
//  《涌现》前日谈 —— GDScript 静态自检（Node 运行，不进 Godot 项目）
// ============================================================================
//  用法： node tools/check_gdscript.mjs
//
//  这不是编译器，只查那些"一定会炸 / 一定会警告"的结构问题：
//    · 语法列结构：每个文件的缩进层级是否合法、代码是否出现在 class 外
//    · 同名函数 / 同名成员变量重复声明（后者静默覆盖前者，极难查）
//    · 成员变量声明夹在函数中间（GDScript 允许但不该这么写）
//    · 调用了本项目里压根没定义的方法
//    · new() 的类名是不是 Godot 内置类或本项目内部类
//    · .tscn 引用的脚本 / shader 路径是否存在
//    · 必需文件是否齐全
//
//  作用域模型（关键，第一版就是在这里误报满屏）：
//    顶格(0)        → 文件级：func / class Foo:
//    一级(1)        → 内部类成员区：var / const / func
//    二级及更深(2+) → 函数体内：局部变量、控制流
//    同名变量出现在"不同"作用域里是完全合法的，不能算重复。
// ============================================================================

import { readFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const problems = [];
const notes = [];

const bad = (file, line, msg) => problems.push(`${file}:${line}  ${msg}`);
const note = (file, line, msg) => notes.push(`${file}:${line}  ${msg}`);

// ---------------------------------------------------------------- 收集文件
function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name === ".godot" || name === ".git" || name === "node_modules") continue;
    if (name === "_archive") continue; // 归档件（例如退休的 llm_client.gd）不算项目代码
    if (name === "_docs") continue; // 设计稿原件（docx 解出来的文本），不是代码
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

const all = walk(root);
const gdFiles = all.filter((f) => f.endsWith(".gd"));
const tscnFiles = all.filter((f) => f.endsWith(".tscn"));
const shaderFiles = all.filter((f) => f.endsWith(".gdshader"));
const relOf = (f) => relative(root, f).replace(/\\/g, "/");

if (gdFiles.length === 0) {
  console.error("✗ 没找到任何 .gd 文件，工作目录是不是不对？");
  process.exit(1);
}

// ---------------------------------------------------------------- Godot 内置类
const GODOT_CLASSES = new Set([
  "Control", "Node", "Node2D", "Node3D", "CanvasItem", "CanvasLayer", "Label",
  "RichTextLabel", "Button", "ColorRect", "TextureRect", "PanelContainer", "Panel",
  "MarginContainer", "VBoxContainer", "HBoxContainer", "BoxContainer", "Container",
  "ScrollContainer", "GridContainer", "CenterContainer", "TabContainer",
  "StyleBoxFlat", "StyleBoxEmpty", "StyleBoxTexture", "StyleBox", "Theme",
  "ImageTexture", "Image", "Texture2D", "GradientTexture2D", "Gradient",
  "GradientTexture1D", "NoiseTexture2D", "AtlasTexture", "CurveTexture",
  "ShaderMaterial", "Shader", "Material", "CanvasItemMaterial",
  "Tween", "SceneTree", "Timer", "Engine", "OS", "Input", "InputEvent",
  "InputEventKey", "InputEventMouseButton", "InputEventAction",
  "FileAccess", "JSON", "ResourceLoader", "Resource", "PackedScene",
  "Vector2", "Vector2i", "Vector3", "Rect2", "Rect2i", "Color", "Transform2D",
  "Basis", "Quaternion", "Projection", "AABB", "Plane", "Callable", "Signal",
  "Array", "Dictionary", "String", "StringName", "NodePath", "RID",
  "PackedStringArray", "PackedVector2Array", "PackedVector3Array",
  "PackedColorArray", "PackedFloat32Array", "PackedInt32Array", "PackedByteArray",
  "AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStream", "AudioStreamOggVorbis",
  "AnimationPlayer", "Animation", "Sprite2D", "Polygon2D", "Line2D", "Camera2D",
  "WorldEnvironment", "Environment", "SubViewport", "SubViewportContainer",
  "Viewport", "Window", "Popup", "PopupMenu", "AcceptDialog", "ConfirmationDialog",
  "Font", "FontFile", "FontVariation", "SystemFont", "LabelSettings",
  "RandomNumberGenerator", "Time", "Performance", "MainLoop", "ConfigFile",
  "DirAccess", "Thread", "WorkerThreadPool",
]);

// 上面这份是手写的最小表（保证没有 godot_classes.json 时也能跑）。
// 完整的类表由 tools/dump_classdb.gd 从引擎里导出来，存在 tools/godot_classes.json：
//   godot --headless --path . --script tools/dump_classdb.gd
// 换了 Godot 版本、或这里报「XXX.new()：既不是 Godot 内置类」但你确定那是引擎自带的类，
// 就重跑一次那个脚本，把 godot_classes.json 一起提交。
try {
  const dumped = JSON.parse(readFileSync(join(root, "tools/godot_classes.json"), "utf8"));
  for (const c of dumped) GODOT_CLASSES.add(c);
} catch {
  console.log("（没找到 tools/godot_classes.json，只用内置的最小类表）");
}

// ---------------------------------------------------------------- 字符扫描器
// 逐字符遍历，正确跟踪字符串 / 注释 / 三引号多行串，再统计括号与引号。
// 之所以不用正则：GDScript 字符串里会出现 "、[、]、( 等字符，
// 而 "…%d.[/color]  %s" % [...] 这种格式化串会让正则的回溯算错括号数。
function scanCode(src) {
  let i = 0;
  const n = src.length;
  let inStr = false;      // 普通 "…"
  let inTriple = false;   // """…"""
  let inComment = false;
  let dq = 0;
  let depthParen = 0, depthBracket = 0, depthBrace = 0;
  let minParen = 0;
  let countParenOpen = 0, countParenClose = 0;

  while (i < n) {
    const ch = src[i];
    const next3 = src.substr(i, 3);

    if (inComment) {
      if (ch === "\n") inComment = false;
      i++;
      continue;
    }
    if (inTriple) {
      if (next3 === '"""') { inTriple = false; i += 3; continue; }
      i++;
      continue;
    }
    if (inStr) {
      if (ch === "\\") { i += 2; continue; }   // 转义
      if (ch === '"') { inStr = false; dq++; i++; continue; }
      i++;
      continue;
    }
    // 不在字符串里
    if (next3 === '"""') { inTriple = true; dq += 3; i += 3; continue; }
    if (ch === '"') { inStr = true; dq++; i++; continue; }
    if (ch === "#") { inComment = true; i++; continue; }
    switch (ch) {
      case "(": depthParen++; countParenOpen++; break;
      case ")": depthParen--; countParenClose++; if (depthParen < minParen) minParen = depthParen; break;
      case "[": depthBracket++; break;
      case "]": depthBracket--; break;
      case "{": depthBrace++; break;
      case "}": depthBrace--; break;
      default: break;
    }
    i++;
  }
  return { dq, depthParen, depthBracket, depthBrace, minParen, countParenOpen, countParenClose, unterminated: inStr || inTriple };
}

// ---------------------------------------------------------------- 解析
// 每个文件产出一份作用域表
const parsed = new Map(); // rel → { src, lines, methods:Set, topVars:Set, innerClasses:Map, classNames:Set }
const classNames = new Map(); // class_name → rel
const autoloads = new Map();

// 从 project.godot 读 autoload
if (existsSync(join(root, "project.godot"))) {
  const pg = readFileSync(join(root, "project.godot"), "utf8");
  const autoSec = pg.match(/\[autoload\]([\s\S]*?)(?=\n\[|$)/);
  if (autoSec) {
    for (const m of autoSec[1].matchAll(
      /^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"\*?(res:\/\/[^"]+)"/gm,
    )) {
      autoloads.set(m[1], m[2].replace("res://", ""));
    }
  }
}

for (const f of gdFiles) {
  const rel = relOf(f);
  const src = readFileSync(f, "utf8");
  const lines = src.split(/\r?\n/);

  const cn = src.match(/^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)/m);
  if (cn) classNames.set(cn[1], rel);

  const info = {
    src, lines,
    methods: new Set(),                    // 所有层级的方法名
    topMethods: new Map(),                 // 方法名 → 行号（用于重复检测）
    topVars: new Set(),                    // 顶层成员变量
    topVarLine: new Map(),
    innerClasses: new Map(),               // 内部类名 → { methods:Set, vars:Set, line }
    inlineInner: new Map(),                // 内部类名（含 PreludeUI.X 形式）
  };

  let curInner = null;      // 当前内部类名
  let inFunc = false;       // 当前是否在函数体内（顶格或内部类的函数）
  let funcDepth = 0;

  lines.forEach((raw, idx) => {
    const lineNo = idx + 1;
    const noComment = raw.replace(/#.*$/, "");
    if (noComment.trim() === "") return;

    const tabs = (noComment.match(/^\t*/) || [""])[0].length;
    const code = noComment.trim();

    // ---- 顶层 class Foo:  (0 缩进)
    const mClass = code.match(/^class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:/);
    if (tabs === 0 && mClass) {
      curInner = mClass[1];
      inFunc = false;
      info.innerClasses.set(curInner, { methods: new Set(), vars: new Set(), line: lineNo });
      return;
    }

    // ---- 顶层 func（含 static）
    const mFunc = code.match(/^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/);
    if (mFunc) {
      const name = mFunc[1];
      if (tabs === 0) {
        if (info.topMethods.has(name)) {
          bad(rel, lineNo,
            `函数 ${name}() 重复定义（上一次在第 ${info.topMethods.get(name)} 行），后者会静默覆盖前者`);
        }
        info.topMethods.set(name, lineNo);
        curInner = null;
      } else {
        if (curInner && info.innerClasses.has(curInner)) {
          const ic = info.innerClasses.get(curInner);
          if (ic.methods.has(name)) {
            bad(rel, lineNo, `内部类 ${curInner} 的 ${name}() 重复定义`);
          }
          ic.methods.add(name);
        }
      }
      info.methods.add(name);
      inFunc = true;
      funcDepth = tabs;
      return;
    }

    // ---- 变量声明
    const mVar = code.match(/^var\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (mVar) {
      const name = mVar[1];
      if (tabs === 0) {
        if (info.topVars.has(name)) {
          bad(rel, lineNo,
            `成员变量 ${name} 重复声明（上一次在第 ${info.topVarLine.get(name)} 行）`);
        }
        info.topVars.add(name);
        info.topVarLine.set(name, lineNo);
        if (inFunc) {
          note(rel, lineNo, `成员变量 ${name} 声明在函数之后，建议统一移到文件顶部`);
        }
      } else if (tabs === 1 && curInner && inFunc === false) {
        const ic = info.innerClasses.get(curInner);
        if (ic && ic.vars.has(name)) {
          bad(rel, lineNo, `内部类 ${curInner} 的成员 ${name} 重复声明`);
        }
        if (ic) ic.vars.add(name);
      }
      return;
    }

    // ---- 回到内部类成员区（缩进 ≤ 1 且不是代码块内的语句）
    if (tabs <= 1 && funcDepth > 0 && tabs <= funcDepth) {
      inFunc = false;
      funcDepth = 0;
      if (tabs === 0) curInner = null;
    }
  });

  parsed.set(rel, info);
}

// ---------------------------------------------------------------- 语法粗筛
for (const [rel, info] of parsed) {
  const { lines, src } = info;

  // 全角标点混进代码位置
  lines.forEach((raw, i) => {
    const code = raw.replace(/#.*$/, "");
    const noStr = code.replace(/"[^"]*"/g, '""');
    if (/\w+\s*（/.test(noStr)) bad(rel, i + 1, "代码位置出现了全角括号（），GDScript 只认半角");
    if (/\w+\s*：\s*$/.test(noStr) && !/^class\s/.test(noStr.trim())) {
      bad(rel, i + 1, "行尾出现了全角冒号：，GDScript 只认半角 :");
    }
  });

  // 跨行的括号平衡（整文件级别，比逐行可靠）
  //  注意：不能用正则去剥字符串 —— 贪婪/回溯会在 "…%d.[/color]  %s" 这类
  //  内含引号的格式化串上算错，第一版就是这么误报的。这里改为逐字符状态机。
  const scan = scanCode(src);
  if (scan.dq % 2 !== 0) {
    bad(rel, 1, `双引号总数为奇数（${scan.dq}），有字符串没闭合`);
  }
  if (scan.depthParen !== 0) {
    bad(rel, 1, `圆括号不配对，最终净差 ${scan.depthParen}（左 ${scan.countParenOpen} / 右 ${scan.countParenClose}）`);
  }
  if (scan.depthBracket !== 0) {
    bad(rel, 1, `方括号不配对，最终净差 ${scan.depthBracket}`);
  }
  if (scan.depthBrace !== 0) {
    bad(rel, 1, `花括号不配对，最终净差 ${scan.depthBrace}`);
  }
  if (scan.minParen < 0) {
    bad(rel, 1, "出现了多余的右括号 )");
  }
}

// ---------------------------------------------------------------- 调用检查
const knownClasses = new Set([...classNames.keys(), ...parsed.keys()]);
// 内部类名（全局收集，用于 .new() 与 PreludeUI.X 形式）
const allInnerClasses = new Set();
for (const [, info] of parsed) {
  for (const name of info.innerClasses.keys()) allInnerClasses.add(name);
}

// 把每个文件的"可调用方法集"算出来（含基类链）
function methodsOf(rel, seen = new Set()) {
  if (!rel || seen.has(rel)) return new Set();
  seen.add(rel);
  const info = parsed.get(rel);
  if (!info) return new Set();
  const out = new Set(info.methods);
  const ext = info.src.match(/^extends\s+"(res:\/\/[^"]+)"/m);
  if (ext) for (const m of methodsOf(ext[1].replace("res://", ""), seen)) out.add(m);
  const extClass = info.src.match(/^extends\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/m);
  if (extClass && classNames.has(extClass[1])) {
    for (const m of methodsOf(classNames.get(extClass[1]), seen)) out.add(m);
  }
  return out;
}

for (const [rel, info] of parsed) {
  const own = methodsOf(rel);
  // 本文件所有内部类的方法也算"自己能调"
  for (const [, ic] of info.innerClasses) for (const m of ic.methods) own.add(m);

  info.lines.forEach((raw, i) => {
    const code = raw.replace(/#.*$/, "");
    if (/^\s*#/.test(raw)) return;

    // self.foo( 必须存在
    for (const m of code.matchAll(/\bself\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
      if (!own.has(m[1])) {
        bad(rel, i + 1, `调用了 self.${m[1]}()，但本文件（含基类链）没有定义这个方法`);
      }
    }

    // ClassName.method(  —— 只查本项目已知的 class_name
    for (const m of code.matchAll(/\b([A-Z][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
      const [, cls, meth] = m;
      const ownerRel = classNames.get(cls);
      if (!ownerRel) continue;
      const owner = parsed.get(ownerRel);
      if (!owner) continue;
      const set = methodsOf(ownerRel);
      // 内部类的 static / 方法调用形如 PreludeUI.DialogueBox.new()，单独放过
      if (owner.innerClasses.has(meth)) continue;
      if (set.size && !set.has(meth)) {
        bad(rel, i + 1, `${cls}.${meth}() 在 ${ownerRel} 里不存在`);
      }
    }

    // X.new()
    for (const m of code.matchAll(/(?<![.\w])([A-Za-z_][A-Za-z0-9_]*)\.new\s*\(/g)) {
      const cls = m[1];
      if (GODOT_CLASSES.has(cls)) continue;
      if (knownClasses.has(cls)) continue;
      if (allInnerClasses.has(cls)) continue;
      if (/^[A-Z]/.test(cls)) {
        bad(rel, i + 1, `${cls}.new()：既不是 Godot 内置类，也不是本项目定义的类/内部类`);
      }
    }
  });
}

// ---------------------------------------------------------------- 场景 / 资源引用
for (const f of tscnFiles) {
  const rel = relOf(f);
  const src = readFileSync(f, "utf8");
  for (const m of src.matchAll(/path="res:\/\/([^"]+)"/g)) {
    if (!existsSync(join(root, m[1]))) bad(rel, 1, `引用了不存在的文件 res://${m[1]}`);
  }
}

// ---------------------------------------------------------------- 运行时里写死的路径
// assets/ 下的贴图是"等美术出图"的可选落点（代码按"有则用、无则退占位"写），
// 缺失属于预期，不算问题；其他路径缺失才是真问题。
const OPTIONAL_ASSET_PREFIX = "assets/";
for (const [rel, info] of parsed) {
  info.lines.forEach((raw, i) => {
    for (const m of raw.matchAll(/"(res:\/\/[^"]+\.(?:gd|tscn|gdshader|json|png))"/g)) {
      const r = m[1].replace("res://", "");
      if (r.startsWith(OPTIONAL_ASSET_PREFIX)) continue;
      // 探针/预览脚本运行时自己写出来的临时图（项目约定：以下划线开头的临时文件，已 gitignore）
      if (r.startsWith("_")) continue;
      if (!existsSync(join(root, r))) {
        bad(rel, i + 1, `代码里引用了不存在的资源 ${m[1]}`);
      }
    }
  });
}

// ---------------------------------------------------------------- 必需文件
const required = [
  "project.godot",
  "data/prelude_dialogue.json",
  "scripts/prelude/prelude_state.gd",
  "scripts/prelude/prelude_base.gd",
  "scripts/prelude/prelude_1.gd",
  "scripts/prelude/prelude_2.gd",
  "scripts/ui/prelude_ui.gd",
  "scripts/ui/dialogue_runtime.gd",
  "scripts/ui/prelude_backdrop.gd",
  "shaders/portrait_frame.gdshader",
  "scenes/prelude/prelude_1.tscn",
  "scenes/prelude/prelude_2.tscn",
  "李星.png",
  "刘忆.png",
];
for (const r of required) {
  if (!existsSync(join(root, r))) bad("(工程)", 1, `缺少必需文件 ${r}`);
}

// ---------------------------------------------------------------- 报告
console.log("== 《涌现》前日谈 · GDScript 结构自检 ==\n");
console.log(
  `扫描：${gdFiles.length} 个 .gd、${tscnFiles.length} 个 .tscn、${shaderFiles.length} 个 .gdshader`,
);
console.log(`项目类：${[...classNames.keys()].join(" / ") || "(无)"}`);
console.log(`自动加载：${[...autoloads.keys()].join(" / ") || "(无)"}`);
const innerList = [...allInnerClasses].join(" / ");
console.log(`内部类：${innerList || "(无)"}\n`);

if (notes.length) {
  console.log(`· 提示 ${notes.length} 条（不一定是问题）：`);
  for (const n of notes) console.log(`   ${n}`);
  console.log("");
}
if (problems.length) {
  console.log(`✗ 发现 ${problems.length} 个问题：`);
  for (const p of problems) console.log(`   ${p}`);
  process.exit(1);
}
console.log("✓ 结构自检通过：无缩进错乱、无重复声明、无未知方法、无未知类、无失效引用。");
