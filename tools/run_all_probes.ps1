<#
  run_all_probes.ps1 —— 一条命令跑完《寻星》的全部回归探针

  用法（PowerShell 7）：
     pwsh -ExecutionPolicy Bypass -File tools/run_all_probes.ps1
     pwsh -ExecutionPolicy Bypass -File tools/run_all_probes.ps1 -Only probe_soup
     pwsh -ExecutionPolicy Bypass -File tools/run_all_probes.ps1 -Godot "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" -Project "C:\code\-2026gamejam-"

  用法（Windows 自带的 PowerShell 5.1，没装 pwsh 就用这个）：
     powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_all_probes.ps1

  （`-ExecutionPolicy Bypass` 是必须的：默认策略不让跑 .ps1，会报
    “AuthorizationManager check failed / 禁止运行脚本”。）

  说明：
    - 不传 -Project 时，自动用本脚本的上一级目录（也就是项目根）。
    - 不传 -Godot 时，依次尝试常见路径和 PATH 里的 godot，找不到会提示你手动指定。
    - 一定要用 **console 版** 的 exe（普通版没有 stdout，什么都看不到）。
    - -Only probe_soup,probe_week2 可以只跑几个（边改边验，几秒钟出结果）。
    - probe_save / probe_pause 会真写 user://，但它们开跑前会备份玩家存档、结束时还原。
    - 判定标准：每个探针打印的最后一行里有「失败 0」。
      项数与脚本里记的基线对不上只算 WARN（可能有人加了断言，也可能基线该更新了），
      但「失败 > 0」一律 FAIL。**不要为了让它变绿去放宽探针里的断言。**
#>

param(
  [string]$Godot = "",
  [string]$Project = "",
  [string[]]$Only = @()
)

$ErrorActionPreference = "Continue"

# ---------- 1. 定位项目目录 ----------
if ([string]::IsNullOrWhiteSpace($Project)) {
  $Project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if (-not (Test-Path (Join-Path $Project "project.godot"))) {
  Write-Host "[错误] 这个目录里没有 project.godot：$Project" -ForegroundColor Red
  Write-Host "       用 -Project 指定项目根目录（里面有 project.godot 的那层）。"
  exit 2
}

# ---------- 2. 定位 Godot ----------
if ([string]::IsNullOrWhiteSpace($Godot)) {
  $candidates = @(
    "E:\Godot_v4.7.2-stable_win64_console.exe",
    "D:\Godot_v4.7.2-stable_win64_console.exe",
    "D:\Godot\Godot_v4.7.2-stable_win64_console.exe",
    "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { $Godot = $c; break }
  }
  if ([string]::IsNullOrWhiteSpace($Godot)) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $Godot = $cmd.Source }
  }
}
if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path $Godot)) {
  Write-Host "[错误] 找不到 Godot 可执行文件。" -ForegroundColor Red
  Write-Host "       请用 -Godot 指定 **console 版** 的完整路径，例如："
  Write-Host "       pwsh -File tools/run_all_probes.ps1 -Godot 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe'"
  exit 2
}

Write-Host ""
Write-Host "项目：$Project"
Write-Host "引擎：$Godot"
Write-Host ""

# ---------- 3. 探针清单（名字 / 当前基线项数 / 说明）----------
$probes = @(
  @{ name = "probe_week1";    base = 209; note = "一周目总闸：八个面板 + 三次走位 + 幕间 + 章节链" },
  @{ name = "probe_week2";    base = 85;  note = "二周目总闸：推理面板 + 现场走位 + 章节链" },
  @{ name = "probe_resume";   base = 21;  note = "走位 → 对话恢复" },
  @{ name = "probe_walk";     base = 19;  note = "走位房间：镜头跟随 / 靠近判定 / 弹窗" },
  @{ name = "probe_collide";  base = 18;  note = "家具碰撞" },
  @{ name = "probe_maze";     base = 60;  note = "七色镜廊（真实跑光线）" },
  @{ name = "probe_soup";     base = 42;  note = "海龟汤" },
  @{ name = "probe_save";     base = 62;  note = "回看 / 自动存档 / 笔记 / 标题页" },
  @{ name = "probe_pause";    base = 73;  note = "暂停菜单与设置" },
  @{ name = "probe_portrait"; base = 0;   note = "七张立绘抠图（无项数，看输出里有没有被误抠）" },
  @{ name = "solve_maze";     base = 0;   expect = "解数 = 1"; note = "镜廊求解器（必须仍是唯一解）" }
)

if ($Only.Count -gt 0) {
  # -Only a,b 经过 -File 传参时会是一个字符串，所以这里要再按逗号劈开
  $want = @()
  foreach ($o in $Only) {
    foreach ($piece in ($o -split ",")) {
      $n = $piece.Trim()
      if ($n -ne "") { $want += $n }
    }
  }
  $probes = @($probes | Where-Object { $want -contains $_.name })
  if ($probes.Count -eq 0) {
    Write-Host "[错误] -Only 里写的名字一个都不认识：$($want -join ', ')" -ForegroundColor Red
    exit 2
  }
}

$results = @()
$failed = 0
$warned = 0

foreach ($p in $probes) {
  $file = "tools/$($p.name).gd"
  if (-not (Test-Path (Join-Path $Project $file))) {
    Write-Host ("  {0,-16} 跳过（没有 {1}）" -f $p.name, $file) -ForegroundColor DarkGray
    continue
  }

  Write-Host ("  {0,-16} 运行中…" -f $p.name) -NoNewline
  $out = & $Godot --headless --path $Project --script $file 2>&1
  $code = $LASTEXITCODE
  $text = ($out | Out-String)
  Write-Host "`r"

  # 判定
  $status = "PASS"
  $detail = ""
  if ($text -match "失败\s*(\d+)\s*项") {
    # 绝大多数探针最后一行是「共 N 项检查，失败 M 项」
    $fails = [int]$Matches[1]
    if ($text -match "共\s*(\d+)\s*项检查") {
      $n = [int]$Matches[1]
      $detail = "$n 项，失败 $fails 项"
      if ($fails -eq 0 -and $p.base -gt 0 -and $n -ne $p.base) {
        $status = "WARN"
        $detail = "$n 项（基线记的是 $($p.base) —— 有人加/删了断言？记得更新本脚本和文档）"
      }
    } else {
      $detail = "失败 $fails 项"
    }
    if ($fails -gt 0) { $status = "FAIL" }
  } elseif ($p.base -eq 0) {
    # 没有「失败 N 项」汇总行的探针（例如 solve_maze）：按 expect 关键字 + 无 SCRIPT ERROR 判定
    if ($text -match "SCRIPT ERROR|Failed to load|Parse Error") {
      $status = "FAIL"
      $detail = "输出里有错误，见下面的尾部"
    } elseif ($p.expect -and $text -notmatch [regex]::Escape($p.expect)) {
      $status = "FAIL"
      $detail = "输出里没出现预期的那一行「$($p.expect)」"
    } else {
      $detail = "（按无错误判定）"
    }
  } else {
    $status = "FAIL"
    $detail = "没有找到「失败 N 项」这一行（脚本可能崩了）"
  }
  if ($code -ne 0 -and $status -eq "PASS") { $status = "WARN"; $detail = "$detail，退出码 $code" }

  if ($status -eq "FAIL") {
    $failed++
    Write-Host ("  {0,-16} FAIL  {1}" -f $p.name, $detail) -ForegroundColor Red
    Write-Host "  ---- 最后 25 行输出 ----" -ForegroundColor DarkGray
    $tail = $out | Select-Object -Last 25
    foreach ($line in $tail) { Write-Host ("    " + $line) -ForegroundColor DarkGray }
    Write-Host "  ------------------------" -ForegroundColor DarkGray
    Write-Host "  （完整重跑： & `$Godot --headless --path `$Project --script $file ）"
    Write-Host ""
  } elseif ($status -eq "WARN") {
    $warned++
    Write-Host ("  {0,-16} WARN  {1}" -f $p.name, $detail) -ForegroundColor Yellow
  } else {
    Write-Host ("  {0,-16} PASS  {1}" -f $p.name, $detail) -ForegroundColor Green
  }

  $results += [pscustomobject]@{ 探针 = $p.name; 结果 = $status; 说明 = $p.note; 详情 = $detail }
}

# ---------- 4. Node 写的两个静态自检（有 node 才跑）----------
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
  foreach ($script in @("tools/check_gdscript.mjs", "tools/validate_prelude.mjs")) {
    if (-not (Test-Path (Join-Path $Project $script))) { continue }
    Write-Host ("  {0,-16} 运行中…" -f (Split-Path $script -Leaf)) -NoNewline
    # 用 cmd 做输出重定向：某些受限环境里 PowerShell 把原生程序的输出接管会失败
    # （报 "Program 'node.exe' failed to run: Access is denied"），走 cmd 最稳。
    $log = Join-Path ([System.IO.Path]::GetTempPath()) ("xunxing_" + (Split-Path $script -Leaf) + ".log")
    & cmd /c "node `"$script`" > `"$log`" 2>&1"
    $code = $LASTEXITCODE
    Write-Host "`r"
    if ($code -eq 0) {
      Write-Host ("  {0,-16} PASS" -f (Split-Path $script -Leaf)) -ForegroundColor Green
      $results += [pscustomobject]@{ 探针 = (Split-Path $script -Leaf); 结果 = "PASS"; 说明 = "Node 静态自检"; 详情 = "" }
    } else {
      $failed++
      Write-Host ("  {0,-16} FAIL  退出码 {1}" -f (Split-Path $script -Leaf), $code) -ForegroundColor Red
      if (Test-Path $log) {
        Write-Host "  ---- 输出最后 15 行（完整日志： $log）----" -ForegroundColor DarkGray
        foreach ($line in (Get-Content $log -Tail 15 -Encoding UTF8)) { Write-Host ("    " + $line) -ForegroundColor DarkGray }
        Write-Host "  -----------------------------------------" -ForegroundColor DarkGray
      }
      $results += [pscustomobject]@{ 探针 = (Split-Path $script -Leaf); 结果 = "FAIL"; 说明 = "Node 静态自检"; 详情 = "退出码 $code" }
    }
  }
} else {
  Write-Host "  （没装 Node.js，跳过了 check_gdscript.mjs / validate_prelude.mjs）" -ForegroundColor DarkGray
}

# ---------- 5. 汇总 ----------
Write-Host ""
Write-Host "==================== 汇总 ===================="
$results | Format-Table -AutoSize
if ($failed -gt 0) {
  Write-Host "结果：$failed 个探针 FAIL —— 先查自己改了什么，不要放宽断言。" -ForegroundColor Red
  exit 1
}
if ($warned -gt 0) {
  Write-Host "结果：全部 PASS，但有 $warned 个 WARN（多半是基线项数变了，更新本脚本里的 base 即可）。" -ForegroundColor Yellow
  exit 0
}
Write-Host "结果：全部 PASS ✅" -ForegroundColor Green
exit 0
