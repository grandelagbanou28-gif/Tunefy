#!/usr/bin/env python3
"""Muzo home stream server — resolves YouTube audio URLs via yt-dlp.

Contract used by the app (local yt-dlp server mode):
    GET /stream?videoId=<id>  ->  {"url": "..."}
    GET /health               ->  {"ok": true}
"""
import json
import logging
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOST = "0.0.0.0"
PORT = 8123
RESOLVE_TIMEOUT = 60
YTDLP = r"C:\flutter\s_potify\Muzo-v4\server\yt-dlp.exe"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
COOKIES_FILE = os.path.join(BASE_DIR, "cookies.txt")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)


def auth_args():
    """Authenticated extraction when cookies are available.

    cookies.txt (Netscape format) is preferred — exported once from a
    logged-in YouTube browser session. Else fall back to browser cookies if
    the server was started with --browser-cookies.
    """
    if os.path.exists(COOKIES_FILE):
        logging.info("Auth: using cookies.txt")
        return ["--cookies", COOKIES_FILE]
    if "--browser-cookies" in sys.argv:
        browser = os.environ.get("MUZO_BROWSER", "edge").lower()
        logging.info("Auth: trying --cookies-from-browser %s", browser)
        return ["--cookies-from-browser", browser]
    logging.info("Auth: anonymous (no cookies.txt found)")
    return []


def resolve(video_id):
    cmd = [YTDLP] + auth_args() + [
        "-f", "ba/best",
        "-g",
        "--no-playlist",
        "--no-warnings",
        "--socket-timeout", "20",
        video_id,
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=RESOLVE_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, "yt-dlp timed out"
    except Exception as e:
        return None, f"yt-dlp launch failed: {e}"
    if proc.returncode != 0:
        return None, (proc.stderr or proc.stdout).strip()[-600:]
    lines = [l.strip() for l in (proc.stdout or "").splitlines() if l.strip()]
    if not lines:
        return None, "yt-dlp returned no url"
    return lines[-1], None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        logging.info("%s - %s", self.client_address[0], fmt % args)

    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(200, {"ok": True})
            return
        if parsed.path == "/stream":
            params = parse_qs(parsed.query)
            vid = (params.get("videoId") or params.get("id") or [""])[0].strip()
            if not vid:
                self._json(400, {"error": "missing videoId"})
                return
            url, err = resolve(vid)
            if err:
                logging.warning("resolve %s failed: %s", vid, err)
                self._json(502, {"error": err})
            else:
                logging.info("resolved %s -> %s", vid, url[:90])
                self._json(200, {"url": url})
            return
        self._json(404, {"error": "not found"})
        return


if __name__ == "__main__":
    print(f"Muzo stream server on {HOST}:{PORT} — phone should use http://192.168.1.101:{PORT}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()