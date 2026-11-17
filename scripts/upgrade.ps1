#Requires -Version 7.0
<#
.SYNOPSIS
  dsh-superagent 上游/补丁更新后的本地同步脚本。
.DESCRIPTION
  将 deepseek-ai/dsh-superagent-prototype（upstream）的新提交，以「候选分支」方式合入
  自己的 fork（Robert-Wang-08/dsh-superagent-prototype），通过 clean-build + 测试闸门后
  才快进 main。不 force-push、不重写历史、不丢 fork 已发布提交（822e634 等）。
  默认（不带 -Apply）只 fetch 并报告上游是否领先，等价 DryRun。
.PARAMETER Apply
  实际执行升级。缺省为只读报告。
.PARAMETER SkipPush
  只做本地升级与测试，不 push origin。
.PARAMETER BumpParent
  升级成功后，在父仓提交新的 dsh-superagent gitlink 并推送。
.PARAMETER ForkPath
  fork 检出目录，默认 ../dsh-superagent。
.PARAMETER UpstreamRef
  要合入的上游引用，默认 upstream/main。
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$SkipPush,
  [switch]$BumpParent,
  [string]$ForkPath,
  [string]$UpstreamRef = 'upstream/main',
  [string]$Branch = 'main'
)
$ErrorActionPreference = 'Stop'
$env:GIT_TERMINAL_PROMPT = '0'

$patchRoot = Split-Path -Parent $PSScriptRoot          # .../dsh-superagent-patch
$parent    = Split-Path -Parent $patchRoot             # .../dsh（父仓根）
$fork      = if ($ForkPath) { (Resolve-Path $ForkPath).Path } else { Join-Path $parent 'dsh-superagent' }

function Invoke-Git([string]$repo, [string[]]$a) {
  $out  = & git --no-optional-locks -C $repo @a 2>&1
  $code = $LASTEXITCODE
  if ($code -ne 0) {
    $detail = ($out | Out-String).Trim()
    throw ("git -C {0} {1} 退出码 {2}: {3}" -f $repo, ($a -join ' '), $code, $detail)
  }
  return $out
}

Write-Host '== dsh-superagent 上游同步 =='
Write-Host "  fork     : $fork"
Write-Host "  patch 仓 : $patchRoot"
Write-Host "  upstream : $UpstreamRef  branch=$Branch  Apply=$Apply"

if (-not (Test-Path (Join-Path $fork '.git'))) { throw "fork 检出不存在：$fork" }

# 运行中服务警告（3082）
try {
  $listen = Get-NetTCPConnection -LocalPort 3082 -State Listen -ErrorAction SilentlyContinue
  if ($listen) { Write-Warning '检测到 3082 端口在监听（superagent 服务运行中）。升级会重建 lib/，建议先 stop 服务。' }
} catch {}

# 1) 工作区必须干净
$dirty = & git -C $fork status --porcelain
if ($dirty) { throw 'fork 工作区不干净，先提交或 stash 后再升级。' }

# 2) fetch origin + upstream
Write-Host 'fetch origin + upstream ...'
Invoke-Git $fork @('fetch','--prune','--quiet','origin')
Invoke-Git $fork @('fetch','--prune','--quiet','upstream')

# 3) 漂移检测（相对上游 + origin）
$base         = (Invoke-Git $fork @('merge-base',$UpstreamRef,$Branch)).Trim()
$forkAhead    = [int](Invoke-Git $fork @('rev-list','--count',"$UpstreamRef..$Branch"))
$upAhead      = [int](Invoke-Git $fork @('rev-list','--count',"$Branch..$UpstreamRef"))
$originAhead  = [int](Invoke-Git $fork @('rev-list','--count',"origin/$Branch..$Branch"))
$originBehind = [int](Invoke-Git $fork @('rev-list','--count',"$Branch..origin/$Branch"))
Write-Host ("  分叉基        = {0}" -f $base.Substring(0,7))
Write-Host ("  fork 领先上游 = {0} 提交" -f $forkAhead)
Write-Host ("  上游领先 fork = {0} 提交（需合入）" -f $upAhead)
Write-Host ("  origin 同步   = 领先 {0} / 落后 {1}" -f $originAhead, $originBehind)

if ($upAhead -eq 0) { Write-Host '已是最新，无需升级。'; exit 0 }
if (-not $Apply)  { Write-Host "DryRun 结束：上游领先 $upAhead 个提交，加 -Apply 执行升级。"; exit 0 }

# 3.4) 切回目标分支（fork 可能处于 detached HEAD，如 submodule 检出到 gitlink）
Invoke-Git $fork @('checkout',$Branch)

# 3.5) Apply 前：快进同步 origin/branch，吸收已发布的 fork 补丁（如 822e634），避免 push 非快进
if ($originAhead -gt 0) { throw "本地 $Branch 领先 origin/$Branch $originAhead 个提交（未推送本地提交），先手动处理" }
if ($originBehind -gt 0) {
  Write-Host ("本地 {0} 落后 origin/{0} {1} 个提交，快进同步" -f $Branch, $originBehind)
  Invoke-Git $fork @('merge','--ff-only',"origin/$Branch")
}

# 4) 候选分支 + merge upstream
$ts   = Get-Date -Format 'yyyyMMdd-HHmmss'
$cand = "upgrade/$ts"
Write-Host "== 候选分支 $cand =="
Invoke-Git $fork @('checkout','-B',$cand,$Branch)
try {
  Invoke-Git $fork @('merge','--no-edit',$UpstreamRef)
} catch {
  Write-Host "!! merge 冲突，已停在分支 $cand。解决后手动：git -C $fork add . ; git -C $fork commit"
  throw
}

# 5) 依赖 + clean-build + 测试闸门（pnpm check = typecheck + test + build）
Write-Host '== 安装依赖 =='
Push-Location $fork
try {
  & pnpm install
  if ($LASTEXITCODE -ne 0) { throw 'pnpm install 失败' }
  Write-Host '== clean-build + 类型检查 + 测试（pnpm check）=='
  & pnpm check
  if ($LASTEXITCODE -ne 0) { throw 'pnpm check 失败' }
} finally { Pop-Location }

# 6) 全绿后快进 main
Invoke-Git $fork @('checkout',$Branch)
Invoke-Git $fork @('merge','--ff-only',$cand)
Invoke-Git $fork @('branch','-d',$cand)
Write-Host ("已快进 {0} 到 {1}" -f $Branch, (Invoke-Git $fork @('rev-parse','--short','HEAD')).Trim())

# 7) push fork
if (-not $SkipPush) {
  Invoke-Git $fork @('push','origin',$Branch)
  Write-Host "已 push origin/$Branch"
}

# 8) 父仓 gitlink 回写（可选）
if ($BumpParent) {
  Invoke-Git $parent @('add','dsh-superagent')
  Invoke-Git $parent @('commit','-m','chore(superagent): 同步上游到 fork')
  Invoke-Git $parent @('push','origin','main')
  Write-Host '父仓 gitlink 已回写并推送。'
} else {
  Write-Host "提示：跨设备生效需回写父仓 gitlink：git -C $parent add dsh-superagent ; git -C $parent commit ; git push"
}
Write-Host '完成。'
