# Desktop Guide

For the Windows / macOS / Linux desktop build, currently **`v4.5.0`** (version comes from `global_version` in `src/config.py`).

![Desktop main window](../images/desktop-main.webp)

## Contents

- [1. Install and launch](#1-install-and-launch)
- [2. Interface overview](#2-interface-overview)
- [3. Parameters](#3-parameters)
- [4. Route preview](#4-route-preview)
- [5. Upload flow](#5-upload-flow)
- [6. Data generation](#6-data-generation)
- [7. Running from source](#7-running-from-source)
- [8. Packaging](#8-packaging)
- [9. Tips](#9-tips)

## 1. Install and launch

### Windows

1. Download `SJTURunningMan.exe` from [Releases](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/releases).
2. Double-click it. Windows SmartScreen may block the first launch — click "More info" → "Run anyway".
3. It is portable: no installation needed. A `Routes/` folder is created next to the executable for imported routes.

### macOS

1. Download `SJTURunningMan-<version>-macOS-universal.dmg`.
2. Mount it and drag `SJTURunningMan.app` into Applications.

The first launch is blocked by Gatekeeper and must be allowed from **System Settings → Privacy & Security** — **full steps with screenshots are in [macos.md](./macos.md)**.

> Requires **macOS 14 or later**; the universal build covers both Apple Silicon and Intel.

### Linux

Install the `.deb`:

```bash
sudo dpkg -i SJTURunningMan_<version>_linux.deb
```

## 2. Interface overview

On first launch you must read and accept the commitment dialog. After that:

| Area | Contents |
| --- | --- |
| Account | JAccount username and password (masked) |
| Upload settings | Count, time, end date, distance, preset route |
| Buttons | Start, Stop, Design/Update route, Preview route, GitHub, Shuiyuan, About |
| Feedback | Progress bar, status label, warning/log panel, route preview summary |

The UI uses a background image with a glassmorphism theme.

## 3. Parameters

| Parameter | Format | Range / default | Notes |
| --- | --- | --- | --- |
| Username | text | — | JAccount ID |
| Password | text | — | Masked input |
| Count | positive integer | 1–30, default 1 | Number of records to generate |
| Time | `HH:MM:SS` | default `08:00:00` | Each run gets ±10 min / ±30 s of random jitter |
| End date | `YYYY-MM-DD` | default yesterday | Latest record; earlier ones are generated backwards |
| Distance | number (km) | max 5, default 4 | Target distance per record |
| Preset route | dropdown | built-in `default.txt` / legacy `user.txt` / "Custom…" | Mouse wheel will not accidentally switch routes |

All inputs are validated with inline feedback.

## 4. Route preview

Desktop-only: **preview before you upload**.

**Offline pre-upload preview**

1. Click "Preview route".
2. The app runs the full point-filling, segmentation and timestamp pipeline locally — **no login, no network**.
3. The result is written to a temp file and opened in your default browser on OpenStreetMap, showing the track with a green start and red finish.

**Preview during/after upload**

- This previews the **generated payload coordinates** rather than the raw txt route.
- The summary shows distance, point count, duration, longest segment, jump-segment count and upload status.
- Segments longer than 150 m are highlighted in red to expose bad route files or generation results.

![Route preview](../images/desktop-preview.webp)

> The preview opens in the system browser instead of embedding Qt WebEngine, to keep the Windows executable small.

## 5. Upload flow

**Two steps**

1. **Fetch auth** — obtain the token and running rules.
2. **Generate and upload** — generate each track and upload it.

**Multiple days**

- Data is generated for the **past** N days (N consecutive days ending yesterday), one request per day.
- Progress per record, success/failure counters, and a working "Stop" button.

**Captcha**

- Live captchas are solved automatically via an external model.

**Credential check**

- Pass `--verify-credentials` to validate the account without uploading anything.

## 6. Data generation

- **Path adjustment** — the route is scaled to the target distance and pace. If the route is too long you are asked whether to truncate; if too short, an out-and-back or loop strategy extends it. Start and finish more than 15 m apart use out-and-back, otherwise a loop.
- **GPS correction** — an automatic offset correction aligns coordinates with the map, plus a second fine adjustment for the gap between map-picked and recorded points.
- **Segmentation** — the track is split into segments to mimic real running, each tagged normal / stopped / invalid, with plausible timestamps.
- **Local transparency** — previews are generated locally and never mutate the payload.

## 7. Running from source

```bash
git clone https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition.git
cd SJTURunningMan_Advanced_Edition

python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python qtui.py
```

Dependencies (`requirements.txt`): PySide6 ≥ 6.5, requests ≥ 2.31, tenacity ≥ 8.2, urllib3 ≥ 1.26. Any Python 3.x works; CI uses 3.14.6.

## 8. Packaging

Use the provided `main.spec` or `build_windows.ps1` — do **not** run `pyinstaller qtui.py` directly, or you will get the default icon and no bundled assets.

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
```

which calls:

```powershell
python -m PyInstaller --clean --noconfirm .\main.spec
```

`main.spec` uses `assets/SJTURM.ico` (`assets/SJTURM.icns` on macOS) as the icon and bundles the whole `assets/` directory. Automated builds for all three platforms live in [`.github/workflows/release.yml`](../../.github/workflows/release.yml), triggered by `v*` tags.

See [build.md](./build.md) for details.

## 9. Tips

- Avoid a 1 km target — the route often cannot reach it. Use **2 km or more**.
- Max distance is 5 km; keep it reasonable to avoid tripping platform checks.
- Always run "Preview route" first and check distance, jump segments and endpoints.
- Precise distance control may need a few attempts.
- Custom routes should match the target distance. Format: one `longitude,latitude` per line.
- Only `default.txt` ships as a built-in route; the rest wait in `assets/Routes/NeedsReview/` — see [routes.md](./routes.md).
