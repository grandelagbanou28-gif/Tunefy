"""Tunefy artist seed (vrais artistes) — catalogue d'artistes réels par catégorie.
Utilise des listes de noms réels connus par catégorie, récupère la vraie image
Deezer par recherche du nom exact (ex: "Burna Boy"), et insère dans la table
artists via service_role. Les catégories sont stockées dans genres[] (déjà là).
Tri par followers (nb_fan Deezer).
"""
import argparse
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
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


# Vrais artistes connus par catégorie (genre) — noms réels
REAL_ARTISTS = {
    "Afrobeats": ["Burna Boy", "Wizkid", "Davido", "Rema", "Ayra Starr", "Omah Lay",
                  "Asake", "Tems", "Seyi Shay", "Bella Shmurda", "Fireboy DML",
                  "Lojay", "BNXN", "Kizz Daniel", "Mayorkun", "Ckay", "Teni"],
    "Gospel": ["Sinach", "Nathaniel Bassey", "Don Moen", "CeCe Winans", "Kirk Franklin",
               "Tasha Cobbs Leonard", "Hillsong", "William McDowell", "Travis Greene",
               "Mercy Chinwo", "Judith Wambui", "Kelvin Momo"],
    "Pop": ["Taylor Swift", "Ariana Grande", "Dua Lipa", "Billie Eilish", "Ed Sheeran",
            "Bruno Mars", "Justin Bieber", "Charli XCX", "Olivia Rodrigo", "Sabrina Carpenter"],
    "Hip-Hop": ["Kendrick Lamar", "Drake", "J. Cole", "Eminem", "Travis Scott", "21 Savage",
                "Lil Baby", "Kanye West", "Nicki Minaj", "Megan Thee Stallion"],
    "R&B": ["SZA", "Frank Ocean", "The Weeknd", "Beyoncé", "Chris Brown", "Ari Lennox",
            "Summer Walker", "Mario", "Usher", "Jazmine Sullivan"],
    "Rock": ["Coldplay", "Imagine Dragons", "Foo Fighters", "Red Hot Chili Peppers",
             "Linkin Park", "Arctic Monkeys", "Queen", "AC/DC", "Nirvana", "Metallica"],
    "Jazz": ["Miles Davis", "John Coltrane", "Ella Fitzgerald", "Louis Armstrong",
             "Nina Simone", "Duke Ellington", "Chet Baker", "Billie Holiday"],
    "Latin": ["Bad Bunny", "J Balvin", "Shakira", "Karol G", "Ricky Martin",
              "Maluma", "Anuel AA", "Sebastián Yatra"],
    "K-Pop": ["BTS", "BLACKPINK", "Stray Kids", "NewJeans", "TWICE", "Seventeen",
              "EXO", "IVE", "Red Velvet", "ENHYPEN"],
    "Classical": ["Ludovic Tanguy", "Yuja Wang", "Lang Lang", "Max Richter"],
    "Electronic": ["Daft Punk", "Avicii", "Martin Garrix", "Calvin Harris", "Tiësto",
                   "David Guetta", "Swedish House Mafia", "Skrillex"],
    "Reggae": ["Bob Marley", "Damian Marley", "Shaggy", "Sean Paul", "Ziggy Marley",
               "Sizzla", "Alborosie"],
    "Country": ["Taylor Swift", "Luke Bryan", "Dolly Parton", "Blake Shelton",
                "Kane Brown", "Carrie Underwood", "Chris Stapleton"],
}


def deezer_image_and_fans(name: str):
    """Récupère vraie image + nb de fans via Deezer search par nom exact."""
    try:
        with httpx.Client(timeout=15) as c:
            r = c.get("https://api.deezer.com/search/artist", params={"q": name, "limit": 1})
            if r.status_code == 200:
                d = r.json().get("data")
                if d:
                    a = d[0]
                    return (a.get("picture_xl") or a.get("picture"),
                            a.get("nb_fan") or 0, str(a.get("id")))
    except Exception as e:
        print(f"[Deezer] {name}: {e}")
    return (None, 0, None)


def sync_category(category: str):
    print(f"\n=== {category} ===")
    added = 0
    for name in REAL_ARTISTS.get(category, []):
        try:
            img, fans, dzid = deezer_image_and_fans(name)
        except Exception:
            img, fans, dzid = None, 0, None
        genre = category.lower()
        payload = {
            "name": name,
            "image_url": img,
            "genres": [genre],
            "country_code": None,
            "verified": True,
            "followers": fans,
        }
        with httpx.Client(timeout=20) as c:
            # upsert par nom
            r = c.post(
                f"{SUPABASE_URL}/rest/v1/artists",
                headers={**headers(), "Prefer": "resolution=merge-duplicates"},
                json=payload, params={"on_conflict": "name"},
            )
            # sans contrainte unique sur name, on fait un update si existe
            existing = c.get(f"{SUPABASE_URL}/rest/v1/artists",
                             headers=headers(), params={"select": "id", "name": f"eq.{name}"})
            if existing.status_code == 200 and existing.json():
                id_ = existing.json()[0]["id"]
                c.patch(f"{SUPABASE_URL}/rest/v1/artists?id=eq.{id_}",
                        headers=headers(), json=payload)
            else:
                c.post(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(), json=payload)
            added += 1
            print(f"  + {name} ({fans} fans, img={bool(img)})")
        time.sleep(0.15)
    print(f"  -> {added} artistes pour {category}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--category", type=str, default=None,
                    help="Catégorie à ingérer (ou toutes si absent)")
    args = ap.parse_args()

    if not (SUPABASE_URL and (SERVICE_KEY or ANON_KEY)):
        print("Missing credentials in .env")
        return

    cats = [args.category.title()] if args.category else list(REAL_ARTISTS.keys())
    for c in cats:
        if c in REAL_ARTISTS:
            sync_category(c)


if __name__ == "__main__":
    main()