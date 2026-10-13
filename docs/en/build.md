# Building from Source

The four platforms build independently. Build only the one you changed.

| Platform | Directory | Toolchain | Artifact |
| --- | --- | --- | --- |
| Desktop | repository root | Python + PyInstaller | `.exe` / `.dmg` / `.deb` |
| Android | `apps/android/` | Gradle 9.4.1 + AGP 8.13.0 + Kotlin 2.2.10 | `.apk` / `.aab` |
| iOS | `apps/ios/` | Xcode 16+ | `.ipa` |
| HarmonyOS | `apps/harmonyos/` | DevEco Studio / hvigor | `.hap` |

---

## Desktop

### Environment

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### Run directly

```bash
python qtui.py
```

### Package

**Windows**

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
```

**All platforms (equivalent)**

```bash
python -m PyInstaller --clean --noconfirm ./main.spec
```

`main.spec` notes:

- Entry point `qtui.py`; the whole `assets/` directory is bundled.
- Icon is `assets/SJTURM.ico` on Windows, `assets/SJTURM.icns` on macOS.
- The macOS artifact is `universal2` (Intel + Apple Silicon).
- Version comes from the `APP_VERSION` environment variable, defaulting to `4.5.0` locally.

> ⚠️ Do not run `pyinstaller qtui.py` directly — you lose the icon and bundled assets.

### Automated release

[`.github/workflows/release.yml`](../../.github/workflows/release.yml) runs on `v*` tags or manual `workflow_dispatch`, builds Windows / macOS / Linux in parallel and creates a draft Release. Python is pinned to 3.14.6.

---

## Android

```bash
cd apps/android

# Debug build
./gradlew assembleDebug

# Release build (needs signing config)
./gradlew assembleRelease
```

Artifacts land in `app/build/outputs/apk/`.

- Package `com.sjtu.runner`, `minSdk = 26`, `targetSdk = 34`, `compileSdk = 34`.
- Version lives in `app/build.gradle.kts` (`versionCode` / `versionName`).
- Without a signing config, `assembleRelease` produces an unsigned package. Signing needs the keystore properties referenced in the `signingConfigs` block.

> Dependency versions are centralized in `gradle/libs.versions.toml` (version catalog) — bump them there.

## iOS

```bash
cd apps/ios
open SJTURunningMan.xcodeproj
```

Configure the Team ID and Bundle ID in Xcode, then build — see [ios.md](./ios.md#3-signing).

List the project and schemes from the command line:

```bash
xcodebuild -project apps/ios/SJTURunningMan.xcodeproj -list
```

## HarmonyOS

Open `apps/harmonyos/` in **DevEco Studio**, pick a signing profile and build the HAP. From the command line:

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

The repository ships the `hvigorw` / `hvigorw.bat` / `hvigorw.js` wrapper scripts (identical to the ones bundled with DevEco Studio, except for one local patch to `hvigorw.js` — see below). The wrapper locates DevEco Studio and derives `DEVECO_SDK_HOME` / `NODE_HOME` / `HVIGOR_TOOLS_HOME` from it:

- Windows (`hvigorw.bat`): `DEVECO_STUDIO_PATH`, then `%ProgramFiles%\Huawei\DevEco Studio` and `D:\HUAWEI\DevEco Studio`, then the registry (`HKCU/HKLM\Software\Huawei\DevEcoStudio` and the `InstallLocation` under the uninstall keys);
- macOS / Linux (`hvigorw`): `DEVECO_STUDIO_PATH`, then `/Applications/DevEco-Studio.app/Contents`, `~/Applications/DevEco-Studio.app/Contents`, `/opt/deveco-studio`, `/usr/local/deveco-studio`, `~/deveco-studio`.

If none of those are found, set them by hand (adjust to your install location):

```powershell
$env:DEVECO_SDK_HOME   = 'D:\HUAWEI\DevEco Studio\sdk'
$env:NODE_HOME         = 'D:\HUAWEI\DevEco Studio\tools\node'
$env:HVIGOR_TOOLS_HOME = 'D:\HUAWEI\DevEco Studio\tools\hvigor'
cd apps/harmonyos
.\hvigorw assembleHap
```

> **Local patch to `hvigorw.js`**: the original lives in DevEco's `tools/hvigor/bin/` and infers the hvigor install directory with `path.resolve(__dirname, "..")` (i.e. `tools/hvigor`). Copied into `apps/harmonyos/`, `..` becomes `apps/`, so the wrapper tries to link a non-existent `apps/hvigor` into its project cache and fails with `EEXIST` / empty placeholder directories. The patch makes that expression prefer `HVIGOR_TOOLS_HOME` (only when the variable is set and the directory exists) and otherwise fall back **byte-for-byte** to the original expression, so other install layouts, macOS and Linux are unaffected. After upgrading DevEco Studio, re-copy the file and re-apply the single change (search for `HVIGOR_TOOLS_HOME`).

To bypass the wrapper entirely, call DevEco's bundled hvigor directly:

```powershell
$env:DEVECO_SDK_HOME = 'D:\HUAWEI\DevEco Studio\sdk'
& 'D:\HUAWEI\DevEco Studio\tools\node\node.exe' `
  'D:\HUAWEI\DevEco Studio\tools\hvigor\bin\hvigorw.js' `
  --mode module -p product=default assembleHap --no-daemon
```

- Bundle name `com.sjtu.runner`; version in `AppScope/app.json5`.
- Without developer verification the debug certificate expires quickly — see [harmonyos.md](./harmonyos.md#1-installing-the-hap).

---

## Cleaning local build residue

Build outputs and the virtualenv are already gitignored, but they take local disk space (`.venv/` ~1.2 GB, `dist/` ~238 MB, `build/` ~86 MB, `apps/android/app/build/` ~107 MB). **Dry-run first:**

```bash
git clean -Xdn     # preview: lists only gitignored files
git clean -Xdf     # delete (irreversible — confirm before running)
```

`-X` only removes ignored files, so your source changes are untouched.
