# 移动热点开机自启

开机或登录后自动打开 Windows 移动热点，并周期巡检保持开启状态。全程不模拟鼠标点击，也不需要网卡支持传统的承载网络。

- **脚本**：`Enable-MobileHotspot.ps1`
- **需要管理员权限**：是（注册计划任务时）；脚本本体在已注册任务下由系统以最高权限运行
- **适用**：Windows 10 1703+ / Windows 11

## 为什么不用 `netsh wlan start hostednetwork`

`netsh wlan` 走的是旧式承载网络 API，Intel AC 9560 等现代网卡上 `netsh wlan show drivers` 直接返回「不支持的承载网络: 否」，命令必然失败。

正确做法是调用 Windows Runtime 的 `NetworkOperatorTetheringManager`，它与「设置 → 网络和 Internet → 移动热点」里的开关完全等价，可无人值守运行。

## 脚本特性

| 特性 | 说明 |
| --- | --- |
| 幂等 | 热点已是 `On` 就立即退出，不重复开关，因此可安全地被高频反复调用 |
| 等待联网 | 开机时 Wi-Fi 可能还没连上，默认最多等待 180 秒 |
| 结果判定 | PowerShell 5.1 读不到 WinRT 异步返回值，改为轮询 `TetheringOperationalState`（`Off` → `InTransition` → `On`）判定 |
| 自动重试 | 默认失败重试 3 次，每次最长等待 45 秒 |
| 日志裁剪 | 超过 200KB 时只保留最后 300 行，长期巡检不会撑爆磁盘 |

### 参数

```powershell
.\Enable-MobileHotspot.ps1 -WaitForNetworkSeconds 180 -WaitForStartSeconds 45 -RetryCount 3
```

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| `-WaitForNetworkSeconds` | 180 | 等待互联网连接就绪的最长时间 |
| `-WaitForStartSeconds` | 45 | 单次等待热点开启的最长时间 |
| `-RetryCount` | 3 | 失败重试次数 |

### 日志

```
%LOCALAPPDATA%\MobileHotspotAutostart\hotspot.log
```

## 安装：注册为计划任务

先确认脚本的最终存放位置，例如 `C:\Scripts\Enable-MobileHotspot.ps1`，然后**以管理员身份**执行：

```powershell
$script = 'C:\Scripts\Enable-MobileHotspot.ps1'   # 改成你的实际路径

$a  = New-ScheduledTaskAction -Execute 'powershell.exe' `
     -Argument "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
$t1 = New-ScheduledTaskTrigger -AtStartup
$t2 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$pr = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest

# 第一步：只用最小参数注册
Register-ScheduledTask -TaskName 'AutoMobileHotspot' -Action $a -Trigger @($t1,$t2) -Principal $pr -Force

# 第二步：再补设置
$st = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
      -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
      -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
Set-ScheduledTask -TaskName 'AutoMobileHotspot' -Settings $st
```

### 几个关键点

- **必须分两步注册**。一次带上 `-Description`（尤其含中文）、`-Settings`、`-Principal` 的 `Register-ScheduledTask` 可能直接失败（进程退出码 -1）。
- **`-LogonType S4U`** 表示「无论用户是否登录都运行」，且**不保存明文密码**。已实测：S4U 非交互会话下 WinRT 热点接口完全可用。
- **周期巡检靠 `-Once + -RepetitionInterval`**，`-AtStartup` 触发器本身不支持重复；`RepetitionDuration` 留空即无限期重复。
- **`-MultipleInstances IgnoreNew`** 防止巡检间隔短于脚本最长耗时（180s 联网等待 + 3×45s 重试）时任务叠加。
- 任务执行程序会自动适配 `powershell.exe` / `pwsh.exe`，取决于注册时使用的宿主。

## 验证

```powershell
Start-ScheduledTask -TaskName 'AutoMobileHotspot'
Start-Sleep 10
Get-Content "$env:LOCALAPPDATA\MobileHotspotAutostart\hotspot.log" -Tail 20
```

看到 `移动热点已开启` 即成功。日志形如：

```
2026-09-21 15:03:17 [INFO] ===== 开始执行：自动开启移动热点 =====
2026-09-21 15:03:18 [INFO] 互联网连接就绪：某网络，等待耗时 0 秒
2026-09-21 15:03:19 [INFO] 网络共享能力：Enabled
2026-09-21 15:03:19 [INFO] 第 1 次尝试，当前状态：On
2026-09-21 15:03:19 [INFO] 移动热点已开启，无需操作（已连接设备 0/8）
```

真正验证「关闭 → 开启」那条路径会让已连接的设备短暂掉线，测试前先断开重要连接或征得使用者同意。

## 排障

| 现象 | 原因与处理 |
| --- | --- |
| 日志显示 `网络共享能力：DisabledByGroupPolicy` | 组策略禁用了网络共享，需联系管理员放开策略 |
| 显示 `DisabledBySku` | 当前 Windows 版本不支持，家庭版等需确认版本支持情况 |
| 一直卡在 `InTransition` | 等待即可；脚本已内置 30 秒状态稳定等待，若持续失败会重试 3 次 |
| 热点开一会儿自己关了 | 检查 `HKLM:\SYSTEM\CurrentControlSet\Services\icssvc\Settings` 的 `PeerlessTimeoutEnabled`，为 `1` 时系统会自动关热点，与「始终保持开启」的巡检互相打架；把它设为 `0` |
| `StartTetheringAsync` 报「不包含 GetResults 方法」 | PowerShell 5.1 读不到 WinRT 异步返回值，属正常现象；本脚本用轮询状态规避，不要去 await 异步结果 |
| 中文日志乱码 | 脚本必须存成 UTF-8 with BOM，无 BOM 会被 PS 5.1 按 ANSI 解析 |

`TetheringOperationalState` 取值：`Unknown=0`、`On=1`、`Off=2`、`InTransition=3`。

## 卸载

```powershell
Unregister-ScheduledTask -TaskName 'AutoMobileHotspot' -Confirm:$false
Remove-Item "$env:LOCALAPPDATA\MobileHotspotAutostart" -Recurse -Force
```
