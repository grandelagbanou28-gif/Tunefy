"""Tunefy artist seed pipeline — charge des artistes du monde entier dans Supabase.

Sources (metadata) :
  - MusicBrainz  : catalogue ouvert, ~2M+ artistes/groupes, sans clé API.
  - Deezer        : enrichit genres/pays + vraies images de pochettes (photo).
  - LastFM        : images secondaires.

Alimente la table public.artists (0010_artists_catalog.sql) via service_role.
Les "catégories" se déduisent du genre principal de chaque artiste (genre => catégorie).

Usage :
  export SUPABASE_SERVICE_KEY=...   (depuis .env)
  python scripts/seed_artists.py --start 0 --count 10000 --category "Afrobeats"
"""
import argparse
import hashlib
import json
import os
import random
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

import httpx
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

_headers = None


def headers():
    global _headers
    # Prefer service role so we can write.
    key = SERVICE_KEY or ANON_KEY
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }


# Mapping genre => catégorie (metatexture avec le système de catégories de l'app)
GENRE_TO_CATEGORY = {
    "jazz": "Jazz", "blues": "Blues", "rock": "Rock", "metal": "Metal",
    "pop": "Pop", "hip hop": "Hip-Hop", "rap": "Hip-Hop", "rnb": "R&B",
    "soul": "Soul", "funk": "Funk", "reggae": "Reggae", "dancehall": "Reggae",
    "electronic": "Electronic", "house": "Electronic", "techno": "Electronic",
    "edm": "Electronic", "country": "Country", "folk": "Folk",
    "afrobeats": "Afrobeats", "afrobeat": "Afrobeats", "highlife": "Afrobeats",
    "gospel": "Gospel", "classical": "Classical", "opera": "Classical",
    "latin": "Latin", "salsa": "Latin", "samba": "Latin", "reggaeton": "Latin",
    "kpop": "K-Pop", "inde": "Indé", "chanson": "French", "variete": "French",
    "ambient": "Ambient", "lofi": "Lofi", "study": "Focus",
    "slee": "Sleep", "meditation": "Wellness",
}


def slugify(name: str) -> str:
    s = name.strip().lower()
    s = "".join(c if (c.isalnum() or c == " ") else "-" for c in s)
    return "-".join(s.split())[:80] or "unnamed"


def category_for_genre(genre: str) -> str:
    g = (genre or "").lower()
    return GENRE_TO_CATEGORY.get(g, "Divers")


def hash_id(name: str) -> str:
    return hashlib.md5(name.lower().encode()).hexdigest()


def fetch_musicbrainz(offset: int, limit: int) -> list:
    """Récupère une tranche d'artistes MusicBrainz via l'API de recherche."""
    url = "https://musicbrainz.org/ws/2/artist/"
    params = {
        "query": 'type:person OR type:group',  # tout, peuplé
        "fmt": "json",
        "offset": offset,
        "limit": min(limit, 100),
    }
    try:
        with httpx.Client(timeout=30) as c:
            r = c.get(url, params=params, headers={"User-Agent": "TunefySeed/1.0 (contact@tunefy.app)"})
            if r.status_code != 200:
                return []
            data = r.json()
            return data.get("artists", [])
    except Exception as e:
        print(f"[MusicBrainz] error: {e}")
        return []


def enrich_deezer(name: str) -> dict:
    """Essaye de récupérer une vraie image + genre via l'API Deezer."""
    try:
        with httpx.Client(timeout=15) as c:
            r = c.get("https://api.deezer.com/search/artist",
                      params={"q": name, "limit": 1})
            if r.status_code == 200:
                d = r.json().get("data")
                if d:
                    a = d[0]
                    return {
                        "image_url": a.get("picture_xl") or a.get("picture"),
                        "deezer_id": str(a.get("id")),
                        "genre": (a.get("genre_id") and "pop") or None,
                    }
    except Exception:
        pass
    return {}


def build_rows_parallel(names: list) -> list:
    rows = []
    with ThreadPoolExecutor(max_workers=16) as ex:
        futures = {ex.submit(enrich_deezer, n): n for n in names}
        for fut in as_completed(futures):
            n = futures[fut]
            try:
                d = fut.result()
            except Exception:
                d = {}
            rows.append({
                "name": n,
                "slug": slugify(n) + "-" + hash_id(n)[:6],
                "categories": [category_for_genre(d.get("genre"))],
                "genres": [g for g in [d.get("genre")] if g],
                "image_url": d.get("image_url"),
                "deezer_id": d.get("deezer_id"),
                "mb_id": hash_id(n),
                "source": "musicbrainz",
                "verified": False,
            })
    return rows


def upsert_batch(rows: list):
    if not rows:
        return
    url = f"{SUPABASE_URL}/rest/v1/artists"
    with httpx.Client(timeout=30) as c:
        r = c.post(url, headers=headers(), json=rows)
        if r.status_code >= 400:
            print(f"[Insert] status {r.status_code}: {r.text[:200]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=10000)
    ap.add_argument("--batch", type=int, default=200)
    args = ap.parse_args()

    if not (SUPABASE_URL and (SERVICE_KEY or ANON_KEY)):
        print("Missing SUPABASE_URL / SUPABASE_SERVICE_KEY in .env")
        return

    inserted = 0
    offset = 0
    while inserted < args.count:
        raw = fetch_musicbrainz(offset, min(args.batch, 100))
        if not raw:
            print("No more MusicBrainz artists. Stopping.")
            break
        names = [a.get("name") for a in raw if a.get("name")]
        rows = build_rows_parallel(names)
        upsert_batch(rows)
        inserted += len(rows)
        print(f"Inserted {len(rows)} (total {inserted}/{args.count}). Sleeping to respect MB rate limit...")
        time.sleep(1.0)  # MusicBrainz ~1 req/s, mais on pagine par tranche
        offset += len(rows)


if __name__ == "__main__":
    main()