# Campus Run — SJTU PE Running System
Use this skill when the user needs to interact with the SJTU PE running system — jAccount login, generating and uploading campus running data.

## Triggers
- "帮我跑步打卡" / "上传校园跑"
- "生成跑步数据" / "校园跑"
- "跑步记录" / "跑步签到"
- Any request to customize run date, time, or distance

## Instructions

**User tells the agent what they want** — the agent translates it into config and runs the upload. The agent handles all parameter parsing; the user does not need to know CLI flags.

Example user requests the agent handles:
- "帮我上传今天的校园跑，4公里"
- "上传昨天下午3点的跑步数据，距离2.5公里"
- "帮我打卡2026年6月20日早上7点半的跑步，跑5公里"

### How the agent should process user requests

The agent extracts the following from the user's natural language:
1. **Date** — default is yesterday if not specified. Parse relative terms like "今天" → today, "昨天" → yesterday, "前天" → day before yesterday, or explicit dates like "2026年6月20日"
2. **Time (hour + minute)** — default is 8:00 if not specified. Parse "早上7点半" → hour=7, minute=30; "下午3点" → hour=15, minute=0
3. **Distance** — default is 4.0 km if not specified. Parse "4公里" → 4.0, "2.5公里" → 2.5
4. **Times** — default is 1. Parse "跑3次" → 3

Then build the config and call `run_single()`:

```python
from campus_run import run_single, DEFAULT_CONFIG

config = dict(DEFAULT_CONFIG)
config["START_DATE"] = "2026-06-20"   # from user's request
config["RUN_HOUR"] = 7                 # from user's request
config["RUN_MINUTE"] = 30              # from user's request
config["RUN_DISTANCE_KM"] = 5.0       # from user's request
config["RUN_TIMES"] = 1                # from user's request

result = run_single("user", "pass", config)
```

The route is always `default.txt` (a fixed, pre-designed route around SJTU). The user does NOT design custom routes — they only specify date, time, distance, and number of runs.

CLI usage (for advanced/power users):
```bash
python scripts/campus_run.py upload --user xxx --pass xxx --times 1 --dist 4 --date 2026-06-20 --hour 8 --minute 0
python scripts/campus_run.py upload --user xxx --pass xxx --dist 2.5 --date 2026-06-19 --hour 15 --minute 30
```

Python API:
- `campus_run.login("user", "pass")` — jAccount OAuth login with auto CAPTCHA solving
- `campus_run.get_auth_token(session)` — obtain auth token and route rules
- `campus_run.generate_run_data(config, rules)` — generate realistic GPS tracks (uses `default.txt` route)
- `campus_run.upload_run(session, token, payload)` — upload run data
- `campus_run.run_single("user", "pass", config)` — full workflow in one call

Configuration keys:
| Key | Default | Description |
|-----|---------|-------------|
| `RUN_TIMES` | 1 | Number of runs |
| `RUN_DISTANCE_KM` | 4.0 | Target distance (km) |
| `RUN_HOUR` | 8 | Run hour (0-23) |
| `RUN_MINUTE` | 0 | Run minute (0-59) |
| `START_DATE` | yesterday | Run date as `"YYYY-MM-DD"` |
| `START_LONGITUDE` | 121.437 | Route start longitude |
| `START_LATITUDE` | 31.025 | Route start latitude |

## Dependencies
- Python packages: `pip install requests tenacity`
- CAPTCHA solver at `https://geek.sjtu.edu.cn/captcha-solver/` (requires campus network)
- Auto-installed on first run if missing

## Credentials Required
- **jAccount credentials** — set `JACCOUNT_USERNAME` and `JACCOUNT_PASSWORD` env vars, or pass via `--user`/`--pass` CLI flags
- Register at https://jaccount.sjtu.edu.cn

## Constraints
- 2FA (异地登录二次验证) requires manual intervention via the 交我办 app
- For educational and research purposes only — comply with SJTU regulations
