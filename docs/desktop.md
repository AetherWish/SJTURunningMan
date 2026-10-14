# 电脑版使用指南

适用于 Windows / macOS / Linux 桌面版，当前版本 **`v4.5.0`**（版本号来自 `src/config.py` 的 `global_version`）。

![电脑版主界面](./images/desktop-main.webp)

## 目录

- [1. 安装与启动](#1-安装与启动)
- [2. 界面总览](#2-界面总览)
- [3. 参数说明](#3-参数说明)
- [4. 路线预览](#4-路线预览)
- [5. 上传流程](#5-上传流程)
- [6. 数据生成逻辑](#6-数据生成逻辑)
- [7. 从源码运行](#7-从源码运行)
- [8. 打包](#8-打包)
- [9. 使用建议](#9-使用建议)

## 1. 安装与启动

### Windows

1. 到 [Releases](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/releases) 下载 `SJTURunningMan.exe`；
2. 双击运行。首次启动时 Windows SmartScreen 可能拦截 —— 点「更多信息」→「仍要运行」；
3. 程序为绿色版，无需安装，同目录会自动生成 `Routes/` 存放导入的路线。

### macOS

1. 下载 `SJTURunningMan-<版本>-macOS-universal.dmg`；
2. 挂载后把 `SJTURunningMan.app` 拖入「应用程序」。

首次打开会被 Gatekeeper 拦截，需要在 **系统设置 → 隐私与安全性** 里放行 —— **完整步骤与截图见 [macos.md](./macos.md)**。

> 要求 **macOS 14 或更高**；Apple Silicon 与 Intel 都在同一份 universal 包里，无需区分。

### Linux

下载 `.deb` 包后安装：

```bash
sudo dpkg -i SJTURunningMan_<版本>_linux.deb
```

## 2. 界面总览

启动后需要先阅读并勾选承诺书，之后进入主界面：

| 区域 | 内容 |
| --- | --- |
| 用户配置区 | JAccount 用户名、密码输入框（密码以星号隐藏） |
| 上传设置区 | 跑步次数、跑步时间、结束日期、跑步距离、预设路线 |
| 功能按钮 | 开始生成并上传、停止任务、设计/更新路线、预览路线、GitHub、水源、说明 |
| 实时反馈区 | 进度条、状态标签、启动警告/运行日志、路线预览摘要 |

界面采用背景图 + 玻璃拟态主题。

## 3. 参数说明

| 参数 | 格式 | 范围 / 默认 | 说明 |
| --- | --- | --- | --- |
| 用户名 | 文本 | — | JAccount 学号 |
| 密码 | 文本 | — | JAccount 密码，输入时星号隐藏 |
| 跑步次数 | 正整数 | 1–30，默认 1 | 生成多少条记录 |
| 跑步时间 | `HH:MM:SS` | 默认 `08:00:00` | 每条会加上 ±10 分钟、±30 秒的随机波动，更自然 |
| 结束日期 | `YYYY-MM-DD` | 默认昨天 | 以这天为最新一条，向前连续生成 |
| 跑步距离 | 数字（km） | 最大 5，默认 4 | 每条记录的目标距离 |
| 预设路线 | 下拉 | 内置 `default.txt` / 旧版 `user.txt` / 「自定义...」 | 鼠标滚轮不会误切换路线 |

所有输入都带格式校验，不合法会就地提示。

## 4. 路线预览

电脑版独有的能力：**上传前即可离线预览**。

**上传前离线预览**

1. 点「预览路线」；
2. 程序按当前距离与路线设置在本地跑一遍补点、分段、时间戳生成算法 —— **无需登录，不发起任何网络请求**；
3. 结果写入系统临时目录并用默认浏览器打开，在 OpenStreetMap 上显示路线连线、绿色起点、红色终点。

**上传中 / 上传后预览**

- 此时预览的是**已生成、准备上传的 payload 坐标**，而不是原始 txt 路线；
- 摘要显示距离、点数、时长、最长单段、跳段数量与上传状态；
- 单段大于 150 m 的跳段会红色高亮，用于发现路线文件或生成结果的异常。

![路线预览](./images/desktop-preview.webp)

> 预览用系统浏览器打开而不是内嵌 Qt WebEngine，是为了避免 Windows exe 体积显著增大。

## 5. 上传流程

**两步流程**

1. **获取认证信息** —— 取得认证令牌与跑步规则；
2. **生成并上传跑步数据** —— 逐条按配置生成轨迹数据并上传。

**多天支持**

- 数据生成在**过去** N 天（从昨天开始的连续 N 天），每天一个独立上传请求；
- 显示每条进度，统计成功/失败次数，可中途点「停止任务」中断。

**验证码**

- 实时验证码通过外部模型自动识别，无需手动输入。

**凭据校验**

- 可加 `--verify-credentials` 参数只验证凭据有效性、不上传数据，便于先确认账号可用。

## 6. 数据生成逻辑

- **路径调整**：按目标距离与速度自动伸缩路线。路线过长时会询问是否自动削减；过短则用往返或环路补齐。起终点距离大于 15 m 用往返策略，否则用环路。
- **GPS 校正**：自动应用坐标偏移校正以匹配地图数据，另含一层微调用于消除「地图上点选」与「实际记录」之间的偏差。
- **轨迹分段**：把整体轨迹拆成多段模拟真实跑步，各段分配正常 / 停止 / 无效状态，并生成合理的点时间戳。
- **本地透明**：预览在本地生成，不修改 payload 本身。

## 7. 从源码运行

```bash
git clone https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition.git
cd SJTURunningMan_Advanced_Edition

python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python qtui.py
```

依赖见 `requirements.txt`：PySide6 ≥ 6.5、requests ≥ 2.31、tenacity ≥ 8.2、urllib3 ≥ 1.26。Python 3.x 即可，CI 使用 3.14.6。

启动后：填写用户名密码 → 填参数 → 选路线 → 点「开始生成并上传」。

## 8. 打包

请使用仓库提供的 `main.spec` 或 `build_windows.ps1`，**不要**直接 `pyinstaller qtui.py`（那样会生成默认图标）。

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
```

脚本内部调用：

```powershell
python -m PyInstaller --clean --noconfirm .\main.spec
```

`main.spec` 会以 `assets/SJTURM.ico`（macOS 下 `assets/SJTURM.icns`）作为图标，并把整个 `assets/` 目录打进程序。三个平台的自动构建见 [`.github/workflows/release.yml`](../.github/workflows/release.yml)，打 `v*` tag 触发。

更多构建细节见 [build.md](./build.md)。

## 9. 使用建议

- 避免选 1 km 距离（大概率最后不满 1 km），推荐 **2 km 及以上**，结果更稳定；
- 单次距离上限 5 km，请合理设置，避免触发平台校验机制；
- 每次上传前先点「预览路线」，确认距离、跳段、起终点符合预期；
- 如需精确控制距离，多试几次找到最合适的设置；
- 自定义路线时保证路线长度与目标距离匹配，txt 格式为每行 `longitude,latitude`；
- 内置路线当前仅保留 `default.txt`，其余在 `assets/Routes/NeedsReview/` 待人工校验后再恢复 —— 详见 [routes.md](./routes.md)。
