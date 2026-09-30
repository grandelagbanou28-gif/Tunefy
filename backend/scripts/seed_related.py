"""Tunefy seed by related (volume qualité) — part de graines populaires par genre,
récupère leurs artistes "related" Deezer (même genre, populaires), les insère après
validation stricte (vraie image + fans >= MIN_FANS), puis itère quelques niveaux (BFS)
pour faire grossir le catalogue tout en restant dans le bon genre et propre.
"""
import os
import time

import httpx
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

EMPTY_IMG = {"d41d8cd98f00b204e9800998ecf8427e"}
MIN_FANS = int(os.environ.get("MIN_FANS", "2000"))
DEEZER = "https://api.deezer.com"

# Graines populaires par genre (on cherche l'id via search/artist, robuste)
SEEDS = {
    "afrobeats": ["Burna Boy", "Wizkid", "Davido", "Rema", "Ayra Starr", "Asake", "Olamide", "Tiwa Savage", "Diamond Platnumz", "Fally Ipupa", "Virgal Magagi", "Youssoupha", "Sarkodie", "Sho Madjozi", "Nasty C"],
    "gospel": ["Kirk Franklin", "Sinach", "CeCe Winans", "Hillsong Worship", "Mercy Chinwo", "Don Moen", "Tasha Cobbs", "Jonathan McReynolds", "Fred Hammond", "Maverick City Music", "Elevation Worship", "Bethel Music"],
    "pop": ["Taylor Swift", "Ariana Grande", "Dua Lipa", "Ed Sheeran", "The Weeknd", "Bruno Mars", "Justin Bieber", "Lady Gaga", "Miley Cyrus", "Katy Perry", "Rihanna", "Adele", "Billie Eilish", "Sia", "Charlie Puth", "Selena Gomez"],
    "hip-hop": ["Drake", "Kendrick Lamar", "Travis Scott", "Eminem", "J. Cole", "Kanye West", "Future", "Lil Wayne", "Nas", "50 Cent", "Nicki Minaj", "Cardi B", "Lil Baby", "DaBaby", "Playboi Carti", "A$AP Rocky"],
    "r&b": ["Beyoncé", "SZA", "Chris Brown", "Usher", "Frank Ocean", "The Weeknd", "H.E.R.", "Alicia Keys", "Mary J. Blige", "John Legend", "Ari Lennox", "Summer Walker", "The Weeknd", "Toni Braxton", "Trey Songz"],
    "rock": ["Coldplay", "Imagine Dragons", "Queen", "AC/DC", "Metallica", "Foo Fighters", "Nirvana", "Linkin Park", "U2", "Green Day", "Arctic Monkeys", "Muse", "The Killers", "Pearl Jam", "Radiohead", "Red Hot Chili Peppers", "Three Days Grace"],
    "jazz": ["Miles Davis", "John Coltrane", "Ella Fitzgerald", "Nina Simone", "Diana Krall", "Louis Armstrong", "Herbie Hancock", "Norah Jones", "Billie Holiday", "Duke Ellington", "Charlie Parker", "Erykah Badu"],
    "latin": ["Bad Bunny", "J Balvin", "Shakira", "Karol G", "Maluma", "Ozuna", "Ricky Martin", "Roméo Santos", "Daddy Yankee", "Luis Fonsi", "Anuel AA", "Rosalía", "Jhayco", "Rauw Alejandro"],
    "k-pop": ["BTS", "BLACKPINK", "Stray Kids", "NewJeans", "EXO", "TWICE", "Seventeen", "Aespa", "Enhypen", "ATEEZ", "IVE", "Red Velvet", "LE SSERAFIM", "BoA"],
    "classical": ["Ludovico Einaudi", "André Rieu", "Yo-Yo Ma", "Lang Lang", "Max Richter", "Yuja Wang", "Itzhak Perlman", "Hilary Hahn", "Marianne Beaulieu"],
    "electronic": ["David Guetta", "Daft Punk", "Calvin Harris", "Tiësto", "Avicii", "Martin Garrix", "Zedd", "The Chainsmokers", "Marshmello", "Skrillex", "deadmau5", "Alan Walker", "Illenium", "Gryffin"],
    "reggae": ["Bob Marley", "Sean Paul", "Shaggy", "Vybz Kartel", "Koffee", "Buju Banton", "Damian Marley", "Beenie Man", "Ziggy Marley", "Chronixx", "Toots and the Maytals"],
    "country": ["Dolly Parton", "Chris Stapleton", "Carrie Underwood", "Garth Brooks", "Luke Bryan", "Morgan Wallen", "Kenny Chesney", "Miranda Lambert", "Tim McGraw", "Zach Bryan", "Toby Keith", "Blake Shelton"],
    "soul": ["Aretha Franklin", "Marvin Gaye", "Stevie Wonder", "Al Green", "Sam Cooke", "Otis Redding", "Bill Withers", "Luther Vandross", "Ray Charles", "Sam Smith", "Amy Winehouse"],
    "funk": ["James Brown", "Prince", "Parliament", "Chaka Khan", "Earth Wind & Fire", "Tower of Power", "Kool & The Gang", "Bootsy Collins", "Daft Punk"],
    "blues": ["B.B. King", "Muddy Waters", "Buddy Guy", "Gary Clark Jr.", "John Lee Hooker", "Etta James", "Stevie Ray Vaughan", "Robert Johnson", "Howlin' Wolf", "Albert King"],
    "metal": ["Metallica", "Iron Maiden", "Slipknot", "System of a Down", "Rammstein", "Pantera", "Megadeth", "Judas Priest", "Lamb of God", "Disturbed", "Avenged Sevenfold", "Trivium"],
    "folk": ["Bob Dylan", "Hozier", "Bon Iver", "Mumford & Sons", "Joni Mitchell", "The Lumineers", "Fleet Foxes", "Leonard Cohen", "Fleetwood Mac", "Iron & Wine", "Sufjan Stevens", "Nick Drake", "The Avett Brothers"],
}


def headers():
    key = SERVICE_KEY or ANON_KEY
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}


def has_valid_image(img: str) -> bool:
    if not img:
        return False
    if "/artist//" in img:
        return False
    hp = img.split("/images/artist/")
    if len(hp) == 2 and hp[1].split("/")[0] in EMPTY_IMG:
        return False
    return True


def deezer_id(client: httpx.Client, name: str):
    """Cherche le meilleur match Deezer : image valide + max de fans."""
    r = client.get(f"{DEEZER}/search/artist", params={"q": name, "limit": 6})
    if r.status_code != 200:
        return None
    best_id, best_fans = None, -1
    for a in r.json().get("data") or []:
        img = a.get("picture_xl") or a.get("picture_big") or a.get("picture_medium")
        if not has_valid_image(img):
            continue
        fans = a.get("nb_fan") or 0
        if fans > best_fans:
            best_fans = fans
            best_id = a["id"]
    return best_id


def valid_artist(a: dict):
    img = a.get("picture_xl") or a.get("picture_big") or a.get("picture_medium")
    fans = a.get("nb_fan") or 0
    if not has_valid_image(img):
        return None
    if fans < MIN_FANS:
        return None
    return (img, fans)


def load_existing(client: httpx.Client):
    names = set()
    offset = 0
    while True:
        r = client.get(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(),
                       params={"select": "name", "limit": 1000, "offset": offset})
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
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--depth", type=int, default=2, help="niveaux de BFS des related")
    ap.add_argument("--per", type=int, default=25, help="related pris par graine")
    args = ap.parse_args()

    client = httpx.Client(timeout=20)
    existing = load_existing(client)
    print(f"Déjà en base: {len(existing)}")

    total = 0
    for genre, seeds in SEEDS.items():
        # file BFS
        frontier = list(seeds)
        depth = 0
        seen = set()
        while frontier and depth < args.depth:
            next_frontier = []
            for name in frontier:
                if name.strip().lower() in seen:
                    continue
                seen.add(name.strip().lower())
                did = deezer_id(client, name)
                if not did:
                    continue
                r = client.get(f"{DEEZER}/artist/{did}/related", params={"limit": args.per})
                if r.status_code != 200:
                    continue
                for a in (r.json().get("data") or []):
                    aname = a.get("name") or ""
                    low = aname.strip().lower()
                    if not aname or low in existing or low in seen:
                        continue
                    v = valid_artist(a)
                    if not v:
                        continue
                    img, fans = v
                    try:
                        pr = client.post(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(),
                                         json={"name": aname.strip(), "image_url": img,
                                               "genres": [genre], "verified": True,
                                               "followers": fans})
                        if pr.status_code < 400:
                            existing.add(low)
                            next_frontier.append(aname)
                            total += 1
                    except Exception as e:
                        print(f"  ! {aname}: {e}")
                    time.sleep(0.15)
            frontier = next_frontier
            depth += 1
            print(f"  [{genre}] profondeur {depth}: total en cours = {total}")
    client.close()
    print(f"\nTOTAL insérés (related): {total}")


if __name__ == "__main__":
    main()