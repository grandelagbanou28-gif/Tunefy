"""Tunefy catalog seed (grand catalogue) — ajoute des centaines de vrais artistes
par catégorie avec vraies images, en évitant les doublons déjà présents.
Récupère l'image + fans via Deezer search du nom exact. categories stockées dans genres[].
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


# ── Grand catalogue : vrais artistes par catégorie ──────────────────────────
CATALOG = {
    "Afrobeats": [
        "Burna Boy", "Wizkid", "Davido", "Rema", "Ayra Starr", "Omah Lay", "Asake",
        "Tems", "Seyi Vibez", "Fireboy DML", "Lojay", "BNXN", "Kizz Daniel", "Mayorkun",
        "Ckay", "Teni", "Zlatan", "Busy Signal", "Yemi Alade", "Niniola", "Mr Eazi",
        "Patoranking", "Korede Bello", "Wande Coal", "Tekno", "Phyno", "Olamide",
        "Flavour", "Tiwa Savage", "Darkoo", "Bella Shmurda", "Ruger", "Young Jonn",
        "Shallipopi", "Savage", "Diamond Platnumz", "KizzDaniel", "Boy Spyce",
    ],
    "Gospel": [
        "Sinach", "Nathaniel Bassey", "Don Moen", "CeCe Winans", "Kirk Franklin",
        "Tasha Cobbs Leonard", "Hillsong", "William McDowell", "Travis Greene",
        "Mercy Chinwo", "Judith Wambui", "Kelvin Momo", "Maranda Curtis", "Zach Williams",
        "Lauren Daigle", "Chris Tomlin", "Koryn Hawthorne", "Jonathan McReynolds",
        "Tori Kelly", "Brian Courtney Wilson", "Tasha Cobbs", "Mary Mary", "Donnie McClurkin",
        "Tope Alabi", "Eben", "Ada Ehi", "Nathaniel Bassey",
    ],
    "Pop": [
        "Taylor Swift", "Ariana Grande", "Dua Lipa", "Billie Eilish", "Ed Sheeran",
        "Bruno Mars", "Justin Bieber", "Charli XCX", "Olivia Rodrigo", "Sabrina Carpenter",
        "The Weeknd", "Harry Styles", "Katy Perry", "Rihanna", "Lady Gaga", "Adele",
        "Miley Cyrus", "Pink", "Post Malone", "Doja Cat", "Nicki Minaj", "Childish Gambino",
        "Charlie Puth", "Shawn Mendes", "Camila Cabello", "Jonas Brothers", "OneRepublic",
        "Maroon 5", "Sia", "Dua Lipa", "Ariana Grande", "Ellie Goulding", "Ava Max",
        "Demi Lovato", "Halsey", "Khalid", "Lizzo", "Shawn Mendes", "Selena Gomez",
    ],
    "Hip-Hop": [
        "Kendrick Lamar", "Drake", "J. Cole", "Eminem", "Travis Scott", "21 Savage",
        "Lil Baby", "Kanye West", "Nicki Minaj", "Megan Thee Stallion", "Lil Wayne",
        "Future", "Metro Boomin", "Cardi B", "50 Cent", "Nas", "Jay-Z", "Snoop Dogg",
        "Dr. Dre", "Ice Cube", "Lil Durk", "Polo G", "Logic", "A$AP Rocky", "Big Sean",
        "Tyga", "Rick Ross", "Meek Mill", "Juice WRLD", "XXXTentacion", "Wiz Khalifa",
        "Schoolboy Q", "Tyler, The Creator", "Denzel Curry", "Offset", "Quavo",
    ],
    "R&B": [
        "SZA", "Frank Ocean", "The Weeknd", "Beyoncé", "Chris Brown", "Ari Lennox",
        "Summer Walker", "Mario", "Usher", "Jazmine Sullivan", "Toni Braxton", "Brandy",
        "Monica", "Keyshia Cole", "Mary J. Blige", "John Legend", "Alicia Keys",
        "H.E.R.", "Daniel Caesar", "Giveon", "Lucky Daye", "PJ Morton", "Victoria Monét",
        "Trey Songz", "Omarion", "Jeremih", "Eric Bellinger", "Lyfe Jennings", "Musiq Soulchild",
    ],
    "Rock": [
        "Coldplay", "Imagine Dragons", "Foo Fighters", "Red Hot Chili Peppers",
        "Linkin Park", "Arctic Monkeys", "Queen", "AC/DC", "Nirvana", "Metallica",
        "U2", "Green Day", "Radiohead", "The Police", "Led Zeppelin", "Pink Floyd",
        "Guns N' Roses", "Bon Jovi", "Pearl Jam", "The Rolling Stones", "Aerosmith",
        "Blink-182", "Fall Out Boy", "Paramore", "My Chemical Romance", "Twenty One Pilots",
        "The Killers", "Muse", "Sting", "The Beatles", "Oasis",
    ],
    "Jazz": [
        "Miles Davis", "John Coltrane", "Ella Fitzgerald", "Louis Armstrong",
        "Nina Simone", "Duke Ellington", "Chet Baker", "Billie Holiday", "Thelonious Monk",
        "Charlie Parker", "Dizzy Gillespie", "Sarah Vaughan", "Count Basie", "Art Blakey",
        "Herbie Hancock", "Cannonball Adderley", "Wes Montgomery", "Johnny Hartman",
        "Dinah Washington", "Nat King Cole", "Diana Krall", "Norah Jones", "Gregory Porter",
        "Chick Corea", "Stan Getz", "Dave Brubeck",
    ],
    "Latin": [
        "Bad Bunny", "J Balvin", "Shakira", "Karol G", "Ricky Martin", "Maluma",
        "Anuel AA", "Sebastián Yatra", "Ozuna", "Daddy Yankee", "Nicky Jam",
        "Romeo Santos", "Manuel Turizo", "Feid", "Myke Towers", "Rauw Alejandro",
        "Farruko", "Paulo Londra", "Camilo", "Jhay Cortez", "Becky G", "Rosalía",
        "Calle 13", "Residente", "Anitta", "Luis Fonsi", "Enrique Iglesias", "Chayanne",
    ],
    "K-Pop": [
        "BTS", "BLACKPINK", "Stray Kids", "NewJeans", "TWICE", "Seventeen", "EXO",
        "IVE", "Red Velvet", "ENHYPEN", "aespa", "NCT 127", "NCT DREAM", "GOT7",
        "Super Junior", "SHINee", "ATEEZ", "TXT", "ITZY", "Girls' Generation", "BIGBANG",
        "PSY", "JYP Entertainment", "LE SSERAFIM", "Kep1er", "Treasure",
    ],
    "Classical": [
        "Ludovic Tanguy", "Yuja Wang", "Lang Lang", "Max Richter", "Yo-Yo Ma",
        "Itzhak Perlman", "André Rieu", "Ludovico Einaudi", "Alicia de Larrocha",
        "Martha Argerich", "Evgeny Kissin", "Jean-Yves Thibaudet", "Hélène Grimaud",
        "David Garrett", "Kathryn Stott", "Anne-Sophie Mutter", "Joshua Bell",
    ],
    "Electronic": [
        "Daft Punk", "Avicii", "Martin Garrix", "Calvin Harris", "Tiësto",
        "David Guetta", "Swedish House Mafia", "Skrillex", "Armin van Buuren",
        "Deadmau5", "Marshmello", "The Chainsmokers", "Zedd", "Alesso", "Kygo",
        "Alan Walker", "Diplo", "DJ Snake", "KSHMR", "Don Diablo", "Nicky Romero",
        "Hardwell", "Steve Aoki", "Afrojack", "R3hab", "Oliver Heldens",
    ],
    "Reggae": [
        "Bob Marley", "Damian Marley", "Shaggy", "Sean Paul", "Ziggy Marley",
        "Sizzla", "Alborosie", "Beenie Man", "Buju Banton", "Sean Kingston",
        "Vybz Kartel", "Popcaan", "Beres Hammond", "Julian Marley", "Steel Pulse",
        "Toots And The Maytals", "Peter Tosh", "Jimmy Cliff", "Inner Circle",
    ],
    "Country": [
        "Taylor Swift", "Luke Bryan", "Dolly Parton", "Blake Shelton", "Kane Brown",
        "Carrie Underwood", "Chris Stapleton", "Kenny Chesney", "Zach Bryan",
        "Morgan Wallen", "Luke Combs", "Jimmie Allen", "Thomas Rhett", "Brooks & Dunn",
        "Miranda Lambert", "Tim McGraw", "Keith Urban", "Alan Jackson", "Reba McEntire",
        "Shania Twain", "Eric Church", "Jason Aldean", "Cody Johnson", "Bailey Zimmerman",
    ],
    "Soul": [
        "Aretha Franklin", "Marvin Gaye", "Stevie Wonder", "Sam Cooke", "Otis Redding",
        "Donny Hathaway", "Bill Withers", "Ray Charles", "Al Green", "Smokey Robinson",
        "Diana Ross", "The Temptations", "Earth Wind & Fire", "Luther Vandross",
        "Anita Baker", "Gladys Knight", "Roberta Flack",
    ],
    "Funk": [
        "James Brown", "Prince", "Earth Wind & Fire", "Parliament", "George Clinton",
        "Bootsy Collins", "Cameo", "Dazz Band", "The Isley Brothers", "Chaka Khan",
        "Sly & The Family Stone", "Funkadelic", "Commodores", "Level 42", "Tower of Power",
    ],
    "Blues": [
        "B.B. King", "Muddy Waters", "John Lee Hooker", "Howlin' Wolf", "Robert Johnson",
        "Buddy Guy", "Eric Clapton", "Etta James", "Albert King", "Gary Clark Jr.",
        "Stevie Ray Vaughan", "Keb' Mo'", "Taj Mahal", "Beth Hart",
    ],
    "Metal": [
        "Metallica", "Slipknot", "Iron Maiden", "System of a Down", "Rammstein",
        "Pantera", "Megadeth", "Black Sabbath", "Iron Maiden", "Gojira", "Tool",
        "Disturbed", "Korn", "Breaking Benjamin", "Five Finger Death Punch", "Avenged Sevenfold",
    ],
    "Folk": [
        "Bob Dylan", "Simon & Garfunkel", "Johnny Cash", "Joni Mitchell", "Nick Drake",
        "Leonard Cohen", "Cat Stevens", "James Taylor", "Paul Simon", "Arlo Guthrie",
        "Fleet Foxes", "The Lumineers", "Hozier", "Mumford & Sons",
    ],
}


def deezer_info(name: str):
    """Retourne (image_url, nb_fan) via Deezer search du nom exact."""
    try:
        with httpx.Client(timeout=15) as c:
            r = c.get("https://api.deezer.com/search/artist", params={"q": name, "limit": 1})
            if r.status_code == 200:
                d = r.json().get("data")
                if d:
                    a = d[0]
                    return (a.get("picture_xl") or a.get("picture"), a.get("nb_fan") or 0)
    except Exception as e:
        print(f"[Deezer] {name}: {e}")
    return (None, 0)


def fetch_existing_names():
    """Noms déjà présents (avec genre) dans la table artists."""
    names = set()
    offset = 0
    with httpx.Client(timeout=20) as c:
        while True:
            r = c.get(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(),
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


def upsert(c: httpx.Client, name: str, category: str, existing: set):
    low = name.strip().lower()
    if low in existing:
        return False  # déjà présent
    img, fans = deezer_info(name)
    payload = {
        "name": name.strip(),
        "image_url": img,
        "genres": [category.lower()],
        "verified": True,
        "followers": fans,
    }
    r = c.post(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(), json=payload)
    if r.status_code < 400:
        existing.add(low)
        return True
    return False


def main():
    existing = fetch_existing_names()
    print(f"Déjà présents: {len(existing)}")
    total_added = 0
    with httpx.Client(timeout=30) as c:
        for category, names in CATALOG.items():
            added = 0
            for name in names:
                try:
                    if upsert(c, name, category, existing):
                        added += 1
                        print(f"  + {name} [{category.lower()}]")
                except Exception as e:
                    print(f"  ! {name}: {e}")
                time.sleep(0.15)
            total_added += added
            print(f"=> {category}: {added} ajoutés")
    print(f"\nTOTAL ajoutés: {total_added}")


if __name__ == "__main__":
    main()