<p align="center">
  <img src="assets/logo.png" alt="Tunefy-Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Ein leistungsfähiger, auf Datenschutz ausgerichteter Musikclient, gebaut mit Flutter.</strong><br/>
  Ohne Werbung · Offline · AI DJ · Synchrone & übersetzte Lyrics · Liquid Glass UI · 15 Quellen · Kein Konto erforderlich
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Version" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Plattform" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Sprachen" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Lizenz" />
</p>

<p align="center">
  <a href="#-key-features">Funktionen</a> ·
  <a href="#-localisation">Sprachen</a> ·
  <a href="#-screenshots">Screenshots</a> ·
  <a href="#-architecture">Architektur</a> ·
  <a href="#-setup--installation">Einrichtung</a> ·
  <a href="#-backend--streaming-servers">Server</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.fo.md">Fongbé</a> ·
  <a href="README.es.md">Español</a> ·
  <b>Deutsch</b> ·
  <a href="README.pt.md">Português</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.hi.md">हिन्दी</a> ·
  <a href="README.id.md">Bahasa Indonesia</a> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy ist ein funktionsreicher, auf Datenschutz ausgerichteter Musikclient, gebaut mit Flutter. Er streamt aus
**15+ offenen und schlüsselfreien Quellen** mit automatischer Fallback-Kaskade, sodass ein Titel, der bei einem
Anbieter fehlschlägt, beim nächsten abgespielt wird. Er bietet ein Premium-Erlebnis ohne Werbung mit Wiedergabe im
Hintergrund, Offline-Downloads, synchronisierten **und übersetzten** Lyrics, einem **AI DJ**, Internetradio,
Konzerten, gemeinsamen Blend-Wiedergabelisten, einer modernen Liquid Glass UI und intelligentem
Hintergrund-Caching – mit oder ohne Konto.

> [!NOTE]
> Tunefy wird direkt aus diesem Repository verteilt (APK-Releases). Es ist **nicht** im
> Google Play Store verfügbar.

---

## 🚀 Hauptfunktionen

### 🎨 Liquid Glass UI/UX
- **Dynamische Glassmorphic-Themes** — Premium-Darstellung in Dark- und Light-Modus über `liquid_glass_easy`. Der Light-Modus verwendet einen halbtransparenten weißen Farbton, der sich dem Albumcover anpasst.
- **Eigene Shader & Blur** — Hochleistungs-Mattglas-Panels und -Overlays, die sich den Farben des Artworks anpassen.
- **Kontrastbewusste Elemente** — Symbole der Statusleiste, Bedienelemente, Schieberegler und Menüs invertieren automatisch für bessere Lesbarkeit.
- **Optimierung für große Displays & Desktop** — Responsive Player-Layouts (bis zu 1300px), zentrierte Dialoge und eine eigene Suchleiste oben für Desktop/Tablet.

### 🎧 Immersives Audio, Lyrics & Karaoke
- **Karaoke Wort für Wort** — Die Wörter färben sich in Echtzeit, während der Künstler singt (60+ FPS).
- **Zeilenweiser synchronisierter Sweep** — Fortschreitender Sweep-Effekt mit Hervorhebung der aktiven Zeile und sanftem Scrollen.
- **Übersetzte Lyrics** — Die Lyrics werden maschinell (DeepL) in die Sprache der App übersetzt.
- **Lofi-Modus** — Macht jeden Titel zum Lofi-Vibe: um 0,9× verlangsamt, Tonhöhenkorrektur, nativer Hall.
- **Equalizer & native Effekte** — Systemweiter EQ mit Wiedergabe im Hintergrund und Audio bei ausgeschaltetem Bildschirm.
- **Mehrsprachiges Audio & Qualitätskontrolle** — Erkennt verfügbare Audiosprachen und streamt in High/Medium/Low-Qualität.

### 🤖 AI DJ & Personalisierung
- **AI DJ-Assistent (Gemini)** — Ein konversationeller DJ, der Ihren Geschmack versteht, intelligente Wiedergabelisten erstellt und Wünsche entgegennimmt.
- **Geschmackssignale** — Die Bewertung des Geschmacks pro Titel lernt, was Sie lieben, und steuert Empfehlungen.
- **Wrapped & Hörstatistiken** — Ihr Jahresrückblick: Top-Künstler, Stimmungen und Hör-Kapseln.
- **Intelligentes Cache-System** — Asynchrones Caching von Audio + Artwork in mehreren Auflösungen im Hintergrund für sofortige Wiedergabe ohne Wartezeit.

### 🌍 Entdeckung aus 15+ Quellen
Tunefy löst die Wiedergabe über eine **automatische Fallback-Kaskade** über diese Anbieter auf (keyless = kein API-Schlüssel erforderlich):

| Quelle | Type | Hinweise |
|---|---|---|
| **YouTube / YT Music** | Video / Audio | Primär, über youtube_explode + interne API |
| **Jamendo** | Keyless | Creative-Commons-Katalog |
| **Deezer** | Keyless | Katalog + Metadaten |
| **Audius** | Keyless | Dezentrale Künstler |
| **JioSaavn** | Open API | Schnelle Metadaten & Suche |
| **Invidious** | Keyless | YouTube-Spiegel (4 Instanzen) |
| **Piped** | Open API | YouTube-Spiegel |
| **OpenVerse** | Keyless | CC-Bilder/Audio *(neu)* |
| **Wikimedia Commons** | Keyless | Offene Medien *(neu)* |
| **Beatport** | Keyless | Elektronisch/Dance *(neu)* |
| **Dailymotion** | Keyless | Video-Fallback *(neu)* |
| **ccMixter** | Keyless | Remix-Kultur *(neu)* |
| **Internet Archive** | Keyless | Historisches Audio *(neu)* |
| **Radio Browser** | Keyless | Internetradiosender |
| **iTunes / MusicBrainz / Last.fm** | Open | Metadaten, Charts, Genres |

- **Cloud Stream Relay** — Ein selbst gehosteter Relay löst die URL auf und **leitet die Audiobytes** über dieselbe IP weiter, die der Player verwendet, und vermeidet so den HTTP 403, den IP-gebundene Googlevideo-Links sonst zurückgeben. Siehe [Server](#-backend--streaming-servers).
- **Spotify-Import** — Fügen Sie eine beliebige öffentliche Spotify-Playlist-URL ein (oder scannen Sie einen Spotify-Code), um Titel zu importieren.
- **Globale Suche** — Eine Suche über Songs, Videos, Alben, Künstler und Podcasts.
- **Teilen zum Abspielen** — Teilen Sie YouTube/YT-Music-Links direkt in Tunefy.

### 📻 Radio, Konzerte & Video
- **Internetradio** — Tausende Live-Sender (Radio Browser).
- **Konzerte** — Entdecken Sie Live-Events in Ihrer Nähe mit detailreichen Seiten.
- **Clips-Feed** — Vertikaler Kurzvideo-Feed mit Community- und Trend-Clips.
- **Videoplayer** — Vollständige Videowiedergabe mit Canvas-Videohintergründen.
- **DJ-Mixes** — Eigene DJ-/Mix-Entdeckung und -Wiedergabe.

### 🤝 Social, Blends & Community
- **Blend-Wiedergabelisten** — Erstellen Sie eine gemeinsame Wiedergabeliste mit einem kurzen Beitrittscode (z. B. `KORA-4821`); jeder mit dem Code kann zuhören und beitragen, wie bei Spotify-Blend-Links.
- **Community-Feed** — Suchen, streamen und entdecken Sie Titel, die von der Community hochgeladen wurden.
- **Künstler-Folgen** — Folgen Sie Künstlern/Kanälen, um sie im Auge zu behalten.
- **Intelligente Warteschlange & unbegrenzte Wiedergabe** — Automatische Einreihung mit intelligenter Leer-Logik.

### 🔐 Datenschutz & Konten
- **Kein Konto erforderlich** — Favoriten, Wiedergabelisten und Verlauf werden standardmäßig lokal gespeichert.
- **Anonym + Google-Anmeldung** — Optionale Anmeldung (anonyme Geräte-Identität oder Google über Supabase Auth) für Cloud-Sync und Profil.
- **Offline-Downloads** — Laden Sie Songs und Videos für das Hören offline herunter.
- **Deep Linking** — Vollständiges eigenes URL-Schema, um Songs, Künstler, Alben und Wiedergabelisten über Browser oder geteilte Links zu öffnen bzw. abzuspielen.
- **Ohne Werbung & zuverlässig** — Unterbrechungsfreies Hören, abgesichert durch offene Relays (Last.fm, MusicBrainz, iTunes), um die Wiedergabe zu garantieren.

---

## 🌐 Lokalisierung

Tunefy kommt mit **vollständigen Übersetzungen** in 14 Sprachen (plus automatischer Systemsprache):

| Sprache | Code | Sprache | Code |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Legen Sie die Sprache unter **Einstellungen → Sprache** fest (oder behalten Sie **System** für die automatische Erkennung).

---

## 📸 Screenshots

### 🏠 Startseite & Navigation
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Startbildschirm" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Startseite mit Mini-Player" />
  <img src="images/library.jpg" width="30%" alt="Bibliothek" />
</p>

### 🔍 Suche
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Suchergebnisse" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Suchvorschläge" />
</p>

### 🎵 Player
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Immersiver Player" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Legacy-Player" />
  <img src="images/song_queue.jpg" width="30%" alt="Song-Warteschlange" />
</p>

### 🎤 Lyrics
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Lyrics mit Bedienelementen" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Lyrics ohne Bedienelemente" />
</p>

### 👥 Community & Profil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Community-Feed" />
  <img src="images/profile_screen.jpg" width="30%" alt="Profilbildschirm" />
</p>

### ⚙️ Einstellungen & Anpassung
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Einstellungen" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Theme-Auswahl" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Akzentfarbe" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Eigene Akzentfarbe" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Sprachauswahl" />
</p>

### ℹ️ Über
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Über-Bildschirm" />
</p>

---

## 🏗️ Architektur

```
tunefy-music/
├── lib/                     # Flutter app (Riverpod + Just Audio)
│   ├── l10n/                # 14-language localization
│   ├── providers/           # Riverpod state
│   ├── screens/             # UI screens
│   ├── services/            # Sources, streaming, AI DJ, sync
│   └── widgets/             # Reusable components
├── server/                  # ☁️ Cloud stream relay (Render)  ← see below
├── backend/                 # Local/stream API + yt-dlp helpers
├── supabase/migrations/     # Postgres schema + RLS policies
└── images/, assets/         # Screenshots & brand assets
```

**Zuverlässigkeit der Wiedergabe.** Die App hängt nie an einem einzigen Anbieter. Sie prüft Quellen in einer
Prioritätskaskade (lokaler Relay → Cloud-Relay → schlüsselfreie Spiegel → Metadaten/Titel-Suche), mit einem
Schutzschalter, das eine fehlschlagende Quelle überspringt. Der **Cloud-Relay** löst einen Stream auf und
**leitet die Bytes** über seine eigene Verbindung weiter, sodass Auflösung und Wiedergabe eine gemeinsame IP teilen –
genau das vermeidet den IP-gebundenen 403 bei Googlevideo-Links.

---

## 🛠️ Technologie-Stack

| Ebene | Technologie |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **State Management** | [Riverpod](https://riverpod.dev/) |
| **Audio-Engine** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube-Extraktion** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (Fork von [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Lyrics** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + eigene Karaoke-Engine + DeepL-Übersetzung |
| **Lokaler Speicher** | [Hive](https://docs.hivedb.dev/) |
| **Cloud-Sync / Auth** | Supabase (Postgres + RLS, anonyme & Google-Anmeldung) |
| **Netzwerkkommunikation** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Stream-Relay** | FastAPI + yt-dlp auf Render (`server/`) |
| **UI-Komponenten** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Einrichtung & Installation

### Voraussetzungen
- Flutter SDK (neueste Stable-Version)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Installation

1. **Repository klonen:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Abhängigkeiten installieren:**
   ```bash
   flutter pub get
   ```

3. **App ausführen:**
   ```bash
   flutter run
   ```

4. **Release-APK bauen** (nach ABI geteilt für kleinere Größe):
   ```bash
   flutter build apk --split-per-abi
   ```

> Die URL des Cloud-Relays ist in `lib/utils/api_constants.dart`
> eingebaut (`relayBaseUrl`), daher ist kein Build-Flag erforderlich. Auf einen eigenen Relay zeigen:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend & Streaming-Server

### ☁️ Cloud Stream Relay — `server/` (deployed on Render)
Löst eine YouTube-Audio-URL auf **und leitet die Bytes weiter**, sodass Telefon und Auflöser eine gemeinsame IP
teilen (kein 403). FastAPI + yt-dlp, Docker, kostenlose Stufe.

| Endpoint | Beschreibung |
| --- | --- |
| `GET /health` | Liveness-Prüfung (`ok`) |
| `GET /stream?videoId=X&key=K` | Wird über yt-dlp aufgelöst → gibt eine `…/relay`-URL zurück (nur 200, wenn die Auflösung gelingt) |
| `GET /relay?videoId=X&key=K` | Leitet die Audiobytes weiter (Range-orientiert → 206 für Seeking) |

Geschützt durch eine gemeinsame `RELAY_KEY`-Umgebungsvariable (gibt ohne sie **401** zurück). Deploy: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Siehe `server/README.md`.

### 🎵 App API — `backend/`
Das Daten-/Such-Backend (YouTube Music über youtubei.js + offene Quellen: Last.fm-Genres,
MusicBrainz-Veröffentlichungen & Jahrzehnte).

| Endpoint | Beschreibung |
| --- | --- |
| `/api/search` | Musik-/Videosuche |
| `/api/trending` | Trends |
| `/api/charts` | YT-Music-Charts |
| `/api/playlist/:id` | Playlist-Details |
| `/api/moods`, `/api/moods/:id` | Kategorien & Stimmungen (Last.fm-Fallback) |
| `/api/tags?tag=` | Top-Titel/Alben nach Genre (Last.fm) |
| `/api/newreleases` | Neue Veröffentlichungen (MusicBrainz) |
| `/api/decades?year=` | Alben nach Jahrzehnt (MusicBrainz) |
| `/api/categories` | Kategorieliste |

**Lokal:** `cd backend && npm install && npm start` (Port 8000).
**Deploy (Vercel):** Dieses Repo importieren, **Root Directory = `backend`**. Siehe `backend/README.md`.

### 🗄️ Datenbank — `supabase/`
Postgres-Schema mit **Row-Level Security**: Benutzerzeilen sind an `auth.uid()` gebunden, der Katalog ist für
anonyme Nutzer schreibgeschützt und nur für die Service-Rolle beschreibbar. Führen Sie die Migrationen im
Supabase SQL Editor (in der richtigen Reihenfolge) aus.

---

## 🤝 Mitwirken

Beiträge sind willkommen! Ob Fehlerbericht, Feature-Vorschlag oder Code – Ihre Hilfe wird geschätzt.

1. **Projekt forken**
2. **Feature-Branch erstellen** (`git checkout -b feature/AmazingFeature`)
3. **Änderungen committen** (`git commit -m 'Add some AmazingFeature'`)
4. **Zum Branch pushen** (`git push origin feature/AmazingFeature`)
5. **Pull Request eröffnen**

**Richtlinien:** Befolgen Sie den bestehenden Code-Stil, führen Sie `flutter analyze` aus (muss sauber sein) und testen Sie neue Funktionen vor dem Einreichen.

---

## 🙏 Danksagungen

Tunefy würde nicht existieren ohne die großartige Arbeit dieser Entwickler und Projekte.

### youtube_explode_dart
Danke an **[Hexer10](https://github.com/Hexer10)**, ursprünglichen Autor von
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) – dem Rückgrat des
YouTube-Streamings von Tunefy – und an **[anandnet](https://github.com/anandnet)** für den aktuell
gehaltenen Fork, der Tunefy mit den neuesten YouTube-Änderungen am Laufen hält.

### Animesh (n-ce) — fast-saavn & ytify
Ein Dank an **[Animesh (n-ce)](https://github.com/n-ce)**, Schöpfer von
**[fast-saavn](https://github.com/n-ce/saavn)** (der offenen JioSaavn-API, die die Metadaten von Tunefy speist)
und **[ytify](https://github.com/n-ce/ytify)** (einer großen Inspirationsquelle).

### Open-Source-Bibliotheken
| Paket | Autor / Maintainer |
|---|---|
| [just_audio](https://pub.dev/packages/just_audio) | [Ryan Heise](https://github.com/ryanheise) |
| [audio_service](https://pub.dev/packages/audio_service) | [Ryan Heise](https://github.com/ryanheise) |
| [riverpod](https://pub.dev/packages/flutter_riverpod) | [Remi Rousselet](https://github.com/rrousselGit) |
| [hive](https://pub.dev/packages/hive) | [Hive Authors](https://github.com/hivedb/hive) |
| [flutter_lyric](https://pub.dev/packages/flutter_lyric) | [lyric contributors](https://pub.dev/packages/flutter_lyric) |
| [palette_generator](https://pub.dev/packages/palette_generator) | [Flutter Team](https://github.com/flutter/packages) |
| [cached_network_image](https://pub.dev/packages/cached_network_image) | [Baseflow](https://github.com/Baseflow/flutter_cached_network_image) |
| [dio](https://pub.dev/packages/dio) | [cfug](https://github.com/cfug/dio) |
| [flutter_animate](https://pub.dev/packages/flutter_animate) | [gskinner](https://github.com/gskinner/flutter_animate) |
| [google_sign_in](https://pub.dev/packages/google_sign_in) | [Flutter Team](https://github.com/flutter/packages) |
| [app_links](https://pub.dev/packages/app_links) | [Julien Eluard](https://github.com/llfbandit) |

---

## 📄 Lizenz

Verbreitet unter der **MIT License**. Siehe [`LICENSE`](LICENSE) für weitere Informationen.
