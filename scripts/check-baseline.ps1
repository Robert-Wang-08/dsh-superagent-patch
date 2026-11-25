#Requires -Version 7.0
<#
.SYNOPSIS
  只读检查：换到候选提交时，本地改动（archive 0001-0005 与 overlays）是否都还能落地。
.DESCRIPTION
  在临时 worktree 上按 archive → overlay 顺序逐条判定，能套上的会真的套进临时树，
  让后面的补丁看到前面的结果：
    present      对应提交（archive 的 adaptation_commits / overlay 的 absorbed_by）是候选的祖先，
                 或补丁可以反向套用
    needs-apply  补丁可以正向套上。换到这个候选时，它要作为 overlay 重放
    FAIL         两者都不行，需要先重写补丁
  无 FAIL 才打印 OK to retarget snapshot。不改固定检出工作区，不写 upstream.json。
  真正换保存点需另一次人工提交：改 snapshot.commit、各 overlay.base，
  并把 needs-apply 的 archive 补丁登记为 overlay。
.PARAMETER Candidate
  候选 commit（完整或短 SHA，或 origin/main 这类引用）。默认用清单 snapshot.commit。
.PARAMETER ForkPath
  fork 检出目录。默认是仓库根的兄弟目录 dsh-superagent。
#>
[CmdletBinding()]
param(
  [string]$Candidate,
  [string]$ForkPath
)
$ErrorActionPreference = 'Stop'

$patchRoot = Split-Path -Parent $PSScriptRoot
$parent = Split-Path -Parent $patchRoot
$fork = if ($ForkPath) { (Resolve-Path $ForkPath).Path } else { Join-Path (Split-Path -Parent $parent) 'dsh-superagent' }
$manifestPath = Join-Path $patchRoot 'upstream.json'

if (-not (Test-Path (Join-Path $fork '.git'))) { throw "fork 检出不存在：$fork" }
if (-not (Test-Path $manifestPath)) { throw "缺少清单：$manifestPath" }

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
if (-not $manifest.overlays) { throw 'upstream.json 没有 overlays' }

$target = if ($Candidate) { $Candidate.Trim() } else { [string]$manifest.snapshot.commit }
$targetFull = (git -C $fork rev-parse --verify "$target^{commit}").Trim()
if ($LASTEXITCODE -ne 0) { throw "找不到候选提交：$target" }

$entries = @()
$archive = @(Get-ChildItem -LiteralPath (Join-Path $patchRoot 'patches') -Filter '*.patch' -File | Sort-Object Name)
$commits = @($manifest.adaptation_commits)
for ($i = 0; $i -lt $archive.Count; $i++) {
  $entries += [pscustomobject]@{
    Id     = $archive[$i].BaseName
    Kind   = 'archive'
    File   = $archive[$i].FullName
    Commit = if ($i -lt $commits.Count) { [string]$commits[$i] } else { $null }
  }
}
foreach ($item in @($manifest.overlays)) {
  $absorbed = $null
  if ($null -ne $item.PSObject.Properties['absorbed_by'] -and "$($item.absorbed_by)" -ne '') {
    $absorbed = [string]$item.absorbed_by
  }
  $entries += [pscustomobject]@{
    Id     = [string]$item.id
    Kind   = 'overlay'
    File   = Join-Path $patchRoot (([string]$item.path) -replace '/', '\')
    Commit = $absorbed
  }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("dsh-sa-baseline-" + [guid]::NewGuid().ToString('N'))
$failed = @()
$needs = @()
try {
  git -C $fork worktree add --detach $work $targetFull 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "无法创建临时 worktree：$targetFull" }
  Write-Host ("candidate: " + $targetFull)

  foreach ($e in $entries) {
    if (-not (Test-Path -LiteralPath $e.File)) { throw "补丁不存在：$($e.File)" }
    $label = "{0,-8} {1}" -f $e.Kind, $e.Id

    if ($e.Commit) {
      git -C $fork merge-base --is-ancestor $e.Commit $targetFull 2>$null
      if ($LASTEXITCODE -eq 0) {
        Write-Host ("present      $label (commit $($e.Commit.Substring(0, [Math]::Min(7, $e.Commit.Length))) in history)")
        continue
      }
    }
    git -C $work apply -- $e.File 2>$null
    if ($LASTEXITCODE -eq 0) {
      Write-Host ("needs-apply  $label")
      $needs += $e.Id
      continue
    }
    git -C $work apply --reverse --check -- $e.File 2>$null
    if ($LASTEXITCODE -eq 0) {
      Write-Host ("present      $label (reverse applies)")
      continue
    }
    Write-Host ("FAIL         $label") -ForegroundColor Red
    $failed += $e.Id
  }
} finally {
  if (Test-Path -LiteralPath $work) {
    git -C $fork worktree remove --force $work 2>$null | Out-Null
    if (Test-Path -LiteralPath $work) {
      Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    git -C $fork worktree prune 2>$null | Out-Null
  }
}

if ($failed.Count -gt 0) {
  throw ("候选提交上这些本地改动套不上，先重写补丁：`n - " + ($failed -join "`n - "))
}
if ($needs.Count -gt 0) {
  Write-Host ("换到这个候选时需要作为 overlay 重放：" + ($needs -join ', '))
}
Write-Host 'OK to retarget snapshot'
