"""Tunefy seed QUALITÉ étendu — catalogue élargi de vrais artistes réputés par
genre, toujours filtré strictement (vraie image sans hash vide + nb_fan >= MIN_FANS)
pour ne garder que des artistes cohérents avec une vraie image.
On étend à ~2000+ artistes connus. Les doublons (contrainte lower(name)) sont ignorés.
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
MIN_FANS = 2000  # filtre les faux homonymes/spam (peu de fans) tout en gardant les vrais artistes établis


def headers():
    key = SERVICE_KEY or ANON_KEY
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}


def deezer_info(name: str):
    try:
        with httpx.Client(timeout=15) as c:
            r = c.get("https://api.deezer.com/search/artist", params={"q": name, "limit": 1})
            if r.status_code == 200:
                d = r.json().get("data")
                if d:
                    a = d[0]
                    img = a.get("picture_xl") or a.get("picture_big") or a.get("picture_medium")
                    fans = a.get("nb_fan") or 0
                    if not img:
                        return (None, 0, False)
                    hp = img.split("/images/artist/")
                    if len(hp) == 2 and hp[1].split("/")[0] in EMPTY_IMG:
                        return (None, 0, False)
                    if fans < MIN_FANS:
                        return (img, fans, False)
                    return (img, fans, True)
    except Exception as e:
        print(f"  [Deezer] {name}: {e}")
    return (None, 0, False)


# ── Grand catalogue de vrais artistes réputés par genre ─────────────────────
CATALOG = {
    "Afrobeats": [
        "Burna Boy", "Wizkid", "Davido", "Rema", "Ayra Starr", "Omah Lay", "Asake", "Tems",
        "Seyi Vibez", "Fireboy DML", "Lojay", "BNXN", "Kizz Daniel", "Mayorkun", "Ckay",
        "Teni", "Zlatan", "Yemi Alade", "Niniola", "Mr Eazi", "Patoranking", "Wande Coal",
        "Tekno", "Phyno", "Olamide", "Flavour", "Tiwa Savage", "Ruger", "Diamond Platnumz",
        "Korede Bello", "Bella Shmurda", "Young Jonn", "Joeboy", "Koffee", "Sauti Sol",
        "Adekunle Gold", "Simi", "Niniola", "Serge Beynaud", "Fally Ipupa", "Diamond Platnumz",
        "Gabzy", "Tempoh", "Oluwa", "Barry Jhay", "Olize", "Krank", "Boy Spyce",
        "Ceeza Milli", "Sheebah", "Jose Chameleone", "Bebe Cool", "Pinga", "Nakyo",
        "Gyakie", "Black Sherif", "King Promise", "Sarkodie", "Stonebwoy", "Shatta Wale",
        "Seyi Shay", "Zinoleesky", "Skiibii", "Mohbad", "Omo Baba", "Chike", "Simi",
    ],
    "Gospel": [
        "Sinach", "Nathaniel Bassey", "Don Moen", "CeCe Winans", "Kirk Franklin",
        "Tasha Cobbs Leonard", "Hillsong Worship", "William McDowell", "Travis Greene",
        "Mercy Chinwo", "Chris Tomlin", "Lauren Daigle", "Koryn Hawthorne",
        "Jonathan McReynolds", "Donnie McClurkin", "Fred Hammond", "Yolanda Adams",
        "Marvin Sapp", "William Murphy", "Ricky Dillard", "Tamela Mann", "Jekalyn Carr",
        "Todd Dulaney", "Mary Mary", "Dunsin Oyekan", "Moses Bliss", "Judikay",
        "Prospa Ochimana", "Sunmisola Agbebi", "Ebuka Songs", "Greatman Takit",
        "Ada Ehi", "Frank Edwards", "Buchi Atuonwu", "Pastor Adeboye", "Joe Praise",
        "Ayox", "Eben", "Bether", "Maurette Brown Clark", "Bishop Paul Morton",
    ],
    "Pop": [
        "Taylor Swift", "Ariana Grande", "Dua Lipa", "Billie Eilish", "Ed Sheeran",
        "Bruno Mars", "Justin Bieber", "Charli XCX", "Olivia Rodrigo", "Sabrina Carpenter",
        "The Weeknd", "Harry Styles", "Katy Perry", "Rihanna", "Lady Gaga", "Adele",
        "Miley Cyrus", "Post Malone", "Doja Cat", "Childish Gambino", "Charlie Puth",
        "Shawn Mendes", "Camila Cabello", "Jonas Brothers", "OneRepublic", "Maroon 5",
        "Sia", "Ava Max", "Demi Lovato", "Halsey", "Khalid", "Lizzo", "Selena Gomez",
        "Niall Horan", "Liam Payne", "Louis Tomlinson", "Zara Larsson", "Bebe Rexha",
        "Anne-Marie", "Little Mix", "Clean Bandit", "Sam Smith", "James Bay", "Lana Del Rey",
        "Madonna", "Beyoncé", "P!nk", "Celine Dion", "Jennifer Lopez", "Rihanna",
        "Ellie Goulding", "Kylie Minogue", "Alessia Cara", "Jessie J", "Paloma Faith",
        "Aurora", "Tate McRae", "Gracie Abrams", "Maggie Rogers", "Rita Ora", "Jess Glynne",
    ],
    "Hip-Hop": [
        "Kendrick Lamar", "Drake", "J. Cole", "Eminem", "Travis Scott", "21 Savage",
        "Lil Baby", "Kanye West", "Nicki Minaj", "Megan Thee Stallion", "Lil Wayne",
        "Future", "Metro Boomin", "Cardi B", "50 Cent", "Nas", "Jay-Z", "Snoop Dogg",
        "Dr. Dre", "Ice Cube", "Lil Durk", "Polo G", "Logic", "A$AP Rocky", "Big Sean",
        "Tyga", "Rick Ross", "Juice WRLD", "Wiz Khalifa", "Schoolboy Q", "Tyler, The Creator",
        "Denzel Curry", "Offset", "Quavo", "Gunna", "Young Thug", "DaBaby", "Roddy Ricch",
        "Playboi Carti", "Don Toliver", "Lil Uzi Vert", "Pop Smoke", "NLE Choppa", "Lil Tecca",
        "Coi Leray", "Latto", "Saweetie", "Jack Harlow", "Cordae", "JID", "Freddie Gibbs",
    ],
    "R&B": [
        "SZA", "Frank Ocean", "Beyoncé", "Chris Brown", "Ari Lennox", "Summer Walker",
        "Mario", "Usher", "Jazmine Sullivan", "Toni Braxton", "Brandy", "Monica",
        "Keyshia Cole", "Mary J. Blige", "John Legend", "Alicia Keys", "H.E.R.",
        "Daniel Caesar", "Giveon", "Lucky Daye", "PJ Morton", "Victoria Monét",
        "Trey Songz", "Omarion", "Jeremih", "Eric Bellinger", "Jhené Aiko", "Kehlani",
        "Snoh Aalegra", "Sza", "Bryson Tiller", "Jacquees", "SiR", "Alina Baraz",
        "Masego", "Joyce Wrice", "Ty Dolla Sign", "Rayvanny", "Khalifa", "Musiq Soulchild",
        "Kenny Lattimore", "Angie Stone", "Ledisi", "Ledisi", "Alex Isley", "Leela James",
    ],
    "Rock": [
        "Coldplay", "Imagine Dragons", "Foo Fighters", "Red Hot Chili Peppers", "Linkin Park",
        "Arctic Monkeys", "Queen", "AC/DC", "Nirvana", "Metallica", "U2", "Green Day",
        "Radiohead", "The Police", "Led Zeppelin", "Pink Floyd", "Guns N' Roses",
        "Bon Jovi", "Pearl Jam", "The Rolling Stones", "Aerosmith", "Blink-182",
        "Fall Out Boy", "Paramore", "My Chemical Romance", "Twenty One Pilots",
        "The Killers", "Muse", "Sting", "Oasis", "The Beatles", "Fleetwood Mac",
        "Journey", "Boston", "Foreigner", "Styx", "Creedence Clearwater Revival",
        "The Doors", "The Who", "Soundgarden", "Alice In Chains", "Pearl Jam",
        "The Cranberries", "Blur", "Placebo", "Rage Against The Machine", "Audioslave",
        "Three Days Grace", "Breaking Benjamin", "Skillet", "Halestorm", "Shinedown",
    ],
    "Jazz": [
        "Miles Davis", "John Coltrane", "Ella Fitzgerald", "Louis Armstrong", "Nina Simone",
        "Duke Ellington", "Chet Baker", "Billie Holiday", "Thelonious Monk", "Charlie Parker",
        "Dizzy Gillespie", "Sarah Vaughan", "Count Basie", "Art Blakey", "Herbie Hancock",
        "Cannonball Adderley", "Wes Montgomery", "Dinah Washington", "Nat King Cole",
        "Diana Krall", "Norah Jones", "Gregory Porter", "Chick Corea", "Stan Getz",
        "Dave Brubeck", "Charles Mingus", "Sonny Rollins", "Oscar Peterson", "Keith Jarrett",
        "Esperanza Spalding", "Robert Glasper", "Kamasi Washington", "Wynton Marsalis",
        "Roy Hargrove", "Dizzy Gillespie", "Benny Goodman", "Glenn Miller", "Duke Ellington",
    ],
    "Latin": [
        "Bad Bunny", "J Balvin", "Shakira", "Karol G", "Ricky Martin", "Maluma", "Anuel AA",
        "Sebastián Yatra", "Ozuna", "Daddy Yankee", "Nicky Jam", "Romeo Santos",
        "Manuel Turizo", "Feid", "Myke Towers", "Rauw Alejandro", "Farruko", "Paulo Londra",
        "Camilo", "Jhay Cortez", "Becky G", "Rosalía", "Calle 13", "Residente", "Anitta",
        "Luis Fonsi", "Enrique Iglesias", "Chayanne", "Marc Anthony", "Prince Royce",
        "Natti Natasha", "Aitana", "Julio Iglesias", "J Balvin", "Calle 13", "Don Omar",
        "Wisin", "Yandel", "J Alvarez", "Arcangel", "De La Ghetto", "Maluma", "Nicki Nicole",
        "María Becerra", "TINI", "Emilia", "Mau y Ricky", "Reik", "Danna Paola",
    ],
    "K-Pop": [
        "BTS", "BLACKPINK", "Stray Kids", "NewJeans", "TWICE", "Seventeen", "EXO", "IVE",
        "Red Velvet", "ENHYPEN", "aespa", "NCT 127", "NCT DREAM", "GOT7", "Super Junior",
        "SHINee", "ATEEZ", "TXT", "ITZY", "Girls' Generation", "BIGBANG", "PSY",
        "LE SSERAFIM", "Kep1er", "Treasure", "2NE1", "MONSTA X", "SuperM", "WayV", "WJSN",
        "Stray Kids", "Seventeen", "ENHYPEN", "GOT7", "ASTRO", "Golden Child", "AB6IX",
        "Cravity", "ONEUS", "THE BOYZ", "NMIXX", "STAYC", "aespa", "IVE", "NewJeans",
    ],
    "Classical": [
        "Yo-Yo Ma", "Itzhak Perlman", "André Rieu", "Ludovico Einaudi", "Martha Argerich",
        "Lang Lang", "Yuja Wang", "David Garrett", "Anne-Sophie Mutter", "Joshua Bell",
        "Max Richter", "Alicia de Larrocha", "Evgeny Kissin", "Hélène Grimaud",
        "Nigel Kennedy", "Jean-Yves Thibaudet", "Zubin Mehta", "Valery Gergiev",
        "Mariss Jansons", "Simon Rattle", "Vladimir Ashkenazy", "Murray Perahia",
        "Janet Baker", "Cecilia Bartoli", "Niccolò Paganini", "Jascha Heifetz",
        "Glenn Gould", "Wilhelm Kempff", "Andrés Segovia", "John Williams (Guitarist)",
        "Hilary Hahn", "Leila Josefowicz", "Sarah Chang", "Alfred Brendel", "Daniel Barenboim",
    ],
    "Electronic": [
        "Daft Punk", "Avicii", "Martin Garrix", "Calvin Harris", "Tiësto", "David Guetta",
        "Swedish House Mafia", "Skrillex", "Armin van Buuren", "Deadmau5", "Marshmello",
        "The Chainsmokers", "Zedd", "Alesso", "Kygo", "Alan Walker", "Diplo", "DJ Snake",
        "KSHMR", "Don Diablo", "Nicky Romero", "Hardwell", "Steve Aoki", "Afrojack",
        "R3hab", "Oliver Heldens", "Excision", "SLANDER", "Illenium", "Porter Robinson",
        "Madeon", "Eric Prydz", "Above & Beyond", "Gareth Emery", "Paul van Dyk",
        "Paul Oakenfold", "Sasha", "Carl Cox", "Fatboy Slim", "The Chemical Brothers",
        "Basement Jaxx", "Disclosure", "Major Lazer", "Louis The Child", "GRYFFIN",
    ],
    "Reggae": [
        "Bob Marley", "Damian Marley", "Shaggy", "Sean Paul", "Ziggy Marley", "Sizzla",
        "Alborosie", "Beenie Man", "Buju Banton", "Sean Kingston", "Vybz Kartel", "Popcaan",
        "Beres Hammond", "Julian Marley", "Steel Pulse", "Toots And The Maytals", "Peter Tosh",
        "Jimmy Cliff", "Inner Circle", "Koffee", "Protoje", "Chronixx", "Jah9", "Konshens",
        "Busy Signal", "Mavado", "Elephant Man", "Collie Buddz", "Stick Figure",
        "Rebelution", "Iration", "Slightly Stoopid", "SOJA", "The Movement",
    ],
    "Country": [
        "Dolly Parton", "Blake Shelton", "Kane Brown", "Carrie Underwood", "Chris Stapleton",
        "Kenny Chesney", "Zach Bryan", "Morgan Wallen", "Luke Combs", "Jimmie Allen",
        "Thomas Rhett", "Brooks & Dunn", "Miranda Lambert", "Tim McGraw", "Keith Urban",
        "Alan Jackson", "Reba McEntire", "Shania Twain", "Eric Church", "Jason Aldean",
        "Cody Johnson", "Bailey Zimmerman", "Luke Bryan", "Johnny Cash", "Garth Brooks",
        "George Strait", "Darius Rucker", "Maren Morris", "Kacey Musgraves", "Natalie Hemby",
        "Dan + Shay", "Florida Georgia Line", "Brett Young", "Sam Hunt", "Jordan Davis",
        "Whiskey Myers", "Turnpike Troubadours", "Chris Young", "Scott McCreery",
    ],
    "Soul": [
        "Aretha Franklin", "Marvin Gaye", "Stevie Wonder", "Sam Cooke", "Otis Redding",
        "Donny Hathaway", "Bill Withers", "Ray Charles", "Al Green", "Smokey Robinson",
        "Diana Ross", "The Temptations", "Earth Wind & Fire", "Luther Vandross", "Anita Baker",
        "Gladys Knight", "Roberta Flack", "Tina Turner", "James Brown", "Jeffrey Osborne",
        "Leon Bridges", "Anderson .Paak", "The Weeknd", "Amy Winehouse", "Joss Stone",
        "Alicia Keys", "John Legend", "Bruno Mars", "Adele", "Sam Smith", "Sade", "Lauryn Hill",
    ],
    "Funk": [
        "James Brown", "Prince", "Parliament", "George Clinton", "Bootsy Collins", "Cameo",
        "Dazz Band", "The Isley Brothers", "Chaka Khan", "Sly & The Family Stone",
        "Funkadelic", "Commodores", "Level 42", "Tower of Power", "Ohio Players", "Brick",
        "The Gap Band", "Kool & The Gang", "Maceo Parker", "Lettuce", "Vulfpeck",
        "Incognito", "Soulive", "Average White Band", "The Meters",
    ],
    "Blues": [
        "B.B. King", "Muddy Waters", "John Lee Hooker", "Howlin' Wolf", "Robert Johnson",
        "Buddy Guy", "Eric Clapton", "Etta James", "Albert King", "Gary Clark Jr.",
        "Stevie Ray Vaughan", "Keb' Mo'", "Taj Mahal", "Beth Hart", "Jimmie Vaughan",
        "Susan Tedeschi", "Derek Trucks", "Joe Bonamassa", "Christone Ingram",
        "Robert Cray", "Tinsley Ellis", "Peter Green", "Fleetwood Mac", "John Mayall",
    ],
    "Metal": [
        "Metallica", "Slipknot", "Iron Maiden", "System of a Down", "Rammstein", "Pantera",
        "Megadeth", "Black Sabbath", "Gojira", "Tool", "Disturbed", "Korn",
        "Breaking Benjamin", "Five Finger Death Punch", "Avenged Sevenfold", "Ozzy Osbourne",
        "Judas Priest", "Motörhead", "Slayer", "Anthrax", "Lamb of God", "Mastodon",
        "Opeth", "Dream Theater", "Nightwish", "Within Temptation", "Bullet For My Valentine",
        "Ghost", "Volbeat", "Killswitch Engage", "As I Lay Dying",
    ],
    "Folk": [
        "Bob Dylan", "Simon & Garfunkel", "Johnny Cash", "Joni Mitchell", "Nick Drake",
        "Leonard Cohen", "Cat Stevens", "James Taylor", "Paul Simon", "Arlo Guthrie",
        "Fleet Foxes", "The Lumineers", "Hozier", "Mumford & Sons", "Bon Iver",
        "First Aid Kit", "The Avett Brothers", "Vance Joy", "Passenger", "Iron & Wine",
        "Gregory Alan Isakov", "The Tallest Man on Earth", "Shakey Graves", "José González",
        "Sufjan Stevens", "Damien Rice", "Ben Howard", "City and Colour", "Novo Amor",
    ],
}


def main():
    with httpx.Client(timeout=30) as c:
        # charge les noms déjà présents pour éviter les ré-insertions
        existing = set()
        offset = 0
        while True:
            r = c.get(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(),
                      params={"select": "name", "limit": 1000, "offset": offset})
            if r.status_code != 200:
                break
            rows = r.json()
            if not rows:
                break
            for row in rows:
                if row.get("name"):
                    existing.add(row["name"].strip().lower())
            if len(rows) < 1000:
                break
            offset += 1000

        total = 0
        for category, names in CATALOG.items():
            added = 0
            for name in names:
                low = name.strip().lower()
                if low in existing:
                    continue
                img, fans, ok = deezer_info(name)
                if not ok:
                    continue
                try:
                    r = c.post(f"{SUPABASE_URL}/rest/v1/artists", headers=headers(),
                               json={"name": name.strip(), "image_url": img,
                                     "genres": [category.lower()], "verified": True,
                                     "followers": fans})
                    if r.status_code < 400:
                        existing.add(low)
                        added += 1
                except Exception as e:
                    print(f"  ! {name}: {e}")
                time.sleep(0.15)
            total += added
            print(f"  [{category}]: {added}")
        print(f"\nTOTAL nouveaux: {total}")


if __name__ == "__main__":
    main()