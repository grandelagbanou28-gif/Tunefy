"""Tunefy Deezer enrich — remplit image_url + followers (+ genre valide) pour les
artistes qui n'ont pas d'image, via Deezer search du nom exact.
Itère paginé sur artists (image_url is null), met à jour par id.
--limit: borne le nombre d'artistes traités pour permettre des passes courtes.
--attempts: nb de passes (rattrape les rate-limits).
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
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}


def deezer_info(name: str):
    try:
        with httpx.Client(timeout=15) as c:
            r = c.get("https://api.deezer.com/search/artist", params={"q": name, "limit": 1})
            if r.status_code == 200:
                d = r.json().get("data")
                if d:
                    a = d[0]
                    return (a.get("picture_xl") or a.get("picture") or a.get("picture_medium"),
                            a.get("nb_fan") or 0)
    except Exception as e:
        print(f"  [Deezer] {name}: {e}")
    return (None, 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--attempts", type=int, default=1)
    args = ap.parse_args()

    client = httpx.Client(timeout=30)
    updated = 0
    no_match = 0

    for _ in range(max(1, args.attempts)):
        offset = 0
        while True:
            r = client.get(f"{SUPABASE_URL}/rest/v1/artists",
                           headers=headers(),
                           params={"select": "id,name", "image_url": "is.null",
                                   "genres": "not.is.null", "limit": 200, "offset": offset})
            if r.status_code != 200:
                print(f"GET err {r.status_code}: {r.text}")
                return
            rows = r.json()
            if not rows:
                break
            for row in rows:
                name = row.get("name")
                if not name:
                    continue
                if args.limit and (updated + no_match) >= args.limit:
                    client.close()
                    print(f"[borné] updated={updated} no_match={no_match}")
                    return
                img, fans = deezer_info(name)
                if img:
                    try:
                        pr = client.patch(
                            f"{SUPABASE_URL}/rest/v1/artists?id=eq.{row['id']}",
                            headers=headers(), json={"image_url": img, "followers": fans})
                        if pr.status_code < 400:
                            updated += 1
                    except Exception as e:
                        print(f"  ! {name}: {e}")
                else:
                    no_match += 1
                if (updated + no_match) % 50 == 0:
                    print(f"... {updated + no_match} traités (updated={updated}, no_match={no_match})")
                time.sleep(0.2)
            offset += 200
            if len(rows) < 200:
                break
    client.close()
    print(f"\nImage/fans mis à jour: {updated} | sans correspondance Deezer: {no_match}")


if __name__ == "__main__":
    main()