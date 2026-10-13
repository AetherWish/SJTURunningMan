# 从源码构建

四个平台各自独立构建，互不依赖。改哪个平台就构建哪个。

| 平台 | 目录 | 工具链 | 产物 |
| --- | --- | --- | --- |
| 电脑版 | 仓库根 | Python + PyInstaller | `.exe` / `.dmg` / `.deb` |
| 安卓 | `apps/android/` | Gradle 9.4.1 + AGP 8.13.0 + Kotlin 2.2.10 | `.apk` / `.aab` |
| iOS | `apps/ios/` | Xcode 16+ | `.ipa` |
| 鸿蒙 | `apps/harmonyos/` | DevEco Studio / hvigor | `.hap` |

---

## 电脑版

### 准备环境

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 直接运行

```bash
python qtui.py
```

### 打包

**Windows**

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
```

**全平台（等价命令）**

```bash
python -m PyInstaller --clean --noconfirm ./main.spec
```

`main.spec` 要点：

- 入口 `qtui.py`，`assets/` 整目录打进程序；
- 图标 Windows 用 `assets/SJTURM.ico`，macOS 用 `assets/SJTURM.icns`；
- macOS 产物是 `universal2` 架构（Intel + Apple Silicon 通用）；
- 版本号从环境变量 `APP_VERSION` 注入，本地缺省 `4.5.0`。

> ⚠️ 不要直接 `pyinstaller qtui.py` —— 那会丢失图标与 `assets/` 资源。

### 自动发布流水线

[`.github/workflows/release.yml`](../.github/workflows/release.yml) 在推送 `v*` tag 或手动 `workflow_dispatch` 时触发，并行构建 Windows / macOS / Linux 三个产物并生成草稿 Release。Python 版本固定 3.14.6。

---

## 安卓

```bash
cd apps/android

# 调试包
./gradlew assembleDebug

# 发布包（需配置签名）
./gradlew assembleRelease
```

产物在 `app/build/outputs/apk/`。

- 包名 `com.sjtu.runner`，`minSdk = 26`、`targetSdk = 34`、`compileSdk = 34`；
- 版本号在 `app/build.gradle.kts` 的 `versionCode` / `versionName`；
- 未配置签名时 `assembleRelease` 产出的是未签名包。签名需要 `keystore` 相关属性（见 `app/build.gradle.kts` 的 `signingConfigs`）。

> 依赖版本集中在 `gradle/libs.versions.toml`（版本目录），改版本优先改那里。

## iOS

```bash
cd apps/ios
open SJTURunningMan.xcodeproj
```

在 Xcode 中配置 Team ID 与 Bundle ID 后构建，步骤详见 [ios.md](./ios.md#3-配置签名)。

命令行检查工程与 scheme：

```bash
xcodebuild -project apps/ios/SJTURunningMan.xcodeproj -list
```

## 鸿蒙

用 **DevEco Studio** 打开 `apps/harmonyos/` 工程，选择合适的签名后构建 HAP；也可以直接命令行构建：

**Windows**

```powershell
cd apps/harmonyos
.\hvigorw assembleHap
```

**macOS / Linux**

```bash
cd apps/harmonyos
./hvigorw assembleHap
```

工程里提交了 `hvigorw` / `hvigorw.bat` / `hvigorw.js` 包装脚本（与 DevEco Studio 自带的一致，仅 `hvigorw.js` 有一处本地补丁，见下）。脚本会自动找到 DevEco Studio 并推导出 `DEVECO_SDK_HOME` / `NODE_HOME` / `HVIGOR_TOOLS_HOME`：

- Windows（`hvigorw.bat`）：先看 `DEVECO_STUDIO_PATH`，再看 `%ProgramFiles%\Huawei\DevEco Studio` 与 `D:\HUAWEI\DevEco Studio`，最后查注册表 `HKCU/HKLM\Software\Huawei\DevEcoStudio` 与卸载信息里的 `InstallLocation`；
- macOS / Linux（`hvigorw`）：先看 `DEVECO_STUDIO_PATH`，再依次探测 `/Applications/DevEco-Studio.app/Contents`、`~/Applications/DevEco-Studio.app/Contents`、`/opt/deveco-studio`、`/usr/local/deveco-studio`、`~/deveco-studio`。

若探测不到，可手动指定（路径按本机实际安装位置调整）：

```powershell
$env:DEVECO_SDK_HOME  = 'D:\HUAWEI\DevEco Studio\sdk'
$env:NODE_HOME        = 'D:\HUAWEI\DevEco Studio\tools\node'
$env:HVIGOR_TOOLS_HOME = 'D:\HUAWEI\DevEco Studio\tools\hvigor'
cd apps/harmonyos
.\hvigorw assembleHap
```

> **`hvigorw.js` 的本地补丁**：原始文件位于 DevEco 的 `tools/hvigor/bin/`，它用 `path.resolve(__dirname, "..")` 推断 hvigor 安装目录（即 `tools/hvigor`）。把脚本搬进 `apps/harmonyos/` 后 `..` 会变成 `apps/`，导致包装脚本试图把不存在的 `apps/hvigor` 链进工程缓存并报 `EEXIST` / 生成空占位目录。补丁让该表达式优先使用 `HVIGOR_TOOLS_HOME`（变量存在且目录真实存在时才采用），否则**逐字节回落到原表达式**，因此其它安装布局、macOS 与 Linux 不受影响。升级 DevEco Studio 后需重新拷贝该文件并重新打这一处补丁（搜索 `HVIGOR_TOOLS_HOME` 即可定位）。

完全不走包装脚本时，仍可直接调用 DevEco 自带的 hvigor：

```powershell
$env:DEVECO_SDK_HOME = 'D:\HUAWEI\DevEco Studio\sdk'
& 'D:\HUAWEI\DevEco Studio\tools\node\node.exe' `
  'D:\HUAWEI\DevEco Studio\tools\hvigor\bin\hvigorw.js' `
  --mode module -p product=default assembleHap --no-daemon
```

- Bundle Name `com.sjtu.runner`，版本在 `AppScope/app.json5`（`versionName` 与安卓端保持一致）；
- 产物在 `entry/build/default/outputs/default/`；
- 未做开发者认证时，调试证书有效期很短，安装前请先完成认证（见 [harmonyos.md](./harmonyos.md#1-安装-hap-包)）。

---

## 清理本地构建残留

构建产物、虚拟环境等已在 `.gitignore` 中，但会占本地磁盘（`.venv/` 约 1.2 GB、`dist/` 约 238 MB、`build/` 约 86 MB、`apps/android/app/build/` 约 107 MB）。清理前**先 dry-run 确认要删什么**：

```bash
git clean -Xdn     # 预览：只列被 .gitignore 忽略的文件
git clean -Xdf     # 执行删除（不可恢复，确认无误再跑）
```

`-X` 只删被忽略的文件，不会碰你的源码改动。
