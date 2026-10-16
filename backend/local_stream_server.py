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
import atexit
import faulthandler
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

# Enable faulthandler to get tracebacks on crashes
faulthandler.enable()

# Global executor for yt-dlp/ffmpeg work - limits concurrent jobs
_EXECUTOR = ThreadPoolExecutor(max_workers=2, thread_name_prefix="yt-dlp-")
# Track active subprocesses for cleanup
_ACTIVE_PROCESSES: list[subprocess.Popen] = []
_ACTIVE_LOCK = threading.Lock()

# Track server start time for health checks
_SERVER_START_TIME = time.time()

def _cleanup_processes() -> None:
    """Terminate all tracked subprocesses on exit."""
    with _ACTIVE_LOCK:
        for proc in _ACTIVE_PROCESSES:
            try:
                if proc.poll() is None:
                    proc.terminate()
            except Exception:
                pass
        # Give processes a moment to terminate gracefully
        time.sleep(0.5)
        for proc in _ACTIVE_PROCESSES:
            try:
                if proc.poll() is None:
                    proc.kill()
            except Exception:
                pass

atexit.register(_cleanup_processes)

# Track active subprocesses
def _track_process(proc: subprocess.Popen) -> None:
    with _ACTIVE_LOCK:
        _ACTIVE_PROCESSES.append(proc)

def _untrack_process(proc: subprocess.Popen) -> None:
    with _ACTIVE_LOCK:
        if proc in _ACTIVE_PROCESSES:
            _ACTIVE_PROCESSES.remove(proc)

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

# Kept under the phone's 28 s wait for this endpoint: a resolution that ran
# past it produced a verdict the client could never receive, so the app logged
# "no relay" and re-queued the same dead id forever.
RUN_TIMEOUT = 20

_cache: dict[str, tuple[str, float]] = {}
_cache_lock = threading.Lock()
# googlevideo links handed to the phone expire quickly (and 403 outright once
# reused), so a cached answer older than this must be re-resolved instead of
# served — that is exactly the "the relay answered but the song failed" case.
CACHE_TTL = 1500
# Bound the table so a long listening session cannot grow it without limit.
CACHE_MAX = 300

# One merge at a time: yt-dlp + ffmpeg are CPU bound, and a shelf of clips
# resolving in parallel would starve the machine instead of going faster.
_merge_lock = threading.Lock()


def cache_key(video_id: str, kind: str) -> str:
    """Audio and video URLs of the same id are different resources."""
    return f"{kind}:{video_id}"


def cache_get(video_id: str, kind: str) -> str | None:
    key = cache_key(video_id, kind)
    with _cache_lock:
        entry = _cache.get(key)
        if entry is None:
            return None
        url, stored_at = entry
        if time.time() - stored_at > CACHE_TTL:
            del _cache[key]
            return None
        return url


def cache_put(video_id: str, kind: str, url: str) -> None:
    with _cache_lock:
        _cache[cache_key(video_id, kind)] = (url, time.time())
        if len(_cache) > CACHE_MAX:
            for old in sorted(_cache, key=lambda k: _cache[k][1])[
                : len(_cache) - CACHE_MAX
            ]:
                del _cache[old]


# ─── Verdicts « cette vidéo ne se jouera pas ici » ───────────────────────────
# yt-dlp answers in 15-45 s, and a label whose country whitelist excludes this
# IP says the same thing every time. Without remembering it, each retry from the
# phone re-ran the whole extraction (16 identical attempts for one id in a single
# session) and the app kept queueing 30 s waits behind them instead of falling
# back to the sources that answer by title.
_gone: dict[str, tuple[str, float]] = {}
_gone_lock = threading.Lock()
GONE_TTL = 1800
GONE_MARKS = (
    "Video unavailable",
    "video unavailable",
    "not available",
    "Private video",
    "Removed by the owner",
    "does not exist",
)


def _is_gone_verdict(message: str) -> bool:
    return any(mark in message for mark in GONE_MARKS)


def _remember_gone(video_id: str, message: str) -> None:
    with _gone_lock:
        _gone[video_id] = (message, time.time())
        if len(_gone) > CACHE_MAX:
            for old in sorted(_gone, key=lambda k: _gone[k][1])[
                : len(_gone) - CACHE_MAX
            ]:
                del _gone[old]


def _gone_verdict(video_id: str) -> str | None:
    with _gone_lock:
        entry = _gone.get(video_id)
        if entry is None:
            return None
        message, stored_at = entry
        if time.time() - stored_at > GONE_TTL:
            del _gone[video_id]
            return None
        return message


def resolve_audio(video_id: str) -> str:
    """Direct audio URL (no muxing needed — the player accepts adaptive audio)."""
    hit = cache_get(video_id, "audio")
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
    
    def _run_audio():
        proc = subprocess.run(
            cmd,
            capture_output=True,
            timeout=RUN_TIMEOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        return _first_url(proc)

    try:
        future = _EXECUTOR.submit(_run_audio)
        url = future.result(timeout=RUN_TIMEOUT + 5)
    except TimeoutError:
        raise RuntimeError("yt-dlp audio resolution timed out")
    except Exception as exc:
        raise RuntimeError(f"yt-dlp audio failed: {exc}") from exc

    cache_put(video_id, "audio", url)
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
                    
                    def _run_merge():
                        proc = subprocess.run(
                            cmd,
                            capture_output=True,
                            timeout=MERGE_TIMEOUT,
                            text=True,
                            encoding="utf-8",
                            errors="replace",
                        )
                        return proc

                    # Run the merge in the executor with tracking
                    future = _EXECUTOR.submit(_run_merge)
                    proc = future.result(timeout=MERGE_TIMEOUT + 30)
                    _track_process(proc)
                    try:
                        produced = os.path.join(tmp_dir, f"{video_id}.mp4")
                        if not (os.path.exists(produced) and os.path.getsize(produced) > 0):
                            raise RuntimeError(_describe_failure(proc))
                        os.replace(produced, target)
                    finally:
                        _untrack_process(proc)
                url = f"http://127.0.0.1:9877/file/{video_id}.mp4"
                cache_put(video_id, "video", url)
                return url


def _first_url(proc) -> str:
    for line in (proc.stdout or "").strip().splitlines():
        line = line.strip()
        if line.startswith("http"):
            return line
    raise RuntimeError(_describe_failure(proc))


def _describe_failure(proc) -> str:
    """Never return an empty reason.

    An empty 502 body turns a dead track into a mystery: the device logs
    "Empty reply" and nobody can tell an unavailable video from a broken
    ffmpeg. yt-dlp's message is the last useful line it printed, and the exit
    code always says something.
    """
    for blob in (proc.stderr, proc.stdout):
        for line in reversed((blob or "").strip().splitlines()):
            line = line.strip()
            if line and not line.startswith("["):
                return line[:200]
    return f"yt-dlp exited with {proc.returncode}"


class Handler(BaseHTTPRequestHandler):
    server_version = "TunefyLocalStream/1.0"

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        try:
            self.wfile.write(body)
            self.wfile.flush()
        except OSError:
            # The device gave up on its 28-30 s budget and closed. Re-raising
            # only made a second traceback land in the "internal server error"
            # branch and buried the real verdict in noise.
            pass

    def do_HEAD(self) -> None:  # noqa: N802 - stdlib naming
        self._serve_media(head_only=True)

    def do_GET(self) -> None:  # noqa: N802 - stdlib naming
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/health":
                self._json(200, {"ok": True, "cached": len(_cache), "uptime": time.time() - _SERVER_START_TIME})
                return
            if parsed.path == "/stream":
                video_id = (parse_qs(parsed.query).get("videoId") or [""])[0]
                kind = (parse_qs(parsed.query).get("kind") or ["audio"])[0]
                if not VIDEO_ID_RE.match(video_id):
                    self._json(400, {"error": "invalid videoId"})
                    return
                dead = _gone_verdict(video_id)
                if dead is not None:
                    # Instant answer for a verdict already given, so the app's
                    # 30 s wait becomes a millisecond and it moves on to the
                    # sources that resolve by title.
                    self._json(502, {"error": dead, "gone": True, "cached": True})
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
                    message = str(exc)[:200]
                    gone = _is_gone_verdict(message)
                    if gone:
                        already = _gone_verdict(video_id)
                        _remember_gone(video_id, message)
                        # Print the traceback only the first time this id dies;
                        # one dead upload repeated 8 times per session filled the
                        # console with identical stacks and hid everything else.
                        if already is None:
                            traceback.print_exc()
                    else:
                        traceback.print_exc()
                    self._json(502, {"error": message, "gone": gone})
                return
            if parsed.path.startswith("/file/"):
                self._serve_media(head_only=False)
                return
            self._json(404, {"error": "not found"})
        except Exception as exc:  # noqa: BLE001
            # Catch-all for any unexpected exception in the handler
            traceback.print_exc()
            try:
                self._json(500, {"error": "internal server error"})
            except Exception:
                pass
            return

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


def _cleanup_processes() -> None:
    """Terminate all tracked subprocesses on exit."""
    with _ACTIVE_LOCK:
        for proc in _ACTIVE_PROCESSES:
            try:
                if proc.poll() is None:
                    proc.terminate()
            except Exception:
                pass
        # Give processes a moment to terminate gracefully
        time.sleep(0.5)
        for proc in _ACTIVE_PROCESSES:
            try:
                if proc.poll() is None:
                    proc.kill()
            except Exception:
                pass

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9877)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    
    _ensure_ffmpeg()
    os.makedirs(MEDIA_DIR, exist_ok=True)
    
    def _shutdown(signum, frame):
        print(f"Received signal {signum}, shutting down...", flush=True)
        _cleanup_processes()
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)
    
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"listening on http://{args.host}:{args.port}", flush=True)
    print(f"media cache: {MEDIA_DIR}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
