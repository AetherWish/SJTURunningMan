# SJTURunningMan

An iOS app that automates running result uploads to [pe.sjtu.edu.cn](https://pe.sjtu.edu.cn) — SJTU's physical education platform. Designed for students who need to complete running assignments.

## Features

- OAuth2 login via SJTU jAccount (WebView-based)
- Configurable parameters: running days, start time, date, target distance (1–5 km)
- Auto-generates realistic GPS track data with random pace variations
- Uploads running results in natural random segments

## Requirements

- **macOS** with **Xcode 16+** (iOS 26.5 SDK or later)
- An **Apple Developer account** (free or paid)
- An **iPhone** running iOS 18+ (or iOS 26.5+)

## Setup

### 1. Clone & open

```bash
git clone <repository-url>
cd SJTURunningMan_Advanced_Edition/IOS
open SJTURunningMan.xcodeproj
```

### 2. Set your Apple Developer Team ID

1. Open Xcode
2. In the project navigator, select the **SJTURunningMan** project (top-level)
3. Go to **Signing & Capabilities** tab
4. Under **Team**, select your team from the dropdown — Xcode will fill in your Team ID automatically

Or edit `SJTURunningMan.xcodeproj/project.pbxproj` and replace `YOUR_TEAM_ID` with your actual 10-character Apple Developer Team ID.

> **Where to find your Team ID:**
> Go to [developer.apple.com/account](https://developer.apple.com/account) → **Membership** → **Team ID** (top of the page).

### 3. Set your bundle identifier (optional)

The default bundle ID is `SJTU.SJTURunningMan`. If you're using a free Apple Developer account, you may need to change it to something unique (e.g. `com.yourname.SJTURunningMan`):

1. In Xcode, select the project → **Signing & Capabilities**
2. Change **Bundle Identifier** to something unique
3. Xcode will auto-generate the provisioning profile

## Build & Run on iPhone

### Option A: Via Xcode (simplest)

1. Connect your iPhone to your Mac via USB
2. In Xcode, select your iPhone as the build destination (top toolbar, next to the play button)
3. Click the **Play ▶** button (or `Cmd+R`)
4. On first run:
   - Xcode may prompt **"Enable Developer Mode on this iPhone?"** — tap **OK** on the phone, then go to **Settings → Privacy & Security → Developer Mode** and toggle it on, then restart the phone
   - If you're on a **free Apple Developer account**, you'll get a **"Failed to register bundle identifier"** error. Fix this by making the bundle ID unique (see Step 3 above).
   - You may need to **trust the developer certificate** on your iPhone: go to **Settings → General → VPN & Device Management → Developer App → Trust**

### Option B: Build archive for sideloading (no direct cable)

1. In Xcode, select **Product → Archive** (or `Cmd+Shift+K` to clean first if needed)
2. In the Archives organizer, select the archive and click **Distribute App**
3. Choose **"Custom" → "Export as .ipa"**
4. Save the `.ipa` file and install via your preferred sideloading tool (e.g., AltStore, SideStore)

## How to Use

1. **Login**: The app opens an SJTU jAccount OAuth2 login page. Log in with your SJTU credentials.
2. **Set parameters**: Configure running days, start time, date, distance.
3. **Start**: Tap **"开始任务"** (Start Task). The app will:
   - Fetch your user UID from the PE platform
   - Generate GPS track data based on the route coordinates
   - Randomize pace between 4–6 min/km
   - Upload track data for each day, one by one
4. **Monitor**: Watch the live log to see progress.
5. **Re-login**: If the session expires, the app will prompt you to re-login.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **"Failed to register bundle identifier"** | Change the bundle ID to something unique (see Setup step 3). |
| **App won't install / "Untrusted Developer"** | Go to **Settings → General → VPN & Device Management → tap your developer profile → Trust**. |
| **Login page won't load** | Make sure your iPhone has internet access. The app uses jAccount OAuth2 — if SJTU's SSO is down, wait and retry. |
| **Cookie expired** | The app detects this and shows a "重新登录" (re-login) button. Tap it to log in again. |
| **Build fails with code signing errors** | Ensure your Team ID is correct and you have a valid developer certificate in Xcode → Settings → Accounts. |
| **Xcode says "No devices registered" (free account)** | Free accounts can only run on 1–2 devices. Connect your iPhone, build & run once, and Xcode will register it automatically — but you can't share the app with others via a free account. |

## File Structure

```
IOS/
├── SJTURunningMan/
│   ├── SJTURunningManApp.swift      App entry point
│   ├── LoginView.swift              jAccount OAuth2 WebView
│   ├── MainView.swift               Parameter settings & UI
│   ├── MainViewModel.swift          Upload logic & state
│   ├── ApiService.swift             HTTP client (get UID, upload results)
│   ├── DataGenerator.swift          GPS track data generator
│   ├── GpsUtil.swift                GPS / coordinate utilities
│   └── route_coordinates            Pre-recorded route GPS points (SJTU campus)
├── SJTURunningMan.xcodeproj/        Xcode project
└── README.md                        This file
```

## License

For educational/personal use only. Use at your own risk — the author is not responsible for any consequences arising from automated uploads.