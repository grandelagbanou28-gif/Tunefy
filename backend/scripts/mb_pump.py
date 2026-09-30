"""Tunefy MusicBrainz pump — remplit des milliers de vrais artistes par genre
depuis MusicBrainz (noms réels + tags genre), puis insère dans Supabase.
Les tags MB sont mappés vers nos catégories. L'enrichissement images/fans
(Deezer) est fait par ingest_enrich.py après coup.
"""
import os
import time

import httpx
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")


def headers():
    key = SERVICE_KEY or ANON_KEY
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}


# tag MusicBrainz -> catégorie (clé lowercase)
MB_TAGS = {
    "afrobeats": "afrobeats",
    "afrobeat": "afrobeats",
    "gospel": "gospel",
    "pop": "pop",
    "hip hop": "hip-hop",
    "rap": "hip-hop",
    "rnb": "r&b",
    "soul": "soul",
    "rock": "rock",
    "metal": "metal",
    "jazz": "jazz",
    "latin": "latin",
    "k-pop": "k-pop",
    "classical": "classical",
    "electronic": "electronic",
    "edm": "electronic",
    "house": "electronic",
    "techno": "electronic",
    "reggae": "reggae",
    "country": "country",
    "folk": "folk",
    "blues": "blues",
    "funk": "funk",
}


def fetch_mb_names(tag: str, initial_count: int, client: httpx.Client):
    """Récupère jusqu'à initial_count noms d'artistes MB pour un tag, paginé."""
    names = []
    offset = 0
    while len(names) < initial_count:
        r = client.get("https://musicbrainz.org/ws/2/artist/",
                       params={"query": f"tag:{tag}", "limit": 100,
                               "offset": offset, "fmt": "json"},
                       headers={"User-Agent": "TunefySeed/1.0 (artist catalog)"})
        if r.status_code != 200:
            print(f"  MB {tag} err {r.status_code}")
            break
        rows = r.json().get("artists") or []
        if not rows:
            break
        for a in rows:
            n = (a.get("name") or "").strip()
            if n:
                names.append(n)
        offset += len(rows)
        if len(rows) < 100:
            break
        time.sleep(1.1)  # rate limit MB (1 req/s)
    return names


def fetch_existing_names(client: httpx.Client):
    names = set()
    offset = 0
    while True:
        r = client.get(f"{SUPABASE_URL}/rest/v1/artists",
                       headers=headers(),
                       params={"select": "name", "genres": "not.is.null",
                               "limit": 1000, "offset": offset})
        if r.status_code != 200:
            break
        rows = r.json()
        if not rows:
            break
        for row in rows:
            if row.get("name"):
                names.add(row["name"].strip().lower())
        if len(rows) < 1000:
            break
        offset += 1000
    return names


def main():
    per_genre = int(os.environ.get("PER_GENRE", "500"))
    client = httpx.Client(timeout=30)
    existing = fetch_existing_names(client)
    print(f"Déjà en base: {len(existing)}")

    total_inserted = 0
    t0 = time.time()
    for tag, category in MB_TAGS.items():
        names = fetch_mb_names(tag, per_genre, client)
        # nouveaux = ceux absents en base
        new_names = [n for n in names if n.lower() not in existing]
        # bulk insert (500 par lot)
        for i in range(0, len(new_names), 500):
            batch = new_names[i:i + 500]
            payload = [
                {"name": n, "genres": [category], "verified": True,
                 "followers": 0, "image_url": None}
                for n in batch
            ]
            try:
                r = client.post(f"{SUPABASE_URL}/rest/v1/artists",
                                headers={**headers(), "Prefer": "resolution=ignore-duplicates,return=minimal"},
                                json=payload)
                if r.status_code < 400:
                    for n in batch:
                        existing.add(n.lower())
            except Exception as e:
                print(f"  ! batch {category}: {e}")
        total_inserted += len(new_names)
        print(f"  [{tag} -> {category}]: {len(new_names)} ajoutés (sur {len(names)} noms)")
    client.close()
    print(f"\nTOTAL ajoutés: {total_inserted} en {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()