#Requires -Version 7.0
<#
.SYNOPSIS
  用 patch 仓的本地覆盖补丁生成 dsh-superagent 的 lib，并保持 fork 源码干净。
.DESCRIPTION
  patches/*.patch 是已经在 fork 历史里的存档，这里不重复套用。
  upstream.json 的 overlays 是对固定 fork 的本机覆盖。脚本先核对 fork HEAD
  等于 snapshot.commit，再要求工作区干净，然后临时套上尚未包含的 overlay、
  执行 pnpm build，最后把跟踪文件还原。absorbed_by 非空的条目要求该提交是 HEAD 的祖先，然后跳过。
  lib/ 与 node_modules/ 被 .gitignore 忽略，所以生成的包留在检出目录里，
  已跟踪源码保持无变更。
.PARAMETER ForkPath
  fork 检出目录。默认是仓库根的兄弟目录 dsh-superagent（固定版本，不是父仓子模块）。
#>
[CmdletBinding()]
param(
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
if (-not $manifest.snapshot -or -not $manifest.snapshot.commit) {
  throw 'upstream.json 缺少 snapshot.commit'
}
if (-not $manifest.overlays -or @($manifest.overlays).Count -eq 0) {
  throw 'upstream.json 没有 overlays'
}

$expected = [string]$manifest.snapshot.commit
$head = (git -C $fork rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw "无法读取 fork HEAD：$fork" }
$headShort = (git -C $fork rev-parse --short HEAD).Trim()
$expectedFull = (git -C $fork rev-parse --verify "$expected^{commit}").Trim()
if ($LASTEXITCODE -ne 0) {
  throw "fork 找不到清单保存点 $expected"
}
if ($head -ne $expectedFull) {
  throw ("fork HEAD 不是清单保存点。HEAD=$head ($headShort)，期望=$expectedFull。先对齐保存点再打包。")
}
Write-Host ("snapshot ok: " + $expectedFull.Substring(0, [Math]::Min(12, $expectedFull.Length)))

$dirty = @(git -C $fork status --porcelain --untracked-files=no)
if ($dirty.Count -gt 0) {
  throw ("fork 有未提交的跟踪改动，先还原后再打包：`n" + ($dirty -join "`n"))
}

$restored = $false
function Restore-Fork {
  if ($restored) { return }
  git -C $fork checkout -- . | Out-Null
  if ($LASTEXITCODE -ne 0) { throw '还原 fork 跟踪文件失败' }
  $script:restored = $true
}

try {
  foreach ($item in @($manifest.overlays)) {
    $rel = [string]$item.path
    if ([string]::IsNullOrWhiteSpace($rel)) { throw 'overlay 缺少 path' }
    $patchFile = Join-Path $patchRoot ($rel -replace '/', '\')
    if (-not (Test-Path -LiteralPath $patchFile)) { throw "补丁不存在：$patchFile" }
    $id = if ($item.id) { [string]$item.id } else { Split-Path -Leaf $patchFile }

    $absorbed = $null
    if ($null -ne $item.PSObject.Properties['absorbed_by'] -and $null -ne $item.absorbed_by -and "$($item.absorbed_by)" -ne '') {
      $absorbed = [string]$item.absorbed_by
    }

    if ($absorbed) {
      git -C $fork merge-base --is-ancestor $absorbed HEAD 2>$null
      if ($LASTEXITCODE -ne 0) {
        throw ("清单标成已被 $absorbed 吸收，但该提交不在当前 fork 历史里：$id")
      }
      Write-Host ("absorbed by $absorbed, skip $id")
      continue
    }

    git -C $fork apply --check -- $patchFile
    if ($LASTEXITCODE -eq 0) {
      git -C $fork apply -- $patchFile
      if ($LASTEXITCODE -ne 0) { throw ("打补丁失败：$id") }
      Write-Host ("applied $id")
      continue
    }
    git -C $fork apply --reverse --check -- $patchFile
    if ($LASTEXITCODE -eq 0) {
      Write-Host ("already in fixed fork, skip $id")
      continue
    }
    throw ("补丁套不上当前 fork：$id")
  }
  Push-Location $fork
  try {
    & pnpm build
    if ($LASTEXITCODE -ne 0) { throw 'pnpm build 失败' }
  } finally {
    Pop-Location
  }
} finally {
  Restore-Fork
}

$left = @(git -C $fork status --porcelain --untracked-files=no)
if ($left.Count -gt 0) { throw ("打包后 fork 仍有跟踪改动：`n" + ($left -join "`n")) }
Write-Host ("bundle ready: " + (Join-Path $fork 'lib'))
Write-Host 'fork 跟踪文件已还原'
