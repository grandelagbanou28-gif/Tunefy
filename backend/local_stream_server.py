"""Minimal, dependency-free yt-dlp stream resolver for the phone.

Why this exists
---------------
`https://tunefy-ytdlp.vercel.app` returns a YouTube URL that is locked to the
IP that produced it (`ip=` in the URL), and it has no relay mode: asking it to
stream (`?streamUrl=`) just re-answers the resolve JSON. Any other client than
the server itself therefore gets HTTP 403 on every track.

Resolving from the workstation fixes it, because the workstation and the phone
sit on the same network and share the same public IP — the IP-bound URL is
then valid on the phone too.

Usage:
    python backend/local_stream_server.py --port 9877
    adb reverse tcp:9877 tcp:9877
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
YT_DLP_BIN = os.environ.get("YT_DLP_BIN", "yt-dlp")
MEDIA_DIR = os.environ.get(
    "TUNEFY_MEDIA_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "media_cache")
)

# YouTube no longer serves any progressive (muxed) format: itag 18 is gone and
# everything left is adaptive-only. ExoPlayer — which video_player uses on
# Android — cannot play a bare DASH segment, so the only way to get a real
# picture is to download the best video track plus the best audio track and
# mux them into one MP4 here. Capped low on purpose: these are short clips, and
# a 4K merge would cost minutes and hundreds of megabytes for nothing.
VIDEO_FORMAT = (
    "bv*[height<=480][ext=mp4][vcodec^=avc1]+ba[ext=m4a]/"
    "bv*[height<=480][ext=mp4]+ba[ext=m4a]/"
    "b[height<=480][ext=mp4]/bv*+ba"
)
MERGE_TIMEOUT = 180

RUN_TIMEOUT = 45

_cache: dict[str, str] = {}
_cache_lock = threading.Lock()
# One merge at a time: yt-dlp + ffmpeg are CPU bound, and a shelf of clips
# resolving in parallel would starve the machine instead of going faster.
_merge_lock = threading.Lock()


def cache_key(video_id: str, kind: str) -> str:
    """Audio and video URLs of the same id are different resources."""
    return f"{kind}:{video_id}"


def resolve_audio(video_id: str) -> str:
    """Direct audio URL (no muxing needed — the player accepts adaptive audio)."""
    with _cache_lock:
        hit = _cache.get(cache_key(video_id, "audio"))
    if hit:
        return hit

    cmd = [
        YT_DLP_BIN,
        "--no-playlist",
        "-f",
        "bestaudio/best",
        "--get-url",
        "--no-warnings",
        "--socket-timeout",
        "15",
        "--",
        f"https://www.youtube.com/watch?v={video_id}",
    ]
    proc = subprocess.run(
        cmd, capture_output=True, timeout=RUN_TIMEOUT, text=True, encoding="utf-8", errors="replace"
    )
    url = _first_url(proc)
    with _cache_lock:
        _cache[cache_key(video_id, "audio")] = url
    return url


def resolve_video(video_id: str) -> str:
    """Mux video+audio into one MP4 on disk, return the URL that serves it.

    Served over `127.0.0.1` because the phone reaches this host through
    `adb reverse`, which is already required for the audio path. Using the
    workstation's LAN address instead would add a firewall dependency for no
    benefit.
    """
    os.makedirs(MEDIA_DIR, exist_ok=True)
    target = os.path.join(MEDIA_DIR, f"{video_id}.mp4")
    if not (os.path.exists(target) and os.path.getsize(target) > 0):
        with _merge_lock:
            # Re-checked under the lock: a queue of clips would otherwise all
            # download the same file at once.
            if not (os.path.exists(target) and os.path.getsize(target) > 0):
                tmp_dir = os.path.join(MEDIA_DIR, "parts")
                # A stale .part left by an interrupted run makes yt-dlp resume at
                # a byte the CDN no longer serves, which fails with HTTP 416.
                shutil.rmtree(tmp_dir, ignore_errors=True)
                os.makedirs(tmp_dir, exist_ok=True)
                cmd = [
                    YT_DLP_BIN,
                    "--no-playlist",
                    "-f",
                    VIDEO_FORMAT,
                    "--merge-output-format",
                    "mp4",
                    "--no-part",
                    "--no-continue",
                    "--no-warnings",
                    "--socket-timeout",
                    "15",
                    "-o",
                    os.path.join(tmp_dir, "%(id)s.%(ext)s"),
                    "--",
                    f"https://www.youtube.com/watch?v={video_id}",
                ]
                proc = subprocess.run(
                    cmd,
                    capture_output=True,
                    timeout=MERGE_TIMEOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                )
                produced = os.path.join(tmp_dir, f"{video_id}.mp4")
                if not (os.path.exists(produced) and os.path.getsize(produced) > 0):
                    err = (proc.stderr or "").strip().splitlines()
                    raise RuntimeError(
                        err[-1] if err else f"video mux failed ({proc.returncode})"
                    )
                os.replace(produced, target)
    with _cache_lock:
        _cache[cache_key(video_id, "video")] = f"http://127.0.0.1:9877/file/{video_id}.mp4"
    return f"http://127.0.0.1:9877/file/{video_id}.mp4"


def _first_url(proc) -> str:
    for line in (proc.stdout or "").strip().splitlines():
        line = line.strip()
        if line.startswith("http"):
            return line
    err = (proc.stderr or "").strip().splitlines()
    raise RuntimeError(err[-1] if err else f"yt-dlp exit {proc.returncode}")


class Handler(BaseHTTPRequestHandler):
    server_version = "TunefyLocalStream/1.0"

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib naming
        self._serve_media(head_only=True)

    def do_GET(self) -> None:  # noqa: N802 - stdlib naming
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(200, {"ok": True, "cached": len(_cache)})
            return
        if parsed.path == "/stream":
            video_id = (parse_qs(parsed.query).get("videoId") or [""])[0]
            kind = (parse_qs(parsed.query).get("kind") or ["audio"])[0]
            if not VIDEO_ID_RE.match(video_id):
                self._json(400, {"error": "invalid videoId"})
                return
            try:
                url = (
                    resolve_video(video_id)
                    if kind == "video"
                    else resolve_audio(video_id)
                )
                self._json(200, {"url": url})
            except subprocess.TimeoutExpired:
                self._json(504, {"error": "yt-dlp timeout"})
            except Exception as exc:  # noqa: BLE001 - reported to the caller
                self._json(502, {"error": str(exc)[:200]})
            return
        if parsed.path.startswith("/file/"):
            self._serve_media(head_only=False)
            return
        self._json(404, {"error": "not found"})

    def _serve_media(self, head_only: bool) -> None:
        """Serves a cached MP4 with Range support.

        Range is not optional: ExoPlayer opens the source, reads the moov
        atom, then asks for byte ranges as it seeks. Answering every request
        with the whole file makes seeking impossible and stalls playback.
        """
        name = os.path.basename(unquote(urlparse(self.path).path[len("/file/") :]))
        path = os.path.join(MEDIA_DIR, name)
        if not name or not os.path.isfile(path):
            self._json(404, {"error": "not found"})
            return

        size = os.path.getsize(path)
        start, end = 0, size - 1
        partial = False
        header = self.headers.get("Range")
        if header:
            m = re.match(r"bytes=(\d*)-(\d*)", header.strip())
            if m:
                partial = True
                if m.group(1):
                    start = int(m.group(1))
                    if m.group(2):
                        end = min(int(m.group(2)), size - 1)
                elif m.group(2):  # suffix range: last N bytes
                    start = max(0, size - int(m.group(2)))
        if start >= size:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.end_headers()
            return

        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head_only:
            return
        with open(path, "rb") as fh:
            fh.seek(start)
            remaining = end - start + 1
            while remaining > 0:
                chunk = fh.read(min(256 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[stream] " + (fmt % args) + "\n")


def _ensure_ffmpeg() -> None:
    """Put a real `ffmpeg` on PATH, or the video merge silently never runs.

    yt-dlp needs a binary *named* `ffmpeg`; the `imageio-ffmpeg` wheel ships
    `ffmpeg-win-x86_64-v7.1.exe`, and yt-dlp neither finds that nor merges
    anything — it downloads both tracks, prints no `[Merger]` line and exits 0,
    so the failure is invisible unless you read the whole log.
    """
    if os.environ.get("TUNEFY_SKIP_FFMPEG_SETUP"):
        return
    local_bin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ffmpeg_bin")
    exe = os.path.join(local_bin, "ffmpeg.exe")
    if not os.path.isfile(exe):
        try:
            import imageio_ffmpeg

            os.makedirs(local_bin, exist_ok=True)
            shutil.copyfile(imageio_ffmpeg.get_ffmpeg_exe(), exe)
        except Exception as exc:  # noqa: BLE001 - optional convenience
            print(f"[stream] ffmpeg unavailable ({exc}); video will not merge", flush=True)
            return
    os.environ["FFMPEG_LOCATION"] = local_bin
    os.environ["PATH"] = local_bin + os.pathsep + os.environ.get("PATH", "")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9877)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    _ensure_ffmpeg()
    os.makedirs(MEDIA_DIR, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"listening on http://{args.host}:{args.port}", flush=True)
    print(f"media cache: {MEDIA_DIR}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
