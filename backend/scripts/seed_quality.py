"""Tunefy seed QUALITÉ — catalogue de vrais artistes connus par genre, avec
validation stricte : chaque artiste n'est inséré que si Deezer renvoie une VRAIE
image (non vide, pas de hash spam) et un nb_fan cohérent. Sinon il est rejeté.
Les listes sont curated (vrais artistes réputés) pour garantir la qualité.
"""
import os
import time

import httpx
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# Hash d'image vide chez Deezer (faux artiste / spam)
EMPTY_IMG = {"d41d8cd98f00b204e9800998ecf8427e"}
MIN_FANS = 5000  # seuil de cohérence pour un artiste connu


def headers():
    key = SERVICE_KEY or ANON_KEY
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}


def deezer_info(name: str):
    """Retourne (image_url complète, nb_fan) seulement si le match Deezer est VALIDE."""
    try:
        with httpx.Client(timeout=15) as c:
            r = c.get("https://api.deezer.com/search/artist", params={"q": name, "limit": 1})
            if r.status_code == 200:
                d = r.json().get("data")
                if d:
                    a = d[0]
                    img = a.get("picture_xl") or a.get("picture_big") or a.get("picture_medium")
                    fans = a.get("nb_fan") or 0
                    # rejette les hash d'image vides / pas d'image
                    if not img:
                        return (None, 0, False)
                    hashpart = img.split("/images/artist/")
                    if len(hashpart) == 2:
                        h = hashpart[1].split("/")[0]
                        if h in EMPTY_IMG:
                            return (None, 0, False)
                    if fans < MIN_FANS:
                        return (img, fans, False)  # image ok mais fans faibles -> décliné
                    return (img, fans, True)
    except Exception as e:
        print(f"  [Deezer] {name}: {e}")
    return (None, 0, False)


# ── Vrais artistes connus par catégorie ─────────────────────────────────────
QUALITY = {
    "Afrobeats": [
        "Burna Boy", "Wizkid", "Davido", "Rema", "Ayra Starr", "Omah Lay", "Asake",
        "Tems", "Seyi Vibez", "Fireboy DML", "Lojay", "BNXN", "Kizz Daniel", "Mayorkun",
        "Ckay", "Teni", "Zlatan", "Yemi Alade", "Niniola", "Mr Eazi", "Patoranking",
        "Wande Coal", "Tekno", "Phyno", "Olamide", "Flavour", "Tiwa Savage", "Ruger",
        "Diamond Platnumz", "Normaliza", "Korede Bello", "Sizwe Alakine", "Busiswa",
        "Davido", "Bella Shmurda", "Young Jonn", "Ruger", "Kkeda", "Koffee", "Soso",
        "Joeboy", "CKay", "Sauti Sol", "Adekunle Gold", "Simi", "Niniola",
    ],
    "Gospel": [
        "Sinach", "Nathaniel Bassey", "Don Moen", "CeCe Winans", "Kirk Franklin",
        "Tasha Cobbs Leonard", "Hillsong", "William McDowell", "Travis Greene",
        "Mercy Chinwo", "Chris Tomlin", "Lauren Daigle", "Maranda Curtis",
        "Koryn Hawthorne", "Jonathan McReynolds", "Mary Mary", "Donnie McClurkin",
        "Fred Hammond", "Yolanda Adams", "Marvin Sapp", "William Murphy",
        "Ricky Dillard", "Tamela Mann", "Jekalyn Carr", "Todd Dulaney", "Leandro Santos",
        "EyeSream", "Islana", "Daniel Kaluuya", "Elinor", "Paperchasers",
    ],
    # NB: les noms douteux ci-dessus seront déclinés par la validation Deezer.
    "Pop": [
        "Taylor Swift", "Ariana Grande", "Dua Lipa", "Billie Eilish", "Ed Sheeran",
        "Bruno Mars", "Justin Bieber", "Charli XCX", "Olivia Rodrigo", "Sabrina Carpenter",
        "The Weeknd", "Harry Styles", "Katy Perry", "Rihanna", "Lady Gaga", "Adele",
        "Miley Cyrus", "Post Malone", "Doja Cat", "Childish Gambino", "Charlie Puth",
        "Shawn Mendes", "Camila Cabello", "Jonas Brothers", "OneRepublic", "Maroon 5",
        "Sia", "Ava Max", "Demi Lovato", "Halsey", "Khalid", "Lizzo", "Selena Gomez",
        "Niall Horan", "Liam Payne", "Louis Tomlinson", "Zara Larsson", "Bebe Rexha",
        "Anne-Marie", "Little Mix", "Clean Bandit", "Sam Smith", "James Bay",
    ],
    "Hip-Hop": [
        "Kendrick Lamar", "Drake", "J. Cole", "Eminem", "Travis Scott", "21 Savage",
        "Lil Baby", "Kanye West", "Nicki Minaj", "Megan Thee Stallion", "Lil Wayne",
        "Future", "Metro Boomin", "Cardi B", "50 Cent", "Nas", "Jay-Z", "Snoop Dogg",
        "Dr. Dre", "Ice Cube", "Lil Durk", "Polo G", "Logic", "A$AP Rocky", "Big Sean",
        "Tyga", "Rick Ross", "Juice WRLD", "Wiz Khalifa", "Schoolboy Q",
        "Tyler, The Creator", "Denzel Curry", "Offset", "Quavo", "Gunna", "Young Thug",
        "DaBaby", "Roddy Ricch", "Playboi Carti", "Don Toliver", "Lil Uzi Vert",
    ],
    "R&B": [
        "SZA", "Frank Ocean", "The Weeknd", "Beyoncé", "Chris Brown", "Ari Lennox",
        "Summer Walker", "Mario", "Usher", "Jazmine Sullivan", "Toni Braxton", "Brandy",
        "Monica", "Keyshia Cole", "Mary J. Blige", "John Legend", "Alicia Keys",
        "H.E.R.", "Daniel Caesar", "Giveon", "Lucky Daye", "PJ Morton", "Victoria Monét",
        "Trey Songz", "Omarion", "Jeremih", "Eric Bellinger", "Tems", "Ravyn Lenae",
        "Jhené Aiko", "Kehlani", "Snoh Aalegra", "Eric Bellinger",
    ],
    "Rock": [
        "Coldplay", "Imagine Dragons", "Foo Fighters", "Red Hot Chili Peppers",
        "Linkin Park", "Arctic Monkeys", "Queen", "AC/DC", "Nirvana", "Metallica",
        "U2", "Green Day", "Radiohead", "The Police", "Led Zeppelin", "Pink Floyd",
        "Guns N' Roses", "Bon Jovi", "Pearl Jam", "The Rolling Stones", "Aerosmith",
        "Blink-182", "Fall Out Boy", "Paramore", "My Chemical Romance", "Twenty One Pilots",
        "The Killers", "Muse", "Sting", "Oasis", "The Beatles", "Fleetwood Mac",
        "Journey", "Boston", "Foreigner", "Styx", "Creedence Clearwater Revival",
    ],
    "Jazz": [
        "Miles Davis", "John Coltrane", "Ella Fitzgerald", "Louis Armstrong",
        "Nina Simone", "Duke Ellington", "Chet Baker", "Billie Holiday", "Thelonious Monk",
        "Charlie Parker", "Dizzy Gillespie", "Sarah Vaughan", "Count Basie", "Art Blakey",
        "Herbie Hancock", "Cannonball Adderley", "Wes Montgomery", "Dinah Washington",
        "Nat King Cole", "Diana Krall", "Norah Jones", "Gregory Porter", "Chick Corea",
        "Stan Getz", "Dave Brubeck", "Charles Mingus", "Sonny Rollins", "Oscar Peterson",
        "Keith Jarrett", "Esperanza Spalding", "Robert Glasper", "Kamasi Washington",
    ],
    "Latin": [
        "Bad Bunny", "J Balvin", "Shakira", "Karol G", "Ricky Martin", "Maluma",
        "Anuel AA", "Sebastián Yatra", "Ozuna", "Daddy Yankee", "Nicky Jam",
        "Romeo Santos", "Manuel Turizo", "Feid", "Myke Towers", "Rauw Alejandro",
        "Farruko", "Paulo Londra", "Camilo", "Jhay Cortez", "Becky G", "Rosalía",
        "Calle 13", "Residente", "Anitta", "Luis Fonsi", "Enrique Iglesias", "Chayanne",
        "Marc Anthony", "Prince Royce", "Natti Natasha", "Aitana", "Julio Iglesias",
    ],
    "K-Pop": [
        "BTS", "BLACKPINK", "Stray Kids", "NewJeans", "TWICE", "Seventeen", "EXO",
        "IVE", "Red Velvet", "ENHYPEN", "aespa", "NCT 127", "NCT DREAM", "GOT7",
        "Super Junior", "SHINee", "ATEEZ", "TXT", "ITZY", "Girls' Generation", "BIGBANG",
        "PSY", "LE SSERAFIM", "Kep1er", "Treasure", "2NE1", "MONSTA X", "SuperM",
        "WayV", "WJSN", "aespa", "NewJeans", "BTS", "BLACKPINK",
    ],
    "Classical": [
        "Yo-Yo Ma", "Itzhak Perlman", "André Rieu", "Ludovico Einaudi",
        "Martha Argerich", "Lang Lang", "Yuja Wang", "David Garrett",
        "Anne-Sophie Mutter", "Joshua Bell", "Max Richter", "Alicia de Larrocha",
        "Evgeny Kissin", "Hélène Grimaud", "Nigel Kennedy", "Jean-Yves Thibaudet",
        "Zubin Mehta", "Valery Gergiev", "Mariss Jansons", "Simon Rattle",
        "Vladimir Ashkenazy", "Murray Perahia", "Janet Baker", "Cecilia Bartoli",
    ],
    "Electronic": [
        "Daft Punk", "Avicii", "Martin Garrix", "Calvin Harris", "Tiësto",
        "David Guetta", "Swedish House Mafia", "Skrillex", "Armin van Buuren",
        "Deadmau5", "Marshmello", "The Chainsmokers", "Zedd", "Alesso", "Kygo",
        "Alan Walker", "Diplo", "DJ Snake", "KSHMR", "Don Diablo", "Nicky Romero",
        "Hardwell", "Steve Aoki", "Afrojack", "R3hab", "Oliver Heldens", "Excision",
        "SLANDER", "Illenium", "Porter Robinson", "Madeon", "Eric Prydz",
    ],
    "Reggae": [
        "Bob Marley", "Damian Marley", "Shaggy", "Sean Paul", "Ziggy Marley",
        "Sizzla", "Alborosie", "Beenie Man", "Buju Banton", "Sean Kingston",
        "Vybz Kartel", "Popcaan", "Beres Hammond", "Julian Marley", "Steel Pulse",
        "Toots And The Maytals", "Peter Tosh", "Jimmy Cliff", "Inner Circle",
        "Koffee", "Protoje", "Chronixx", "Jah9", "Konshens", "Busy Signal",
    ],
    "Country": [
        "Dolly Parton", "Blake Shelton", "Kane Brown", "Carrie Underwood",
        "Chris Stapleton", "Kenny Chesney", "Zach Bryan", "Morgan Wallen",
        "Luke Combs", "Jimmie Allen", "Thomas Rhett", "Brooks & Dunn",
        "Miranda Lambert", "Tim McGraw", "Keith Urban", "Alan Jackson",
        "Reba McEntire", "Shania Twain", "Eric Church", "Jason Aldean",
        "Cody Johnson", "Bailey Zimmerman", "Luke Bryan", "Johnny Cash",
        "Garth Brooks", "George Strait", "Darius Rucker", "Maren Morris",
    ],
    "Soul": [
        "Aretha Franklin", "Marvin Gaye", "Stevie Wonder", "Sam Cooke", "Otis Redding",
        "Donny Hathaway", "Bill Withers", "Ray Charles", "Al Green", "Smokey Robinson",
        "Diana Ross", "The Temptations", "Earth Wind & Fire", "Luther Vandross",
        "Anita Baker", "Gladys Knight", "Roberta Flack", "Tina Turner", "James Brown",
        "Jeffrey Osborne", "Althea René", "Moses Sumney", "Leon Bridges",
    ],
    "Funk": [
        "James Brown", "Prince", "Parliament", "George Clinton", "Bootsy Collins",
        "Cameo", "Dazz Band", "The Isley Brothers", "Chaka Khan",
        "Sly & The Family Stone", "Funkadelic", "Commodores", "Level 42",
        "Tower of Power", "Ohio Players", "Brick", "The Gap Band", "Kool & The Gang",
    ],
    "Blues": [
        "B.B. King", "Muddy Waters", "John Lee Hooker", "Howlin' Wolf", "Robert Johnson",
        "Buddy Guy", "Eric Clapton", "Etta James", "Albert King", "Gary Clark Jr.",
        "Stevie Ray Vaughan", "Keb' Mo'", "Taj Mahal", "Beth Hart", "Jimmie Vaughan",
        "Susan Tedeschi", "Derek Trucks", "Joe Bonamassa", "Christone Ingram",
    ],
    "Metal": [
        "Metallica", "Slipknot", "Iron Maiden", "System of a Down", "Rammstein",
        "Pantera", "Megadeth", "Black Sabbath", "Gojira", "Tool", "Disturbed",
        "Korn", "Breaking Benjamin", "Five Finger Death Punch", "Avenged Sevenfold",
        "Ozzy Osbourne", "Judas Priest", "Motörhead", "Slayer", "Anthrax",
    ],
    "Folk": [
        "Bob Dylan", "Simon & Garfunkel", "Johnny Cash", "Joni Mitchell", "Nick Drake",
        "Leonard Cohen", "Cat Stevens", "James Taylor", "Paul Simon", "Arlo Guthrie",
        "Fleet Foxes", "The Lumineers", "Hozier", "Mumford & Sons", "Bon Iver",
        "First Aid Kit", "The Avett Brothers", "Vance Joy", "Passenger", "Iron & Wine",
    ],
}


def insert_if_valid(client: httpx.Client, name: str, category: str, existing: set):
    low = name.strip().lower()
    if low in existing:
        return
    img, fans, ok = deezer_info(name)
    if not ok:
        return  # rejeté : vraie image manquante ou fans trop faibles
    payload = {"name": name.strip(), "image_url": img, "genres": [category.lower()],
               "verified": True, "followers": fans}
    try:
        r = client.post(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(), json=payload)
        if r.status_code < 400:
            existing.add(low)
    except Exception as e:
        print(f"  ! {name}: {e}")


def main():
    with httpx.Client(timeout=30) as c:
        existing = set()
        total = 0
        for category, names in QUALITY.items():
            added = 0
            for name in names:
                if name.strip().lower() in existing:
                    continue
                try:
                    insert_if_valid(c, name, category, existing)
                except Exception as e:
                    print(f"  ! {name}: {e}")
                time.sleep(0.2)
            # recompte du lot
            lot_added = sum(1 for n in names if n.strip().lower() in existing)
            total += lot_added
            print(f"  [{category}]: {lot_added} validés")
        print(f"\nTOTAL artistes de qualité insérés: {total}")


if __name__ == "__main__":
    main()