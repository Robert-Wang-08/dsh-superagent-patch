#Requires -Version 7.0
<#
.SYNOPSIS
  用 patch 仓的本地覆盖补丁生成 dsh-superagent 的 lib，并保持 fork 源码干净。
.DESCRIPTION
  patches/*.patch 是已经在 fork 历史里的存档，这里不重复套用。
  patches/overlay/*.patch 是尚未进入 fork 的本机覆盖。脚本先要求 fork 工作区干净，
  再临时套上 overlay、执行 pnpm build，最后把跟踪文件还原。lib/ 与 node_modules/ 被
  .gitignore 忽略，所以生成的包留在检出目录里，git status 仍然干净。
.PARAMETER ForkPath
  fork 检出目录。默认是本仓上一级的 dsh-superagent（父仓子模块）。
#>
[CmdletBinding()]
param(
  [string]$ForkPath
)
$ErrorActionPreference = 'Stop'

$patchRoot = Split-Path -Parent $PSScriptRoot
$parent = Split-Path -Parent $patchRoot
$fork = if ($ForkPath) { (Resolve-Path $ForkPath).Path } else { Join-Path $parent 'dsh-superagent' }
$overlayDir = Join-Path $patchRoot 'patches\overlay'

if (-not (Test-Path (Join-Path $fork '.git'))) { throw "fork 检出不存在：$fork" }
if (-not (Test-Path $overlayDir)) { throw "没有 overlay 目录：$overlayDir" }

$dirty = @(git -C $fork status --porcelain --untracked-files=no)
if ($dirty.Count -gt 0) {
  throw ("fork 有未提交的跟踪改动，先还原后再打包：`n" + ($dirty -join "`n"))
}

$patches = @(Get-ChildItem -Path $overlayDir -Filter '*.patch' | Sort-Object Name)
if ($patches.Count -eq 0) { throw "overlay 目录没有补丁：$overlayDir" }

$restored = $false
function Restore-Fork {
  if ($restored) { return }
  git -C $fork checkout -- . | Out-Null
  if ($LASTEXITCODE -ne 0) { throw '还原 fork 跟踪文件失败' }
  $script:restored = $true
}

try {
  foreach ($patch in $patches) {
    git -C $fork apply --check -- $patch.FullName
    if ($LASTEXITCODE -ne 0) { throw ("补丁套不上当前 fork：$($patch.Name)") }
    git -C $fork apply -- $patch.FullName
    if ($LASTEXITCODE -ne 0) { throw ("打补丁失败：$($patch.Name)") }
    Write-Host ("applied " + $patch.Name)
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
