"""Tunefy artist seed (structure existante) — insère des artistes réels avec vraies images.
Table artists actuelle (colonnes) : id,name,image_url,country,country_code,region,
genres[],bio,verified,followers,created_at,updated_at.
Les catégories sont dérivées des genres et stockées dans le même champ. Tri par followers.
Sources d'images : Deezer (vraies photos d'artistes, CDN public).
"""
import argparse
import json
import os
import random
import time
import urllib.parse

import httpx
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")


def headers():
    key = SERVICE_KEY or ANON_KEY
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


# Mapping genre -> catégorie (mêmes catégories que l'app)
GENRE_TO_CATEGORY = {
    "jazz": "Jazz", "blues": "Blues", "rock": "Rock", "metal": "Metal", "pop": "Pop",
    "hip hop": "Hip-Hop", "rap": "Hip-Hop", "rnb": "R&B", "soul": "Soul", "funk": "Funk",
    "reggae": "Reggae", "electronic": "Electronic", "house": "Electronic", "techno": "Electronic",
    "edm": "Electronic", "country": "Country", "folk": "Folk", "afrobeats": "Afrobeats",
    "gospel": "Gospel", "classical": "Classical", "latin": "Latin", "kpop": "K-Pop",
}


def category_for(genres):
    for g in genres:
        g = (g or "").lower()
        if g in GENRE_TO_CATEGORY:
            return GENRE_TO_CATEGORY[g]
    return "Divers"


def fetch_from_deezer(query: str, limit: int = 25):
    """Récupère des artistes réels (noms, vraies images, genres) via Deezer search."""
    try:
        with httpx.Client(timeout=15) as c:
            r = c.get("https://api.deezer.com/search/artist", params={"q": query, "limit": limit})
            if r.status_code == 200:
                data = r.json().get("data") or []
                rows = []
                for a in data:
                    rows.append({
                        "name": a.get("name"),
                        "image_url": a.get("picture_xl") or a.get("picture"),
                        "deezer_nb_fan": a.get("nb_fan") or 0,
                        "deezer_id": str(a.get("id")),
                    })
                return rows
    except Exception as e:
        print(f"[Deezer] error: {e}")
    return []


def upsert_artist(row: dict):
    cat = category_for([row["genres"][0]] if row.get("genres") else [])
    payload = {
        "name": row["name"],
        "image_url": row["image_url"],
        "genres": row.get("genres") or [cat.lower()],
        "country_code": None,
        "verified": False,
        "followers": row.get("deezer_nb_fan") or 0,
    }
    # upsert ignore les doublons par nom (sans unique constraint, on ajoute un guard)
    with httpx.Client(timeout=20) as c:
        # check si nom existe déjà
        existing = c.get(
            f"{SUPABASE_URL}/rest/v1/artists",
            headers=headers(),
            params={"select": "id", "name": f"eq.{row['name']}"},
        )
        if existing.status_code == 200 and existing.json():
            return False  # déjà présent
        r = c.post(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(), json=payload)
        return r.status_code < 400


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--category", type=str, default="pop",
                    help="Genre/query Deezer à ingérer (ex: pop, afrobeats, gospel, jazz, kpop, latin)")
    ap.add_argument("--count", type=int, default=25)
    args = ap.parse_args()

    if not (SUPABASE_URL and (SERVICE_KEY or ANON_KEY)):
        print("Missing credentials in .env")
        return

    art = fetch_from_deezer(args.category, args.count)
    inserted = 0
    for row in art:
        if row.get("name"):
            try:
                if upsert_artist(row):
                    inserted += 1
                    print(f"  + {row['name']} ({args.category})")
            except Exception as e:
                print(f"  ! {row.get('name')}: {e}")
        time.sleep(0.15)
    print(f"\nInséré {inserted}/{len(art)} artistes pour '{args.category}'.")


if __name__ == "__main__":
    main()