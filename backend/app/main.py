"""Tunefy API — FastAPI.
Serve :
  - /stream  full-length audio for a YouTube videoId (via yt-dlp, run here)
  - /artists artists by category (paginated, from Supabase)
  - /search/artists artist search
Deploy on Render, talk to Supabase, store media on Cloudflare R2.
"""
import os
import asyncio
import json
import re
from pathlib import Path
from typing import Optional

import httpx
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

app = FastAPI(title="Tunefy API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
YT_DLP_BIN = os.getenv("YT_DLP_BIN", "yt-dlp")

SUPABASE_HEADERS = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_SERVICE_KEY or SUPABASE_ANON_KEY}",
}

# Un videoId ne contient que les caractères d'un identifiant YouTube : sans
# cette garde, `watch?v=<payload>` pourrait injecter d'autres paramètres/URL.
VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


@app.get("/health")
async def health():
    return PlainTextResponse("ok")


@app.get("/artists")
async def artists(
    category: Optional[str] = Query(None, description="Category to filter by"),
    q: Optional[str] = Query(None, description="Search query"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    """Paginated artists from Supabase, optionally by category or search."""
    if not SUPABASE_URL:
        return JSONResponse({"error": "Supabase not configured"}, status_code=500)

    base = f"{SUPABASE_URL}/rest/v1/rpc/artists_by_category"
    params: dict = {"p_limit": limit, "p_offset": offset}

    if category:
        params["p_category"] = category
    if q:
        base = f"{SUPABASE_URL}/rest/v1/rpc/search_artists"
        params = {"p_query": q, "p_limit": limit}

    try:
        async with httpx.AsyncClient(timeout=20) as client:
            resp = await client.get(base, headers=SUPABASE_HEADERS, params=params)
        if resp.status_code != 200:
            return JSONResponse(
                {"error": f"Supabase {resp.status_code}", "detail": resp.text[:300]},
                status_code=502,
            )
        return {"artists": resp.json(), "limit": limit, "offset": offset}
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=502)


@app.get("/stream")
async def stream(videoId: str = Query(...)):
    """Full-length audio URL for a YouTube videoId via yt-dlp."""
    if not videoId:
        return JSONResponse({"error": "missing videoId"}, status_code=400)
    if not VIDEO_ID_RE.match(videoId):
        return JSONResponse({"error": "invalid videoId"}, status_code=400)

    url = f"https://www.youtube.com/watch?v={videoId}"
    cmd = [
        YT_DLP_BIN,
        "--no-playlist",
        "-f", "bestaudio/best",
        "--get-url",
        "--no-warnings",
        "--socket-timeout", "15",
        "--",
    ]
    cmd.append(url)
    # NOTE : jamais de --no-check-certificates : il désactive la vérification
    # TLS et rend tout le trafic amont interceptable (MITM).

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=30)
        stream_url = stdout.decode().strip().split("\n")[0]
        if stream_url and stream_url.startswith("http"):
            return JSONResponse({"url": stream_url})
        return JSONResponse(
            {"error": f"yt-dlp: {stream_url} | {stderr.decode()[:200]}"},
            status_code=502,
        )
    except asyncio.TimeoutError:
        return JSONResponse({"error": "yt-dlp timed out"}, status_code=504)
    except FileNotFoundError:
        return JSONResponse({"error": "yt-dlp not installed"}, status_code=500)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)