# 开机自启与计划任务

收录开机自启、登录触发、周期巡检类脚本。

## 收录标准

- 通过 Windows 任务计划程序注册（`ScheduledTasks` cmdlet 或 `schtasks.exe`）
- 或写入「启动」文件夹、注册表 `Run` 项实现自启

## 通用注意事项

- `Register-ScheduledTask` 先用最小参数（`-TaskName -Action -Trigger -Force`）注册，再用 `Set-ScheduledTask` 补设置，一次性带齐参数可能失败（退出码 -1）。
- `-LogonType S4U` 可实现「无论用户是否登录都运行」且**不保存明文密码**，优先于 `Interactive`。
- 周期重复必须靠 `-Once + -RepetitionInterval`，`-AtStartup` 触发器本身不支持重复。
- 常驻类脚本必须幂等，并做日志裁剪，避免高频运行时叠加或撑爆磁盘。

## 当前收录

暂无。移动热点自启的实现见 [`../hotspot`](../hotspot)。
