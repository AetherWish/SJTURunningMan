#!/usr/bin/env python3
"""SJTU Campus Run — jAccount login + running data upload for PE system.

Extracted from SJTURunningMan. Removes all GUI — pure CLI/API module.
Use for understanding the sports upload flow and managing campus running data.

Usage::

    from campus_run import login, get_auth_token, generate_run_data, upload_run

    session = login("your-jaccount-user", "your-password")
    token, rules = get_auth_token(session)
    payload, dist, dur = generate_run_data(config, rules)
    result = upload_run(session, token, payload)

Or as CLI::

    python campus_run.py upload --user xxx --pass xxx --times 1 --dist 4
"""

from __future__ import annotations

import datetime
import json
import math
import os
import random
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote

import requests
from requests.adapters import HTTPAdapter

# Auto-install missing dependencies at import time
import subprocess as _sp, sys as _sys, importlib as _il
def _ensure(*packages):
    for pkg in packages:
        try: _il.import_module(pkg)
        except ImportError:
            _sp.check_call([_sys.executable, "-m", "pip", "install", pkg])

_ensure("requests", "tenacity")

# ══════════════════════════════════════════════════════════════════════════════
# Config helpers
# ══════════════════════════════════════════════════════════════════════════════

def _data_dir() -> Path:
    if os.name == "nt":
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        return Path(base) / "sjtu-skills" / "campus-run"
    return Path(os.environ.get("XDG_DATA_HOME",
               str(Path.home() / ".local" / "share"))) / "sjtu-skills" / "campus-run"

DATA_DIR = _data_dir()
CONFIG_PATH = DATA_DIR / "config.json"

EARTH_RADIUS_M = 6371000

DEFAULT_CONFIG = {
    "HOST": "pe.sjtu.edu.cn",
    "UID_URL": "https://pe.sjtu.edu.cn/pe/api/uaa/auth/v1/loginByJaccount",
    "MY_DATA_URL": "https://pe.sjtu.edu.cn/pe/api/data/v1/my/data",
    "POINT_RULE_URL": "https://pe.sjtu.edu.cn/pe/api/cloud/share/v1/passRule/pointRule/list",
    "UPLOAD_URL": "https://pe.sjtu.edu.cn/pe/api/data/v1/sports",
    "START_LONGITUDE": 121.437,
    "START_LATITUDE": 31.025,
    "RUN_TIMES": 1,
    "RUN_DISTANCE_KM": 4,
    "RUN_HOUR": 8,
    "RUN_MINUTE": 0,
    "RUN_SECOND": 0,
}


def _read_json(path: Path, default=None):
    if default is None: default = {}
    if not path.exists(): return default
    try: return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError): return default


def load_config() -> dict:
    cfg = dict(DEFAULT_CONFIG)
    cfg.update(_read_json(CONFIG_PATH, {}))
    return cfg


# ══════════════════════════════════════════════════════════════════════════════
# jAccount Login
# ══════════════════════════════════════════════════════════════════════════════

def _re_search(pattern, text):
    m = re.search(pattern, text)
    return m.group(1) if m else None


def _get_timestamp_ms():
    return str(round(time.time() * 1000))


def _create_session():
    session = requests.Session()
    session.headers = {"Referer": "https://jaccount.sjtu.edu.cn"}
    session.mount("http://", HTTPAdapter(max_retries=3))
    session.mount("https://", HTTPAdapter(max_retries=3))
    return session


def _solve_captcha() -> str:
    """Solve jAccount captcha via SJTU CAPTCHA solver API."""
    captcha_path = DATA_DIR / "captcha.jpeg"
    if not captcha_path.exists():
        return "0000"
    try:
        with open(captcha_path, "rb") as f:
            files = {"image": ("captcha.jpg", f, "image/jpeg")}
            resp = requests.post("https://geek.sjtu.edu.cn/captcha-solver/", files=files, timeout=15)
        return resp.json().get("result", "0000")
    except Exception:
        return "0000"


def login(username: str, password: str) -> requests.Session:
    """Login to jAccount via OAuth flow for PE system.

    Returns a requests.Session with auth cookies (JAAuthCookie).
    Raises RuntimeError on failure.
    """
    session = _create_session()

    auth_url = "https://jaccount.sjtu.edu.cn/oauth2/authorize"
    params = {
        "response_type": "code", "scope": "profile",
        "client_id": "9mqzULSXYgUYj5fPOpyL", "state": "8",
        "redirect_uri": "https://pe.sjtu.edu.cn/oauth2Login",
    }
    r = session.get(auth_url, params=params, allow_redirects=True, timeout=10)

    jalogin_url = None
    for resp in (r.history + [r]):
        if "jaccount.sjtu.edu.cn/jaccount/jalogin" in resp.url:
            jalogin_url = resp.url
            break
    if not jalogin_url:
        m = _re_search(r'''(https?://jaccount\.sjtu\.edu\.cn/jaccount/jalogin\?[^\s"'<>]+)''', r.text)
        if m: jalogin_url = m

    if not jalogin_url:
        raise RuntimeError("无法获取 jAccount 登录页面")

    login_resp = session.get(jalogin_url, timeout=10)
    login_page = login_resp.text

    # Check for 2FA requirement
    if "请进行二次验证" in login_page or "2faVerify" in login_page:
        raise RuntimeError("检测到异地登录需要二次验证，请通过交我办 APP 验证后重试")

    captcha_id = _re_search(r"img.src = 'captcha\?(.*)'", login_page)
    if captcha_id:
        captcha_url = f"https://jaccount.sjtu.edu.cn/jaccount/captcha?{captcha_id}{_get_timestamp_ms()}"
        captcha_resp = session.get(captcha_url, timeout=10)
        captcha_path = DATA_DIR / "captcha.jpeg"
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with open(captcha_path, "wb") as f:
            f.write(captcha_resp.content)

    captcha_code = _solve_captcha()

    sid = _re_search(r'sid: "(.*?)"', login_page)
    returl = _re_search(r'returl:"(.*?)"', login_page)
    se = _re_search(r'se: "(.*?)"', login_page)
    client = _re_search(r'client: "(.*?)"', login_page)
    uuid_val = _re_search(r'captcha\?uuid=(.*?)&t=', login_page)

    data = {
        "sid": sid, "returl": returl, "se": se, "client": client,
        "user": username, "pass": password, "captcha": captcha_code,
        "v": "", "uuid": uuid_val,
    }

    time.sleep(1)
    res = session.post("https://jaccount.sjtu.edu.cn/jaccount/ulogin", data=data, timeout=10)

    if "请进行二次验证" in res.text or "2faVerify" in res.text:
        raise RuntimeError("登录触发二次验证，请通过交我办 APP 完成验证")

    cookie_names = {c.name for c in session.cookies}
    if "JAAuthCookie" not in cookie_names:
        raise RuntimeError("登录失败，请检查用户名和密码")

    return session


# ══════════════════════════════════════════════════════════════════════════════
# API Client — get auth token + upload
# ══════════════════════════════════════════════════════════════════════════════

def _make_request(method, url, headers, params=None, data=None, session=None):
    if session:
        if method.upper() == "GET":
            resp = session.get(url, headers=headers, params=params, timeout=15)
        else:
            resp = session.post(url, headers=headers, data=data, timeout=15)
    else:
        if method.upper() == "GET":
            resp = requests.get(url, headers=headers, params=params, timeout=15)
        else:
            resp = requests.post(url, headers=headers, data=data, timeout=15)
    resp.raise_for_status()
    return resp.json()


def get_auth_token(session: requests.Session) -> tuple[str, dict]:
    """Get authorization token and point rules for campus run.

    Returns (auth_token, point_rules_data).
    """
    cfg = load_config()

    headers = {
        "Host": cfg["HOST"],
        "User-Agent": "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36",
        "Accept": "application/json, text/plain, */*",
        "X-Requested-With": "edu.sjtu.infoplus.taskcenter",
        "Referer": "https://pe.sjtu.edu.cn/phone/",
    }

    uid_data = _make_request("GET", cfg["UID_URL"], headers, session=session)
    if uid_data.get("code") != 0 or "uid" not in uid_data.get("data", {}):
        raise RuntimeError(f"获取认证失败: {uid_data}")
    auth_token = uid_data["data"]["uid"]

    lon = f"{cfg['START_LONGITUDE']:.14f}"
    lat = f"{cfg['START_LATITUDE']:.14f}"
    loc_param = f"{lon},{lat}"

    rule_headers = {
        "authorization": auth_token,
        "Host": cfg["HOST"],
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/140.0.0.0",
        "referer": f"{cfg['POINT_RULE_URL']}?location={quote(loc_param, safe='')}",
    }
    rule_data = _make_request(
        "GET", cfg["POINT_RULE_URL"] + f"?location={quote(loc_param, safe='')}",
        rule_headers, session=session,
    )

    return auth_token, rule_data.get("data", {})


def upload_run(session: requests.Session, auth_token: str,
               running_data: dict) -> dict:
    """Upload running data payload to PE system."""
    cfg = load_config()
    headers = {
        "Authorization": auth_token,
        "Content-Type": "application/json; charset=utf-8",
        "Host": cfg["HOST"],
        "User-Agent": "okhttp/4.10.0",
    }
    return _make_request(
        "POST", cfg["UPLOAD_URL"], headers,
        data=json.dumps(running_data), session=session,
    )


# ══════════════════════════════════════════════════════════════════════════════
# GPS Data Generation
# ══════════════════════════════════════════════════════════════════════════════

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two GPS points in meters."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlam/2)**2
    return EARTH_RADIUS_M * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))


def _read_route_coords(route_file: str = "") -> list[tuple[float, float]]:
    """Read GPS coordinates from a route file (format: lon,lat per line)."""
    if route_file and Path(route_file).exists():
        path = Path(route_file)
    else:
        default_route = DATA_DIR / "default.txt"
        if default_route.exists():
            path = default_route
        else:
            # Default: SiYuan Lake loop
            return [
                (121.437, 31.025), (121.4375, 31.0252), (121.438, 31.0255),
                (121.4382, 31.0258), (121.438, 31.026), (121.4375, 31.0258),
                (121.437, 31.0255), (121.4368, 31.0252), (121.437, 31.025),
            ]

    coords = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        parts = line.replace(",", " ").split()
        if len(parts) >= 2:
            try: coords.append((float(parts[0]), float(parts[1])))
            except ValueError: continue
    return coords


def generate_run_data(config: dict | None = None,
                      point_rules: dict | None = None) -> tuple[dict, float, float]:
    """Generate a single running data payload using the default.txt route.

    Returns (payload_dict, total_distance_km, total_duration_min).
    """
    cfg = config or load_config()
    rules = point_rules or {}

    target_km = cfg.get("RUN_DISTANCE_KM", 4)
    target_m = target_km * 1000

    run_hour = cfg.get("RUN_HOUR", 8)
    run_minute = cfg.get("RUN_MINUTE", 0)
    run_second = cfg.get("RUN_SECOND", 0)

    # Start time — yesterday by default
    start_dt = cfg.get("START_DATE")
    if start_dt:
        base = datetime.datetime.strptime(start_dt, "%Y-%m-%d")
    else:
        base = datetime.datetime.now() - datetime.timedelta(days=1)
    base = base.replace(hour=run_hour, minute=run_minute, second=run_second, microsecond=0)
    start_epoch_ms = int(base.timestamp() * 1000)

    # Always use default.txt route — route_file parameter removed
    coords = _read_route_coords()

    total_dist = 0.0
    for i in range(len(coords) - 1):
        total_dist += haversine_distance(coords[i][1], coords[i][0],
                                         coords[i+1][1], coords[i+1][0])

    # Scale: if route is too short, repeat; if too long, truncate
    laps_needed = max(1, math.ceil(target_m / total_dist)) if total_dist > 0 else 1
    scaled_coords = coords * laps_needed

    cum_dist = 0.0
    used_coords = [scaled_coords[0]]
    for i in range(1, len(scaled_coords)):
        seg = haversine_distance(scaled_coords[i-1][1], scaled_coords[i-1][0],
                                  scaled_coords[i][1], scaled_coords[i][0])
        if cum_dist + seg > target_m:
            break
        cum_dist += seg
        used_coords.append(scaled_coords[i])

    # Generate time-stamped track points (~5m apart, ~3 m/s speed)
    speed_ms = 3.0 + random.uniform(-0.3, 0.3)
    track_points = []
    elapsed_s = 0.0
    track_points.append({
        "longitude": used_coords[0][0], "latitude": used_coords[0][1],
        "timestamp": start_epoch_ms,
    })

    for i in range(1, len(used_coords)):
        seg_dist = haversine_distance(used_coords[i-1][1], used_coords[i-1][0],
                                       used_coords[i][1], used_coords[i][0])
        seg_time = seg_dist / speed_ms
        elapsed_s += seg_time

        num_intermediate = max(1, int(seg_dist / 5))
        for j in range(1, num_intermediate + 1):
            frac = j / num_intermediate
            lon = used_coords[i-1][0] + (used_coords[i][0] - used_coords[i-1][0]) * frac
            lat = used_coords[i-1][1] + (used_coords[i][1] - used_coords[i-1][1]) * frac
            t = start_epoch_ms + int((elapsed_s - seg_time + seg_time * frac) * 1000)
            track_points.append({"longitude": round(lon, 7), "latitude": round(lat, 7), "timestamp": t})

    total_duration_min = elapsed_s / 60
    actual_dist_km = cum_dist / 1000

    payload = {
        "sportType": 1,
        "startTime": start_epoch_ms,
        "endTime": track_points[-1]["timestamp"],
        "totalTime": int(elapsed_s),
        "totalDistance": int(cum_dist),
        "track": track_points,
    }

    return payload, actual_dist_km, total_duration_min


# ══════════════════════════════════════════════════════════════════════════════
# Full workflow
# ══════════════════════════════════════════════════════════════════════════════

def run_single(username: str, password: str,
               config: dict | None = None) -> dict:
    """Complete single-run workflow: login -> get token -> generate -> upload.

    Uses default.txt route. Customize date/time/distance via config.
    Returns: {success, message, response}
    """
    cfg = config or load_config()

    session = login(username, password)
    token, rules = get_auth_token(session)
    payload, dist, dur = generate_run_data(cfg, rules)
    result = upload_run(session, token, payload)

    if result.get("code") == 0:
        return {"success": True, "message": "上传成功", "distance_km": dist,
                "duration_min": dur, "response": result}
    else:
        return {"success": False, "message": f"上传失败: {result.get('message', result)}",
                "response": result}


# ══════════════════════════════════════════════════════════════════════════════
# CLI
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser(description="SJTU Campus Run — PE running data upload")
    p.add_argument("action", choices=["login", "upload"], default="upload", nargs="?")
    p.add_argument("--user", help="jAccount username")
    p.add_argument("--pass", dest="pwd", help="jAccount password")
    p.add_argument("--times", type=int, default=1, help="Number of runs (default: 1)")
    p.add_argument("--dist", type=float, default=4.0, help="Distance in km (default: 4)")
    p.add_argument("--date", help="Run date as YYYY-MM-DD (default: yesterday)")
    p.add_argument("--hour", type=int, default=8, help="Run hour 0-23 (default: 8)")
    p.add_argument("--minute", type=int, default=0, help="Run minute 0-59 (default: 0)")
    args = p.parse_args()

    user = args.user or os.environ.get("JACCOUNT_USERNAME", "")
    pwd = args.pwd or os.environ.get("JACCOUNT_PASSWORD", "")
    if not user or not pwd:
        print("请提供用户名和密码 (--user/--pass 或 JACCOUNT_USERNAME/JACCOUNT_PASSWORD 环境变量)")
        sys.exit(1)

    if args.action == "login":
        session = login(user, pwd)
        print(f"登录成功! JAAuthCookie: {session.cookies.get('JAAuthCookie', '?')[:30]}...")
    else:
        cfg = load_config()
        cfg["RUN_TIMES"] = args.times
        cfg["RUN_DISTANCE_KM"] = args.dist
        cfg["RUN_HOUR"] = args.hour
        cfg["RUN_MINUTE"] = args.minute
        if args.date:
            cfg["START_DATE"] = args.date
        for i in range(args.times):
            print(f"\n--- 第 {i+1}/{args.times} 次 ---")
            result = run_single(user, pwd, cfg)
            if result["success"]:
                print(f"  距离: {result['distance_km']:.2f} km, 时长: {result['duration_min']:.1f} 分钟")
                print("  上传成功")
            else:
                print(f"  上传失败: {result['message']}")
