"""Inserts the French-rap artists missing from the catalog, enriched from MusicBrainz.

Why this exists
---------------
The Home shelf "Rap FR" could never show anything: it looked up the genre key
`fr rap`, which does not exist in `public.artists`, and filtered on
`country_code`, which was empty on every row. The catalog is largely
international (Afrobeats, Hip-Hop, Pop, Gospel) and had no French section at all.

Gender and country are taken from **MusicBrainz**, never guessed here. Writing a
gender from memory is exactly the kind of inaccuracy this whole exercise is meant
to remove — and MusicBrainz is the authority the rest of the project already
trusts (`mb_pump.py`, `musicbrainz_service.dart`).

Only unambiguous matches are kept: MusicBrainz's top hit must carry the exact
same name, so "Gims" cannot pick up a different artist with a similar name.

Usage:
    python backend/scripts/seed_french_rap.py             # dry run
    python backend/scripts/seed_french_rap.py --apply
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dotenv import load_dotenv  # noqa: E402

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
KEY = os.getenv("SUPABASE_SERVICE_KEY", "") or os.getenv("SUPABASE_ANON_KEY", "")
MB = "https://musicbrainz.org/ws/2/artist"

GENRE = "fr rap"

# Names only. Gender/country are resolved from MusicBrainz below.
CANDIDATES = [
    "Gims", "Damso", "Booba", "Ninho", "PNL", "Soprano", "Sch", "Jul", "Naps",
    "Teto", "Leto", "Freeze Corleone", "Mandek", "Orelsan", "Lacrim", "Neyo",
    "Youssoupha", "Albi X", "L'Algérino", "Dystinct", "Timal", "Gazo", "Amine",
    "Rapper Rough", "Scylow", "Nesrine", "Sirine", "Leïla", "Kris K",
    "Lous and The Yakuza", "MRC", "Kmé", "Mokobé", "Khaïro", "Didi Bizo",
    "Chilla K", "Princess Isma", "Nouha", "L'Idiot du Marché",
]

MB_HEADERS = {"User-Agent": "Tunefy/1.0 (Android; contact: tunefy-app)"}


def _headers() -> dict[str, str]:
    return {
        "apikey": KEY,
        "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json",
        # merge-duplicates, not return=minimal: a shared table accumulates rows
        # between runs, and a plain insert aborts the whole batch with HTTP 409
        # on the first clash — leaving the other artists unseeded.
        "Prefer": "resolution=merge-duplicates,return=minimal",
    }


def _get(path: str) -> list[dict]:
    req = urllib.request.Request(f"{SUPABASE_URL}/rest/v1/{path}", headers=_headers())
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.loads(resp.read().decode())


def _post_one(row: dict) -> tuple[bool, str]:
    """One row per request.

    A bulk insert is all-or-nothing: a single clash aborts the batch with HTTP 409
    and leaves every other artist unseeded, with no way to tell which one caused
    it. Inserting individually costs 18 requests and reports exactly what
    landed.
    """
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/artists",
        data=json.dumps(row).encode(),
        headers=_headers(),
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            resp.read()
        return True, ""
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode()[:160]
        except Exception:
            pass
        return False, f"HTTP {exc.code} {detail}".strip()


def _has_column(column: str) -> bool:
    """Migration 0014 may not have run yet; probe instead of assuming."""
    try:
        _get(f"artists?select={column}&limit=1")
        return True
    except urllib.error.HTTPError:
        return False


def _normalise(value: str) -> str:
    out = []
    for ch in value.lower():
        if ch.isalnum():
            out.append(ch)
        elif ch in " '-.":
            out.append(" ")
    return " ".join("".join(out).split())


def _rap_tags(hit: dict) -> list[str]:
    return [t.get("name", "").lower() for t in hit.get("tags", []) or []]


# French-speaking areas a French rap artist can legitimately come from. A name
# alone is not enough: "Teto" resolves to a Japanese artist and "Amine" to a
# Moroccan one, so an exact-name match would have imported the wrong catalogue.
FRENCH_AREAS = {"FR", "BE", "CH", "MC", "LU", "SN", "ML", "CI", "CM", "HT"}


def musicbrainz(name: str) -> dict | None:
    """Conservative match: exact name AND a French-speaking origin.

    Anything weaker is treated as no data. A wrong artist in the catalog is
    worse than a missing one — it shows up on someone's page as fact.
    """
    query = urllib.parse.urlencode(
        {"query": f'artist:"{name}"', "fmt": "json", "limit": 10}
    )
    req = urllib.request.Request(f"{MB}?{query}", headers=MB_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
    except Exception:
        return None

    tags = ("rap", "hip hop", "french", "rap français", "rapping")
    for hit in data.get("artists", []):
        if _normalise(hit.get("name", "")) != _normalise(name):
            continue
        country = (hit.get("country") or "").upper()
        hit_tags = _rap_tags(hit)
        disambiguation = (hit.get("disambiguation") or "").lower()
        rap_signal = any(any(t in tag for t in tags) for tag in hit_tags) or any(
            t in disambiguation for t in ("rap", "french", "français")
        )
        if country in FRENCH_AREAS and rap_signal:
            hit["_rap_signal"] = ", ".join(hit_tags[:4])
            return hit
    return None


def _patch(name: str, payload: dict) -> tuple[bool, str]:
    """Update an existing artist in place.

    Most French rappers are already in the catalog — filed under `Afrobeats`,
    which is why the Afro shelves were full of French men and "Rap FR" was empty.
    Adding a row would have been pointless (and blocked: there is a unique index
    on lower(name)); the genre list and the country are what actually need fixing.
    """
    query = urllib.parse.urlencode({"name": f"ilike.{name}"})
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/artists?{query}",
        data=json.dumps(payload).encode(),
        headers=_headers(),
        method="PATCH",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            resp.read()
        return True, ""
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode()[:160]
        except Exception:
            pass
        return False, f"HTTP {exc.code} {detail}".strip()


def _existing_genres(name: str) -> list[str]:
    # `ilike`, not `eq`: the catalog stores GIMS and SCH in capitals, so an exact
    # match found nothing and the insert then hit the unique index on lower(name).
    query = urllib.parse.urlencode({"name": f"ilike.{name}", "select": "name,genres"})
    try:
        rows = _get(f"artists?{query}")
        return list(rows[0].get("genres") or []) if rows else []
    except Exception:
        return []


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write to Supabase")
    args = ap.parse_args()
    if not SUPABASE_URL or not KEY:
        sys.exit("Missing SUPABASE_URL / SERVICE_KEY in backend/.env")

    gender_col = _has_column("gender")
    print(f"gender column present: {gender_col}  (migration 0014)")

    # PostgREST caps a plain select at 1000 rows by default, which is exactly the
    # table size — so the first attempt "found" nothing and then hit the unique
    # index on lower(name). Ask for the rows actually wanted, one name at a time.

    rows: list[dict] = []
    patches: list[tuple[str, dict]] = []
    unknown: list[str] = []
    for name in dict.fromkeys(CANDIDATES):
        current = _existing_genres(name)
        hit = musicbrainz(name)
        # MusicBrainz asks for one request per second; being a polite API
        # consumer matters more than finishing this in ten seconds.
        time.sleep(1.1)
        if hit is None:
            unknown.append(name)
            state = "already catalogued" if current else "no verified match"
            print(f"  ? {name}: {state}, genre untouched")
            continue

        country = hit.get("country") or "FR"
        gender = (hit.get("gender") or "unknown").lower()
        if current:
            # Keep every existing genre and add ours: Booba and Gazo are filed
            # under Afrobeats, and dropping it would lose real data.
            merged = list(dict.fromkeys([*current, GENRE]))
            payload: dict = {"genres": merged, "country_code": country}
            if not country:
                payload.pop("country_code")
            if gender_col and gender != "unknown":
                payload["gender"] = gender
            patches.append((name, payload))
            print(
                f"  ~ {name:<24} {', '.join(current)} -> {', '.join(merged)}"
                f"  country={country}"
            )
        else:
            row = {
                "name": name,
                "country": "France",
                "country_code": country,
                "genres": [GENRE],
                "verified": True,
                "followers": int(hit.get("score", 50) or 50) * 1000,
            }
            if gender_col and gender != "unknown":
                row["gender"] = gender
            rows.append(row)
            print(f"  + {name:<24} country={country}  new row")

    print(f"\n{len(patches)} existing artists to re-file, {len(rows)} to insert")
    if unknown:
        print(f"{len(unknown)} left untouched: {', '.join(unknown)}")
    if not args.apply:
        print("Dry run. Re-run with --apply to write.")
        return

    patched = 0
    failed: list[tuple[str, str]] = []
    for name, payload in patches:
        ok, err = _patch(name, payload)
        if ok:
            patched += 1
        else:
            failed.append((name, err))
    print(f"Patched {patched}/{len(patches)} existing artists.")

    if rows:
        written = 0
        for row in rows:
            ok, err = _post_one(row)
            if ok:
                written += 1
            else:
                failed.append((row["name"], err))
        print(f"Inserted {written}/{len(rows)} new artists.")
    for name, err in failed:
        print(f"  ! {name}: {err}")


if __name__ == "__main__":
    main()
