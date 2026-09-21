# Windows

Windows 平台的脚本与配置归档库。所有内容按用途分类放在 `scripts/` 下，每个脚本都自带说明文档，可直接取用或拷到其他机器运行。

## 目录结构

| 目录 | 收录内容 |
| --- | --- |
| [`scripts/hotspot`](scripts/hotspot) | 移动热点开机自启、网络共享 |
| [`scripts/autostart`](scripts/autostart) | 开机自启、计划任务、登录触发 |
| [`scripts/network`](scripts/network) | 网络配置、代理、DNS、共享 |
| [`scripts/system`](scripts/system) | 系统设置、优化、电源与省电策略 |
| [`scripts/dev-env`](scripts/dev-env) | 开发环境搭建、运行时安装 |
| [`scripts/utils`](scripts/utils) | 零散小工具与一次性脚本 |

每个分类目录下都有独立的 `README.md`，说明该目录收录什么、脚本怎么用、遇到问题怎么排查。

## 快速开始

```powershell
git clone https://github.com/ALifeGuide/Windows.git
cd Windows
```

脚本多为 PowerShell，建议以管理员身份运行 Windows Terminal 或 PowerShell：

```powershell
Set-ExecutionPolicy -Scope Process Bypass   # 仅对当前窗口生效，不改系统全局策略
.\scripts\hotspot\Enable-MobileHotspot.ps1
```

## 使用约定

1. **编码**：所有 `.ps1` 一律保存为 **UTF-8 with BOM**。PowerShell 5.1 读取无 BOM 的 UTF-8 会按 ANSI 解析，中文直接变乱码。仓库的 `.gitattributes` 已强制转换行符为 CRLF。
2. **不硬编码敏感信息**：脚本里不写明文密码、热点密钥、令牌。需要凭据时用参数传入，或读取系统已有配置。
3. **幂等**：常驻类脚本必须可重复执行，已处于目标状态就直接退出，避免高频巡检时反复开关。
4. **日志**：长期运行的脚本把输出写入日志文件，并做大小裁剪，避免无限增长。
5. **文档随行**：新增脚本必须同时更新所在目录的 `README.md` 和本文件的目录结构表。

## 运行环境

- Windows 10 1703 及以上 / Windows 11
- PowerShell 5.1（系统自带）或 PowerShell 7+
- 部分脚本需要管理员权限，对应 `README.md` 中会明确标注

## 安全说明

仓库为公开仓库，提交前请确认脚本中没有包含：内网地址与设备名、网卡 GUID、账号令牌、热点密码、个人路径。运行日志默认已被 `.gitignore` 排除。

## 许可

[MIT](LICENSE)
