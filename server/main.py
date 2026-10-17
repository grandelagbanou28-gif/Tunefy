"""Tunefy cloud stream RELAY server.

Why a relay (not just a resolver)
---------------------------------
yt-dlp returns a googlevideo URL that is locked to the IP that produced it
(`ip=` + signature). A cloud resolver hands that URL to the phone, whose public
IP differs → HTTP 403 on every track. That is why the app needed a PC-local
server: the phone and the PC share one public IP.

This server removes the PC. It RESOLVES the URL itself and then RELAYS the
audio bytes through its own connection, so the phone only ever talks to *this*
server (same IP that resolved the link). Range is forwarded so ExoPlayer seeking
keeps working.

Contract used by the app:
    GET /stream?videoId=XXX  ->  { "url": "https://<self>/relay?videoId=XXX" }
    GET /relay?videoId=XXX   ->  audio bytes (200/206, Range aware)
    GET /health              ->  200 OK

Deploy free on Render / Railway / Fly.io (Dockerfile + railway.json provided).
"""
from __future__ import annotations

import asyncio
import os
import re
import time
from pathlib import Path
from typing import Optional

import httpx
from fastapi import FastAPI, Query, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse

app = FastAPI(title="Tunefy Relay", version="1.0.0")

YT_DLP_BIN = os.getenv("YT_DLP_BIN", "yt-dlp")
COOKIES_PATH = os.getenv("COOKIES_PATH", "")

VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

# googlevideo links expire (a few hours) and 403 once their IP/signature stops
# matching, so a resolved URL is cached only briefly and re-resolved on a 403.
_URL_CACHE: dict[str, tuple[str, float]] = {}
_CACHE_TTL = 3 * 3600  # 3 h — well under the usual ~6 h expiry
_CACHE_MAX = 500

# Forwarded response headers the player needs to stream + seek.
_RELAY_HEADERS = (
    "content-type",
    "content-length",
    "content-range",
    "accept-ranges",
    "cache-control",
)


def _cache_get(video_id: str) -> Optional[str]:
    hit = _URL_CACHE.get(video_id)
    if not hit:
        return None
    url, ts = hit
    if time.time() - ts > _CACHE_TTL:
        _URL_CACHE.pop(video_id, None)
        return None
    return url


def _cache_put(video_id: str, url: str) -> None:
    if len(_URL_CACHE) >= _CACHE_MAX:
        # Drop the oldest entries so a long session cannot grow unbounded.
        for key in sorted(_URL_CACHE, key=lambda k: _URL_CACHE[k][1])[: _CACHE_MAX // 2]:
            _URL_CACHE.pop(key, None)
    _URL_CACHE[video_id] = (url, time.time())


async def _resolve_url(video_id: str, *, force: bool = False) -> str:
    """Direct googlevideo URL for a videoId, via yt-dlp (cached briefly)."""
    if not force:
        cached = _cache_get(video_id)
        if cached:
            return cached

    cmd = [
        YT_DLP_BIN,
        "--no-playlist",
        "-f", "bestaudio/best",
        "--get-url",
        "--no-warnings",
        "--socket-timeout", "15",
        "--", f"https://www.youtube.com/watch?v={video_id}",
    ]
    if COOKIES_PATH and Path(COOKIES_PATH).exists():
        cmd.extend(["--cookies", COOKIES_PATH])

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=30)
    for line in stdout.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if line.startswith("http"):
            _cache_put(video_id, line)
            return line
    reason = (stderr.decode("utf-8", "replace") or stdout.decode("utf-8", "replace")).strip()
    raise RuntimeError(f"yt-dlp: {reason[-400:] or 'no url'}")


def _self_base(request: Request) -> str:
    """Public origin of THIS server, as seen by the client (proxy aware)."""
    proto = request.headers.get("x-forwarded-proto") or request.url.scheme or "https"
    host = (
        request.headers.get("x-forwarded-host")
        or request.headers.get("host")
        or request.url.netloc
    )
    return f"{proto}://{host}"


@app.get("/health")
async def health():
    return PlainTextResponse("ok")


@app.get("/stream")
async def stream(
    request: Request,
    videoId: str = Query(...),
    kind: str = Query("audio"),
):
    """Return a RELAY url for this server (never the raw googlevideo link)."""
    if not VIDEO_ID_RE.match(videoId):
        return JSONResponse({"error": "invalid videoId"}, status_code=400)
    base = _self_base(request)
    # kind is accepted for app compatibility; audio is what plays music.
    return JSONResponse({"url": f"{base}/relay?videoId={videoId}"})


@app.get("/relay")
async def relay(videoId: str = Query(...), request: Request = None):
    """Proxy the audio bytes through this server, forwarding Range for seek."""
    if not VIDEO_ID_RE.match(videoId):
        return JSONResponse({"error": "invalid videoId"}, status_code=400)

    client_range = request.headers.get("range")
    client_ua = request.headers.get("user-agent", "Mozilla/5.0")

    # Two attempts: on 403 the cached link went stale, so re-resolve once.
    for attempt in (1, 2):
        try:
            gurl = await _resolve_url(videoId, force=(attempt == 2 and True))
        except asyncio.TimeoutError:
            return JSONResponse({"error": "yt-dlp timed out"}, status_code=504)
        except Exception as exc:  # noqa: BLE001
            if attempt == 2:
                return JSONResponse({"error": str(exc)[:300]}, status_code=502)
            continue

        up_headers = {"User-Agent": client_ua}
        if client_range:
            up_headers["Range"] = client_range

        client = httpx.AsyncClient(timeout=None, follow_redirects=True)
        try:
            req = client.build_request("GET", gurl, headers=up_headers)
            upstream = await client.send(req, stream=True)

            if upstream.status_code == 403 and attempt == 1:
                # Stale link — drop it and re-resolve on the next pass.
                _URL_CACHE.pop(videoId, None)
                await upstream.aclose()
                continue

            resp_headers = {
                k: v for k, v in upstream.headers.items() if k.lower() in _RELAY_HEADERS
            }

            async def _body():
                try:
                    async for chunk in upstream.aiter_raw():
                        yield chunk
                finally:
                    await upstream.aclose()
                    await client.aclose()

            return StreamingResponse(
                _body(),
                status_code=upstream.status_code,
                headers=resp_headers,
            )
        except Exception:
            await client.aclose()
            if attempt == 2:
                return JSONResponse({"error": "relay failed"}, status_code=502)

    return JSONResponse({"error": "relay failed"}, status_code=502)


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8080"))
    uvicorn.run(app, host="0.0.0.0", port=port)
