# FAQ and Troubleshooting

## General

### Uploads fail — what now

This version tolerates off-campus login. If it still fails, work through these in order:

1. **Clear app data** — phone: **Settings → Apps → this app → Storage → Clear data + Clear cache**, then reopen and log in again.
2. **Check the cookie** — cookies expire within hours to days; log in again to refresh. When pasting manually, make sure nothing is missing.
3. **Check the network** — try WiFi vs mobile data, confirm the campus network is not blocking you.
4. **Wait** — the 交我办 servers may be down for maintenance; retry later.

### What should I set for a first run

**Count 1**, distance 2 km or more — verify the account and flow work before scaling up.

### Why avoid 1 km

The point-filling algorithm struggles to hit very short distances and may fall under 1 km. Use **2 km or more**.

### Multiple devices

Logging in the same account on several devices at once can invalidate the cookie. Don't keep several sessions alive simultaneously.

### Cookie safety

A cookie is a credential. **Never share it**, and never paste it into issues, logs or screenshots. See [SECURITY.md](../../SECURITY.md).

---

## Desktop

### Blocked by SmartScreen / Gatekeeper

- Windows: "More info" → "Run anyway".
- macOS: **System Settings → Privacy & Security** → "Open Anyway".

### Route preview doesn't open

- The preview HTML is written to a temp directory and handed to your default browser. Make sure one is configured.
- If security software blocks the temp directory, change it or temporarily disable the block.

### Packaged executable has no icon

You ran `pyinstaller qtui.py` instead of `main.spec`. Use the spec per [build.md](./build.md#package).

### Imported routes vanish after restart

Imported routes are copied into the `Routes/` folder **next to the executable**. If the app lives in a read-only location (e.g. `Program Files`), the write fails. Move it somewhere writable.

### Selecting "Custom…" does nothing

You must pick a `.txt` route in the file dialog. Files that are not one `longitude,latitude` pair per line are rejected.

---

## Android / HarmonyOS

### Can't install the APK / HAP

- **Android**: allow "unknown sources" in the install prompt.
- **HarmonyOS**: the debug certificate expires quickly — complete Huawei developer verification first.

### HarmonyOS can't launch 交我办

HarmonyOS does **not** support one-tap login; JAccount web login only. This is a platform limitation.

### Stuck on the login page

1. Confirm the phone can reach `pe.sjtu.edu.cn`.
2. Clear app data and retry.
3. If SJTU SSO is under maintenance, wait and retry.

---

## iOS

| Symptom | Fix |
| --- | --- |
| **"Failed to register bundle identifier"** | Make the bundle ID unique (see [ios.md](./ios.md#set-a-bundle-identifier-optional)) |
| **Won't install / "Untrusted Developer"** | iPhone: **Settings → General → VPN & Device Management** → tap your developer profile → Trust |
| **Login page won't load** | Ensure the iPhone has internet. The app uses JAccount OAuth2; if SJTU SSO is down, wait |
| **Cookie expired** | The app detects this and shows a "re-login" button — tap it |
| **Code signing errors** | Verify the Team ID and that Xcode → Settings → Accounts holds a valid certificate |
| **"No devices registered" (free account)** | Free accounts allow only 1–2 devices. Connect, build and run once and Xcode registers it — but you cannot share the app |

---

## Verifying a downloaded artifact

After downloading from Releases you can check two things.

### 1. Integrity — the file was not altered in transit

The release body lists a SHA256 for every artifact, and you can also download `SHA256SUMS.txt` and check against it:

```bash
# macOS / Linux: place it next to SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt
```

```powershell
# Windows PowerShell
Get-FileHash .\SJTURunningMan_<version>_windows.exe -Algorithm SHA256
```

Matching values mean the file is intact.

### 2. Build provenance — built by CI, not uploaded from someone's machine

Every artifact carries a **provenance attestation** issued by GitHub OIDC and bound to a specific commit and workflow run:

```bash
# requires gh CLI 2.49+: https://cli.github.com/
gh attestation verify SJTURunningMan_<version>_windows.exe \
  --repo JackyTJie/SJTURunningMan_Advanced_Edition
```

On success it prints the signing certificate and workflow information. **This attestation cannot be forged locally** — it proves the file was built by GitHub Actions running `release.yml` at that commit.

> Note: provenance only proves *how* something was built, not that the software is trustworthy — anyone able to trigger the workflow can also produce a valid attestation. The Android APK additionally carries a **self-signature** guaranteeing that updates from the same author install over older versions; the two are separate guarantees.

### File reported as damaged / won't open

Check the SHA256 first (step 1 above):

- **Matches** — the file is intact; the problem is almost certainly OS blocking (Windows SmartScreen, macOS Gatekeeper — see the entries below);
- **Doesn't match** — the download was corrupted; just download it again.

## Still stuck?

- Search [Issues](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/issues) first.
- Otherwise file one via the [bug template](https://github.com/JackyTJie/SJTURunningMan_Advanced_Edition/issues/new/choose) — and **redact**: no cookies, passwords, captchas, or real names/IDs.
- Security issues go through the private channel in [SECURITY.md](../../SECURITY.md), not a public issue.
