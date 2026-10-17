<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>Ein leistungsstarker, datenschutzorientierter Musik-Client, der mit Flutter.</strong><br/> erstellt wurde
  Werbefrei · Offline · KI-DJ · Synchronisierte und übersetzte Liedtexte · Liquid Glass Benutzeroberfläche · 15 Quellen · Kein Konto erforderlich
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Version" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Platform" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Languages" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

<p align="center">
  <a href="#-hauptmerkmale">Funktionen</a> ·
  <a href="#-lokalisierung">Sprachen</a> ·
  <a href="#-screenshots">Screenshots</a> ·
  <a href="#-architektur">Architektur</a> ·
  <a href="#-einrichtung-und-installation">Einrichtung</a> ·
  <a href="#-backend--und-streaming-server">Server</a>
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

Tunefy ist ein funktionsreicher, datenschutzorientierter Musik-Client, der mit Flutter erstellt wurde. Es strömt aus
**15+ offene und schlüssellose Quellen** mit einer automatischen Fallback-Kaskade, also ein Track, der bei einer ausfällt
Anbieter spielt auf den nächsten. Es bietet ein werbefreies Premium-Erlebnis mit Hintergrundwiedergabe,
Offline-Downloads, synchronisierte **und übersetzte** Liedtexte, ein **KI-DJ**, Internetradio, Konzerte,
Gemeinsame Blend-Wiedergabelisten, eine moderne Liquid Glass-Benutzeroberfläche und intelligentes Hintergrund-Caching – mit oder ohne
ein Konto.

> [!NOTE]
> Tunefy wird direkt aus diesem Repository vertrieben (APK-Versionen). Es ist **nicht** verfügbar
> auf der Google Play Store.

---

## 🚀 Hauptmerkmale

### 🎨 Liquid Glass UI/UX
- **Dynamische glasmorphische Themen** – Premium-Styling in den Modi Dunkel und Hell über `liquid_glass_easy`. Der Lichtmodus verwendet einen halbtransparenten Weißton, der sich dem Albumcover anpasst.
- **Benutzerdefinierte Shader und Unschärfe** – Hochleistungs-Milchglasscheiben und Overlays, die sich an die Farben von Kunstwerken anpassen.
- **Kontrastbewusste Elemente** – Statusleistensymbole, Steuerelemente, Schieberegler und Menüs werden zur besseren Lesbarkeit automatisch invertiert.
- **Großbildschirm- und Desktop-Optimierung** – Responsive Player-Layouts (bis zu 1300 Pixel), zentrierte Dialoge und eine spezielle obere Suchleiste für Desktop/Tablet.

### 🎧 Fesselndes Audio, Texte und Karaoke
- **Wort-für-Wort-Karaoke** – Wörter füllen sich in Echtzeit mit Farbe, während der Künstler singt (60+ FPS).
- **Zeilenweiser synchronisierter Sweep** – Progressiver Sweep-Effekt mit aktiver Zeilenhervorhebung und sanftem Scrollen.
- **Übersetzte Liedtexte** – Liedtexte werden im Handumdrehen maschinell in die Sprache Ihrer App übersetzt (DeepL).
- **Lofi-Modus** – Verwandeln Sie jeden Track in eine Lofi-Atmosphäre: 0,9-fache Verlangsamung, Tonhöhenkorrektur, nativer Hall.
- **Equalizer und native Effekte** – EQ auf Systemebene mit Hintergrundwiedergabe und Screen-Off-Audio.
- **Mehrsprachige Audio- und Qualitätskontrolle** – Erkennen Sie verfügbare Audiosprachen und streamen Sie in hoher/mittlerer/niedriger Qualität.

### 🤖 KI-DJ & Personalisierung
- **AI DJ Assistant (Gemini)** – Ein gesprächiger DJ, der Ihren Geschmack erkennt, intelligente Playlists erstellt und Anfragen entgegennimmt.
- **Geschmackssignale** – Die Geschmacksbewertung pro Titel erfährt, was Sie lieben, und führt zu Empfehlungen.
- **Wrapped & Hörstatistiken** – Ihr Jahresrückblick: Top-Künstler, Stimmungen und Hörkapseln.
- **Smart Cache System** – Asynchrones Hintergrund-Caching von Audio und Grafiken mit mehreren Auflösungen für sofortige Wiedergabe ohne Wartezeit.

### 🌍 Entdeckung aus über 15 Quellen
Tunefy löst die Wiedergabe durch eine **automatische Fallback-Kaskade** über diese Anbieter auf (schlüssellos = kein API-Schlüssel erforderlich):

| Quelle | Geben Sie | ein Notizen |
|---|---|---|
| **YouTube / YT Music** | Video / Audio | Primär, über youtube_explode + interne API |
| **Jamendo** | Schlüssellos | Creative-Commons-Katalog |
| **Deezer** | Schlüssellos | Katalog + Metadaten |
| **Audius** | Schlüssellos | Dezentrale Künstler |
| **JioSaavn** | API öffnen | Schnelle Metadaten und Suche |
| **Invidious** | Schlüssellos | YouTube Spiegel (4 Instanzen) |
| **Piped** | API öffnen | YouTube Spiegel |
| **OpenVerse** | Schlüssellos | CC-Bilder/Audio *(neu)* |
| **Wikimedia Commons** | Schlüssellos | Offene Medien *(neu)* |
| **Beatport** | Schlüssellos | Elektronisch/Tanz *(neu)* |
| **Dailymotion** | Schlüssellos | Video-Fallback *(neu)* |
| **ccMixter** | Schlüssellos | Remix-Kultur *(neu)* |
| **Internet Archive** | Schlüssellos | Historisches Audio *(neu)* |
| **Radio Browser** | Schlüssellos | Internetradiosender |
| **iTunes / MusicBrainz / Last.fm** | Öffnen | Metadaten, Diagramme, Genres |

- **Cloud Stream Relay** – Ein selbst gehostetes Relay löst die Audiobytes von derselben IP-Adresse auf, die der Player verwendet, und leitet sie weiter. Dabei wird HTTP 403 vermieden, das sonst von IP-gesperrten Googlevideo-Links zurückgegeben wird. Siehe [Servers](#-backend--und-streaming-server).
- **Spotify-Import** – Fügen Sie eine beliebige öffentliche Spotify-Playlist-URL ein (oder scannen Sie einen Spotify-Code), um Titel zu importieren.
- **Globale Suche** – Eine Suche über Songs, Videos, Alben, Künstler und Podcasts hinweg.
- **Share to Play** – Teilen Sie YouTube/YT Music-Links direkt in Tunefy.

### 📻 Radio, Konzerte und Video
- **Internetradio** – Tausende Live-Sender (Radio Browser).
- **Konzerte** – Entdecken Sie Live-Events in Ihrer Nähe mit umfangreichen Detailseiten.
- **Clips-Feed** – Vertikaler Kurzvideo-Feed mit Community- und Trendclips.
- **Videoplayer** – Vollständige Videowiedergabe mit Canvas-Videohintergründen.
- **DJ-Mixes** – Spezielle DJ-/Mix-Erkennung und -Wiedergabe.

### 🤝 Sozial, Mischungen und Gemeinschaft
- **Blend Playlists** – Erstellen Sie eine geteilte Playlist mit einem kurzen Beitrittscode (z. B. `KORA-4821`); Jeder mit dem Code kann zuhören und beitragen, z. B. Spotify Blend-Links.
- **Community-Feed** – Suchen, streamen und entdecken Sie von der Community hochgeladene Titel.
- **Künstler folgen** – Folgen Sie Künstlern/Kanälen, um den Überblick zu behalten.
- **Intelligente Warteschlange und unbegrenzte Wiedergabe** – Automatische Warteschlange mit intelligentem Löschverhalten.

### 🔐 Datenschutz und Konten
- **Kein Konto erforderlich** – Favoriten, Wiedergabelisten und Verlauf werden standardmäßig lokal gespeichert.
- **Anonym + Google-Anmeldung** – Optionale Anmeldung (anonyme Geräteidentität oder Google über Supabase Auth) für Cloud-Synchronisierung und Profil.
- **Offline-Downloads** – Laden Sie Songs und Videos zum Offline-Hören herunter.
- **Deep Linking** – Vollständig benutzerdefiniertes URL-Schema zum Öffnen/Wiedergeben von Songs, Künstlern, Alben und Playlists über den Browser oder freigegebene Links.
- **Werbefrei und zuverlässig** – Ununterbrochenes Hören, unterstützt durch offene Relais (Last.fm, MusicBrainz, iTunes), um die Wiedergabe zu gewährleisten.

---

## 🌐 Lokalisierung

Tunefy wird mit **vollständigen Übersetzungen** in 14 Sprachen (plus automatischer Systemsprache) geliefert:

| Sprache | Code | Sprache | Code |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Stellen Sie die Sprache unter **Einstellungen → Sprache** ein (oder behalten Sie **System** für die automatische Erkennung bei).

---

## 📸 Screenshots

### 🏠 Startseite und Navigation
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Startbildschirm" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Zuhause mit Mini-Player" />
  <img src="images/library.jpg" width="30%" alt="Bibliothek" />
</p>

### 🔍Suchen
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Suchergebnisse" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Suchvorschläge" />
</p>

### 🎵 Spieler
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Immersiver Player" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Legacy-Spieler" />
  <img src="images/song_queue.jpg" width="30%" alt="Song-Warteschlange" />
</p>

### 🎤 Songtext
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Liedtext mit Steuerung" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Songtexte ohne Bedienelemente" />
</p>

### 👥 Community & Profil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Community-Feed" />
  <img src="images/profile_screen.jpg" width="30%" alt="Profilbildschirm" />
</p>

### ⚙️ Einstellungen und Anpassung
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Einstellungen" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Themenauswahl" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Akzentfarbe" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Benutzerdefinierte Akzentfarbe" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Sprachauswahl" />
</p>

### ℹ️ Ungefähr
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Über den Bildschirm" />
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

**Wiedergabezuverlässigkeit.** Die App ist nie von einem einzelnen Anbieter abhängig. Es untersucht Quellen in a
Prioritätskaskade (lokales Relay → Cloud-Relay → schlüssellose Spiegel → Metadaten-/Titelsuche), mit a
Leistungsschalter, der eine ausgefallene Quelle überspringt. Das **Cloud-Relay** löst einen Stream auf und dann
**leitet die Bytes** über eine eigene Verbindung weiter, sodass Auflösung und Wiedergabe eine IP teilen – das ist
Was vermeidet die IP-Sperre 403 bei Googlevideo-Links.

---

## 🛠️ Tech-Stack

| Schicht | Technologie |
|---|---|
| **Rahmen** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Staatsverwaltung** | [Riverpod](https://riverpod.dev/) |
| **Audio-Engine** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Extraktion** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (Gabelung durch [anandnet](https://github.com/anandnet)) |
| **KI-DJ** | Google Gemini (`gemini_service`) |
| **Texte** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + benutzerdefinierte Karaoke-Engine + DeepL Übersetzung |
| **Lokaler Speicher** | [Hive](https://docs.hivedb.dev/) |
| **Cloud-Synchronisierung/Authentifizierung** | Supabase (Postgres + RLS, anonym und Google-Anmeldung) |
| **Netzwerk** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Stream Relay** | FastAPI + yt-dlp auf Render (`server/`) |
| **UI-Komponenten** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Einrichtung und Installation

### Voraussetzungen
- Flutter SDK (Neueste stabile Version)
- Dart SDK
- Android Studio / VS-Code
- Java JDK 17

### Installation

1. **Klonen Sie das Repository:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Abhängigkeiten installieren:**
   ```bash
   flutter pub get
   ```

3. **Führen Sie die App aus:**
   ```bash
   flutter run
   ```

4. **Build-Release-APK** (aufgeteilt nach ABI für kleinere Größe):
   ```bash
   flutter build apk --split-per-abi
   ```

> Die Cloud-Relay-URL ist in `lib/utils/api_constants.dart` integriert.
> (`relayBaseUrl`), daher ist kein Build-Flag erforderlich. Um auf Ihr eigenes Relais zu zeigen:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend- und Streaming-Server

### ☁️ Cloud Stream Relay – `server/` (bereitgestellt am Render)
Löst eine YouTube-Audio-URL auf **und leitet die Bytes weiter**, sodass das Telefon und der Resolver eine IP teilen
(Nr. 403). FastAPI + yt-dlp, Docker, kostenlose Stufe.

| Endpunkt | Beschreibung |
| --- | --- |
| `GET /health` | Lebendigkeitssonde (`ok`) |
| `GET /stream?videoId=X&key=K` | Wird über yt-dlp aufgelöst → gibt eine `…/relay`-URL zurück (200 nur, wenn sie aufgelöst wird) |
| `GET /relay?videoId=X&key=K` | Stellt die Audiobytes als Proxy bereit (bereichsbewusst → 206 für die Suche) |

Geschützt durch eine gemeinsam genutzte Umgebungsvariable `RELAY_KEY` (gibt **401** ohne zurück). Bereitstellen: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Siehe `server/README.md`.

### 🎵 App-API – `backend/`
Das Daten-/Such-Backend (YouTube Music über youtubei.js + offene Quellen: Last.fm Genres,
MusicBrainz Veröffentlichungen und Jahrzehnte).

| Endpunkt | Beschreibung |
| --- | --- |
| `/api/search` | Musik-/Videosuche |
| `/api/trending` | Im Trend |
| `/api/charts` | YT Music-Charts |
| `/api/playlist/:id` | Details zur Wiedergabeliste |
| `/api/moods`, `/api/moods/:id` | Kategorien & Stimmungen (Last.fm Fallback) |
| `/api/tags?tag=` | Genre-Top-Titel/-Alben (Last.fm) |
| `/api/newreleases` | Neuerscheinungen (MusicBrainz) |
| `/api/decades?year=` | Alben nach Jahrzehnt (MusicBrainz) |
| `/api/categories` | Kategorieliste |

**Lokal:** `cd backend && npm install && npm start` (Port 8000).
**Bereitstellen (Vercel):** Importieren Sie dieses Repo, **Root Directory = `backend`**. Siehe `backend/README.md`.

### 🗄️ Datenbank — `supabase/`
Postgres-Schema mit **Sicherheit auf Zeilenebene**: Benutzerzeilen sind auf `auth.uid()` beschränkt, der Katalog gilt
schreibgeschützt für anonyme Benutzer und nur für die Dienstrolle schreibbar. Führen Sie Migrationen im Supabase aus
SQL-Editor (in der Reihenfolge).

---

## 🤝 Mitmachen

Beiträge sind willkommen! Egal, ob Sie einen Fehler melden, eine Funktion vorschlagen oder Code schreiben, wir freuen uns über Ihre Hilfe.

1. **Fork das Projekt**
2. **Erstellen Sie Ihren Feature Branch** (`git checkout -b feature/AmazingFeature`)
3. **Übernehmen Sie Ihre Änderungen** (`git commit -m 'Add some AmazingFeature'`)
4. **Push to the Branch** (`git push origin feature/AmazingFeature`)
5. **Öffnen Sie eine Pull-Anfrage**

**Richtlinien:** Befolgen Sie den vorhandenen Codestil, führen Sie `flutter analyze` aus (muss sauber sein) und testen Sie neue Funktionen vor dem Absenden.

---

## 🙏 Danksagungen

Tunefy würde ohne die unglaubliche Arbeit dieser Entwickler und Projekte nicht existieren.

### youtube_explode_dart
Vielen Dank an**[Hexer10](https://github.com/Hexer10)**, ursprünglicher Autor von
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) – das Rückgrat von Tunefy
YouTube Streaming – und**[anandnet](https://github.com/anandnet)** für den aktuellen Fork
Tunefy arbeitet weiterhin mit den neuesten YouTube-Änderungen.

### Animesh (n-ce) – fast-saavn & ytify
Grüße an**[Animesh (n-ce)](https://github.com/n-ce)**, den Schöpfer von
**[fast-saavn](https://github.com/n-ce/saavn)** (die offene JioSaavn-API, die die Metadaten von Tunefy unterstützt)
und**[ytify](https://github.com/n-ce/ytify)** (eine riesige Inspirationsquelle).

### Open-Source-Bibliotheken
| Paket | Autor / Betreuer |
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

Verteilt unter der **MIT-Lizenz**. Weitere Informationen finden Sie unter [`LICENSE`](LICENSE).
