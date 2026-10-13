# Testing Guide

## Current state

| Platform | Automated tests | Notes |
| --- | --- | --- |
| Android | ✅ Yes | Unit + instrumented tests, below |
| Desktop | ❌ None | Manual acceptance only |
| iOS | ❌ None | No test target |
| HarmonyOS | ❌ None | Manual acceptance only (see below) |
| CI | ❌ No tests | `release.yml` only packages |

**Additional tests are welcome** — see [CONTRIBUTING.md](../../CONTRIBUTING.md).

---

## Android

### Unit tests (no device needed)

```bash
cd apps/android
./gradlew test
```

Report: `app/build/reports/tests/testDebugUnitTest/index.html`

Existing cases:

| File | Coverage |
| --- | --- |
| `app/src/test/java/com/sjtu/runner/data/DataGeneratorTest.kt` | Route distance correction, truncate mode reaching target, full-loop mode, over-long route truncation, pace clamped to rules, payload matching the upload schema |
| `app/src/test/java/com/sjtu/runner/update/UpdateCheckerTest.kt` | Version parsing (prefix / prerelease), newer tag detected, older/equal ignored |

### Instrumented tests (device or emulator)

```bash
cd apps/android
./gradlew connectedAndroidTest
```

Case: `app/src/androidTest/java/com/sjtu/runner/AppInstrumentedTest.kt`.

### Adding a test

- Pure logic (data generation, version compare, coordinate math) → `app/src/test/`, JUnit 4.
- Anything needing a Context or UI → `app/src/androidTest/`, AndroidX JUnit + Espresso / Compose Test.

---

## Desktop manual checklist

Walk through this before submitting any desktop change.

**Startup**

- [ ] `python qtui.py` opens without a stack trace
- [ ] The commitment dialog appears and blocks until accepted
- [ ] Background and theme render correctly (no garbled text)

**Validation**

- [ ] Count `0` or `31` is rejected
- [ ] Time `8:00` (not `HH:MM:SS`) is rejected
- [ ] Date `2026/05/07` is rejected
- [ ] Distance `6` is rejected, `5` accepted

**Routes**

- [ ] The preset dropdown lists `default.txt`
- [ ] "Custom…" imports a txt and it appears in the dropdown
- [ ] Imported routes survive a restart
- [ ] Scrolling over the dropdown does not switch routes
- [ ] "Delete" removes imported routes but not `default.txt`

**Preview**

- [ ] "Preview route" works while **logged out**
- [ ] The browser map shows the track, green start and red finish
- [ ] A route with a > 150 m jump is highlighted red

**Upload**

- [ ] A 1-run, 2 km configuration completes successfully
- [ ] "Stop" interrupts without freezing the UI
- [ ] Logs stream per record, no uncaught exceptions

**Packaging**

- [ ] `python -m PyInstaller --clean --noconfirm ./main.spec` succeeds
- [ ] The artifact has the correct icon (not the PyInstaller default)
- [ ] The artifact launches and loads `assets/` correctly

---

## iOS manual checklist

- [ ] The project compiles in Xcode without warnings
- [ ] The login page brings up JAccount OAuth2
- [ ] "Start task" after configuring parameters fetches the UID
- [ ] The log scrolls live with per-record progress
- [ ] An expired session shows a working "re-login" button

---

## HarmonyOS manual checklist

After changing HarmonyOS code, build once with hvigor (see [build.md](./build.md#harmonyos)), then walk through this list:

**Startup and gate**

- [ ] `assembleHap` succeeds; the installed app starts with no jscrash
- [ ] First launch shows the full-screen "使用承诺书" card; "我承诺，进入软件" is disabled until the checkbox is ticked
- [ ] "退出" ends the app immediately; after accepting, a restart does not show the gate again

**Login**

- [ ] Tapping "JAccount 账号" on the account tab opens the login page; the Web page loads with a progress bar
- [ ] After login it returns automatically and the status card reads "已登录，点击可退出"
- [ ] Tapping the card opens the "退出账号" confirmation; confirming returns to the logged-out state

**Parameters**

- [ ] Runs offers 1/3/5/7/10/15/30; picking "自定义" and typing `0` / `31` clamps back into 1–30
- [ ] Start time edits hour/minute/second; hour caps at 23, minute and second at 59
- [ ] End date is selectable and defaults to yesterday
- [ ] Distance slider spans 1–5 km and the displayed value follows the drag

**Routes**

- [ ] The dropdown lists the built-in route plus custom routes (with point count and the "内置" marker)
- [ ] "设计新路线" opens the map page; after tapping points and saving it returns to the main page and a toast shows the point count
- [ ] Deleting a non-built-in route asks for confirmation; the built-in route cannot be deleted
- [ ] "预览路线" renders without being logged in (scatter plot plus distance / point / jump-count summary)

**Upload**

- [ ] A 1-run, 4 km configuration finishes and shows "任务完成: 成功 1 条，失败 0 条"
- [ ] The status card steps through 准备中 → 获取认证 → 生成数据 → 上传中 → 已完成 with the progress bar advancing
- [ ] "停止任务" interrupts a running task and the UI does not freeze
- [ ] The log is colour-coded per level (INFO/WARN/ERROR/SUCCESS), auto-scrolls to the bottom, and "清空" works
- [ ] When the selected route is longer than the target distance, "路线距离提醒" appears and all three buttons behave as their hint text says
- [ ] An expired cookie shows the top re-login banner; "登录" returns to the login page

**About and updates**

- [ ] The About page shows version `v4.5.0`, the disclaimer and the project credits
- [ ] "检查更新" reports either "已是最新版本" or "发现新版本"; on a weak network it shows "检查更新失败：…"
- [ ] The "仓库" and "水源" buttons open the browser

**Theme**

- [ ] After switching the system to dark mode, background / card / text contrast is correct with no white-on-white or black-on-black mismatches

---

## Before committing

```bash
# Android: make sure unit tests pass
cd apps/android && ./gradlew test

# General: confirm no build artifacts or local config got staged
git status
```

See the PR checklist in [CONTRIBUTING.md](../../CONTRIBUTING.md).
