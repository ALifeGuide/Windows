<#
    Enable-MobileHotspot.ps1
    用途：开机/登录后自动打开 Windows 移动热点（Mobile Hotspot）。

    实现方式：调用 Windows 运行时的 NetworkOperatorTetheringManager 接口，
    等同于在“设置 -> 网络和 Internet -> 移动热点”里手动打开开关；
    不模拟鼠标点击，也不依赖网卡支持传统的 netsh 承载网络
    （本机 Intel AC 9560 已确认不支持 hostednetwork，只能用这种方式）。

    特性：
      * 幂等：热点已开启时直接退出，不会重复开关 —— 因此可以安全地高频反复运行（巡检模式）。
      * 开机早于联网时会等待互联网连接就绪（默认最长 180 秒）。
      * 开启结果以轮询 TetheringOperationalState 为准（PS 5.1 读不到异步返回值）。
      * 失败自动重试（默认 3 次），日志超 200KB 自动裁剪。
      * 日志：%LOCALAPPDATA%\MobileHotspotAutostart\hotspot.log
#>

[CmdletBinding()]
param(
    [int]$WaitForNetworkSeconds = 180,   # 等待互联网连接就绪的最长时间
    [int]$WaitForStartSeconds   = 45,    # 单次等待热点开启的最长时间
    [int]$RetryCount            = 3      # 失败重试次数
)

$ErrorActionPreference = 'Stop'

$LogDir  = Join-Path $env:LOCALAPPDATA 'MobileHotspotAutostart'
$LogFile = Join-Path $LogDir 'hotspot.log'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# 长期轮询会累积日志：超过 200KB 时只保留最后 300 行
try {
    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 200KB)) {
        $kept = Get-Content $LogFile -Tail 300 -Encoding UTF8
        Set-Content -Path $LogFile -Value $kept -Encoding UTF8
    }
} catch { }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Get-InternetProfile {
    try {
        return [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
    } catch {
        return $null
    }
}

function Get-State {
    param($Manager)
    try { return $Manager.TetheringOperationalState.ToString() } catch { return 'Unknown' }
}

Write-Log '===== 开始执行：自动开启移动热点 ====='

try {
    $null = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]
    $null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
} catch {
    Write-Log "加载 Windows 运行时接口失败：$($_.Exception.Message)" 'ERROR'
    exit 1
}

# ---------- 1) 等待互联网连接就绪（开机时 Wi-Fi 可能还没连上） ----------
$profile = $null
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $WaitForNetworkSeconds) {
    $profile = Get-InternetProfile
    if ($profile) { break }
    Start-Sleep -Seconds 5
}

if (-not $profile) {
    Write-Log "等待 $WaitForNetworkSeconds 秒仍未检测到可用的互联网连接，本次放弃（请检查是否处于飞行模式或 Wi-Fi 未连上）" 'ERROR'
    exit 1
}

try { $adapterName = $profile.NetworkAdapter.NetworkAdapterId.ToString() } catch { $adapterName = 'N/A' }
Write-Log "互联网连接就绪：$($profile.ProfileName)（网卡 $adapterName），等待耗时 $([int]$sw.Elapsed.TotalSeconds) 秒"

# ---------- 2) 检查是否允许共享网络 ----------
try {
    $cap = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::GetTetheringCapabilityFromConnectionProfile($profile)
    Write-Log "网络共享能力：$cap"
    if ($cap.ToString() -ne 'Enabled') {
        Write-Log "当前连接不允许共享网络（$cap），无法开启移动热点" 'ERROR'
        exit 1
    }
} catch {
    Write-Log "读取共享能力失败：$($_.Exception.Message)" 'WARN'
}

$manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)

# ---------- 3) 等待状态稳定后决定是否开启 ----------
$settle = [System.Diagnostics.Stopwatch]::StartNew()
while ($settle.Elapsed.TotalSeconds -lt 30) {
    $s = Get-State $manager
    if ($s -ne 'InTransition') { break }
    Start-Sleep -Seconds 2
}

for ($i = 1; $i -le $RetryCount; $i++) {
    $state = Get-State $manager
    Write-Log "第 $i 次尝试，当前状态：$state"

    if ($state -eq 'On') {
        Write-Log "移动热点已开启，无需操作（已连接设备 $($manager.ClientCount)/$($manager.MaxClientCount)）"
        exit 0
    }

    Write-Log '调用 StartTetheringAsync 开启移动热点...'
    try {
        $null = $manager.StartTetheringAsync()
    } catch {
        Write-Log "StartTetheringAsync 异常：$($_.Exception.Message)" 'ERROR'
    }

    # 只轮询状态：Off -> InTransition -> On
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw2.Elapsed.TotalSeconds -lt $WaitForStartSeconds) {
        Start-Sleep -Seconds 2
        $s2 = Get-State $manager
        if ($s2 -eq 'On') {
            Write-Log "移动热点开启成功，用时 $([int]$sw2.Elapsed.TotalSeconds) 秒，可连接设备上限 $($manager.MaxClientCount)"
            exit 0
        }
    }

    Write-Log "第 $i 次尝试后状态仍为 $(Get-State $manager)" 'WARN'
    Start-Sleep -Seconds 3
}

Write-Log "重试 $RetryCount 次后仍未能开启移动热点；请检查网卡驱动、飞行模式，或查看系统热点设置页是否有报错" 'ERROR'
exit 1
