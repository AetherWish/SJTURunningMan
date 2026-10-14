<h1 align="center">SJTU 一键校园跑工具</h1>

<div align="center">
  <img src="assets/SJTURM.png" alt="SJTURunningMan Logo" width="140" />
  <p><strong>轻量 · 实际路线预览 · 记录生成与上传流程研究</strong></p>

  <p>
    <img alt="Python" src="https://img.shields.io/badge/Python-3.x-3776AB?logo=python&amp;logoColor=white" />
    <img alt="PySide6" src="https://img.shields.io/badge/PySide6-Qt%20for%20Python-41CD52?logo=qt&amp;logoColor=white" />
    <img alt="Desktop" src="https://img.shields.io/badge/Desktop-v4.5.0-0078D4?logo=windows&amp;logoColor=white" />
    <img alt="Android" src="https://img.shields.io/badge/Android-v4.5.0-3DDC84?logo=android&amp;logoColor=white" />
    <img alt="iOS" src="https://img.shields.io/badge/iOS-v4.5.0-000000?logo=apple&amp;logoColor=white" />
    <img alt="HarmonyOS" src="https://img.shields.io/badge/HarmonyOS-v4.2.0-0FB4A9?logo=harmonyos&amp;logoColor=white" />
  </p>

  <p>
    <img alt="Route Preview" src="https://img.shields.io/badge/Route%20Preview-OpenStreetMap-D97706" />
    <img alt="Routes" src="https://img.shields.io/badge/Routes-Default%20%2B%20Import-2A6F97" />
  </p>
</div>

<a href="https://app.repohistory.com/star-history">
  <picture>
    <source media="(prefers-color-scheme: dark)"
      srcset="https://app.repohistory.com/api/svg?repo=JackyTJie/SJTURunningMan_Advanced_Edition&type=Date&background=0D1117&color=62C3F8" />
    <source media="(prefers-color-scheme: light)"
      srcset="https://app.repohistory.com/api/svg?repo=JackyTJie/SJTURunningMan_Advanced_Edition&type=Date&background=FFFFFF&color=1F6FEB" />
    <img alt="Star History Chart"
      src="https://app.repohistory.com/api/svg?repo=JackyTJie/SJTURunningMan_Advanced_Edition&type=Date&background=0D1117&color=62C3F8" />
  </picture>
</a>

## 简介

本项目仅用于学习、研究和技术测试，主要用于理解运动数据记录与上传相关的技术流程。项目作者不鼓励、不支持任何违反学校规定的使用方式。请在使用前确认自己的行为符合 SJTU 及相关平台的要求，请不要用于伪造运动数据或规避体育锻炼要求。

电脑版提供跑步次数、时间、距离和路线等参数配置，便于进行流程研究、规则测试和结果复核。程序默认以昨日作为结束日期，向前生成指定次数的跑步记录（默认 1 次），每次跑步 4 km，时间为 `08:00:00`。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/Sample_Dark.webp" />
  <source media="(prefers-color-scheme: light)" srcset="assets/Sample_Bright.webp" />
  <img alt="Windows 主界面预览" src="assets/Sample_Bright.webp" />
</picture>

## 平台与文档

四个平台各自独立实现、独立发布。**按你的平台选对应文档**：

| 平台 | 版本 | 安装方式 | 文档 |
| --- | --- | --- | --- |
| **电脑版**（Windows / macOS / Linux） | `v4.5.0` | 下载 exe / dmg / deb 直接运行 | [docs/desktop.md](docs/desktop.md) |
| **macOS 安装** | `v4.5.0` | 需处理首次打开的 Gatekeeper 拦截 | [docs/macos.md](docs/macos.md) |
| **安卓** | `4.5.0` | 下载 APK 安装 | [docs/android.md](docs/android.md) |
| **iOS** | `4.5.0` | 用 Xcode 自行编译安装 | [docs/ios.md](docs/ios.md) |
| **鸿蒙 NEXT** | `4.2.0` | HAP + 调试证书安装 | [docs/harmonyos.md](docs/harmonyos.md) |

📖 **完整文档索引**：[docs/README.md](docs/README.md) ｜ 🌐 **English docs**：[docs/en/](docs/en/README.md)

## 项目速览

| 模块 | 当前状态 |
| --- | --- |
| 电脑版图形界面 | PySide6 轻量桌面版，版本 `v4.5.0`，背景图 + 玻璃拟态主题 |
| 路线预览 | 上传前离线预览（免登录）+ 上传中/后显示实际 payload 轨迹，>150 m 跳段红色高亮 |
| 路线规划器 | 电脑版 Leaflet + OpenStreetMap；移动端百度地图 |
| 路线选择 | 内置 `default.txt`，支持外部 txt 导入与持久化 |
| 上传流程 | 两步式（取认证 → 生成并上传），支持多天、可中途停止 |
| 移动端 | 安卓 `4.5.0`、iOS `4.5.0`、鸿蒙 `4.2.0`，功能对齐电脑版核心能力 |

## 下载

到 [Releases](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/releases) 获取各平台产物：

- **Windows / macOS / Linux / 安卓** —— 提供预编译包，下载即用；
- **iOS** —— 不提供预编译包，需自行用 Xcode 编译，见 [docs/ios.md](docs/ios.md)；
- **鸿蒙 NEXT** —— 不提供预编译包，需自行用 DevEco Studio 编译并签名，见 [docs/harmonyos.md](docs/harmonyos.md)。

## 文档导航

| 主题 | 文档 |
| --- | --- |
| 各平台使用指南 | [docs/](docs/README.md) |
| 路线规划与坐标系 | [docs/routes.md](docs/routes.md) |
| 从源码构建 | [docs/build.md](docs/build.md) |
| 测试指南 | [docs/testing.md](docs/testing.md) |
| 常见问题 | [docs/faq.md](docs/faq.md) |
| 版本更新日志 | [CHANGELOG.md](CHANGELOG.md) |
| 参与贡献 | [CONTRIBUTING.md](CONTRIBUTING.md) |
| 安全策略 | [SECURITY.md](SECURITY.md) |
| AI 助手仓库指南 | [AGENTS.md](AGENTS.md) |
| 致谢 | [docs/credits.md](docs/credits.md) |

## 重要提醒

- 避免选 1 km 距离（大概率最后不满 1 km），推荐 **2 km 及以上**；
- 电脑版单次距离上限 5 km，请合理设置，避免触发平台校验机制；
- 每次上传前建议先点「预览路线」，确认距离、跳段和起终点符合预期；
- 电脑版启动时需阅读并勾选承诺书；
- 内置路线暂仅保留 `default.txt`，`assets/Routes/NeedsReview/` 中的路线待校验后再恢复；
- 自定义路线 txt 格式为每行 `longitude,latitude`。

## 致谢

感谢 [@Labyrinth0419](https://github.com/Labyrinth0419)、[@accelerator-s](https://github.com/accelerator-s) 以及诸位贡献者。完整名单见 [docs/credits.md](docs/credits.md)。

## 免责声明

本工具仅供学习和研究目的，开发者不对因使用本工具造成的任何后果负责。请谨慎使用，并遵守所有适用的法律法规和学校规章制度。
