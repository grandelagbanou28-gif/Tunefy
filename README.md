<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>A powerful, privacy-focused music client built with Flutter.</strong><br/>
  Ad-free · Offline · AI DJ · Synced & translated Lyrics · Liquid Glass UI · 15 sources · No account required
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
  <a href="#-key-features">Features</a> ·
  <a href="#-localisation">Languages</a> ·
  <a href="#-screenshots">Screenshots</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-setup--installation">Setup</a> ·
  <a href="#-backend--streaming-servers">Servers</a>
</p>

<p align="center">
  <a href="README.md"><b>English</b></a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.fo.md">Fongbé</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a> ·
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

Tunefy is a feature-rich, privacy-focused music client built with Flutter. It streams from
**15+ open and keyless sources** with an automatic fallback cascade, so a track that fails on one
provider plays on the next. It offers a premium ad-free experience with background playback,
offline downloads, synchronized **and translated** lyrics, an **AI DJ**, internet radio, concerts,
shared Blend playlists, a modern Liquid Glass UI, and smart background caching — with or without
an account.

> [!NOTE]
> Tunefy is distributed directly from this repository (APK releases). It is **not** available
> on the Google Play Store.

---

## 🚀 Key Features

### 🎨 Liquid Glass UI/UX
- **Dynamic Glassmorphic Themes** — Premium styling in Dark and Light modes via `liquid_glass_easy`. Light Mode uses a semi-transparent white tint that adapts to the album art.
- **Custom Shaders & Blur** — High-performance frosted glass panels and overlays that adapt to artwork colors.
- **Contrast-Aware Elements** — Status bar icons, controls, sliders, and menus auto-invert for legibility.
- **Big Screen & Desktop Optimization** — Responsive player layouts (up to 1300px), centered dialogs, and a dedicated top search bar for desktop/tablet.

### 🎧 Immersive Audio, Lyrics & Karaoke
- **Word-by-Word Karaoke** — Words fill with color in real time as the artist sings (60+ FPS).
- **Line-by-Line Synced Sweep** — Progressive sweep effect with active-line highlight and smooth scrolling.
- **Translated Lyrics** — Lyrics are machine-translated (DeepL) into your app language on the fly.
- **Lofi Mode** — Turn any track into a Lofi vibe: slowed 0.9×, pitch correction, native reverb.
- **Equalizer & Native Effects** — System-level EQ with background playback and screen-off audio.
- **Multi-Language Audio & Quality Control** — Detect available audio languages and stream High/Medium/Low quality.

### 🤖 AI DJ & Personalization
- **AI DJ Assistant (Gemini)** — A conversational DJ that reads your taste, builds smart playlists, and takes requests.
- **Taste Signals** — Per-track taste scoring learns what you love and drives recommendations.
- **Wrapped & Listening Stats** — Your year-in-review: top artists, moods, and listening capsules.
- **Smart Cache System** — Async background caching of audio + multi-resolution artwork for instant, zero-wait playback.

### 🌍 Discovery Across 15+ Sources
Tunefy resolves playback through an **automatic fallback cascade** across these providers (keyless = no API key needed):

| Source | Type | Notes |
|---|---|---|
| **YouTube / YT Music** | Video / Audio | Primary, via youtube_explode + internal API |
| **Jamendo** | Keyless | Creative-Commons catalog |
| **Deezer** | Keyless | Catalog + metadata |
| **Audius** | Keyless | Decentralized artists |
| **JioSaavn** | Open API | Fast metadata & search |
| **Invidious** | Keyless | YouTube mirror (4 instances) |
| **Piped** | Open API | YouTube mirror |
| **OpenVerse** | Keyless | CC images/audio *(new)* |
| **Wikimedia Commons** | Keyless | Open media *(new)* |
| **Beatport** | Keyless | Electronic/dance *(new)* |
| **Dailymotion** | Keyless | Video fallback *(new)* |
| **ccMixter** | Keyless | Remix culture *(new)* |
| **Internet Archive** | Keyless | Historical audio *(new)* |
| **Radio Browser** | Keyless | Internet radio stations |
| **iTunes / MusicBrainz / Last.fm** | Open | Metadata, charts, genres |

- **Cloud Stream Relay** — A self-hosted relay resolves and **proxies the audio bytes** from the same IP the player uses, avoiding the HTTP 403 that IP-locked Googlevideo links otherwise return. See [Servers](#-backend--streaming-servers).
- **Spotify Import** — Paste any public Spotify playlist URL (or scan a Spotify code) to import tracks.
- **Global Search** — One search across songs, videos, albums, artists, and podcasts.
- **Share to Play** — Share YouTube/YT Music links straight into Tunefy.

### 📻 Radio, Concerts & Video
- **Internet Radio** — Thousands of live stations (Radio Browser).
- **Concerts** — Discover live events near you with rich detail pages.
- **Clips Feed** — Vertical short-video feed of community and trending clips.
- **Video Player** — Full video playback with canvas video backgrounds.
- **DJ Mixes** — Dedicated DJ/mix discovery and playback.

### 🤝 Social, Blends & Community
- **Blend Playlists** — Create a shared playlist with a short join code (e.g. `KORA-4821`); anyone with the code can listen and contribute, like Spotify Blend links.
- **Community Feed** — Search, stream, and discover tracks uploaded by the community.
- **Artist Following** — Follow artists/channels to keep track of them.
- **Smart Queue & Infinite Playback** — Auto-queue with intelligent clear behavior.

### 🔐 Privacy & Accounts
- **No Account Required** — Favorites, playlists, and history are stored locally by default.
- **Anonymous + Google Sign-In** — Optional sign-in (anonymous device identity or Google via Supabase Auth) for cloud sync and profile.
- **Offline Downloads** — Download songs and videos for offline listening.
- **Deep Linking** — Full custom URL scheme to open/play songs, artists, albums, and playlists via browser or shared links.
- **Ad-Free & Reliable** — Uninterrupted listening backed by open relays (Last.fm, MusicBrainz, iTunes) to guarantee playback.

---

## 🌐 Localisation

Tunefy ships with **full translations** in 14 languages (plus automatic system language):

| Language | Code | Language | Code |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Set the language in **Settings → Language** (or keep **System** for automatic detection).

---

## 📸 Screenshots

### 🏠 Home & Navigation
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Home Screen" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Home with Mini Player" />
  <img src="images/library.jpg" width="30%" alt="Library" />
</p>

### 🔍 Search
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Search Results" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Search Suggestions" />
</p>

### 🎵 Player
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Immersive Player" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Legacy Player" />
  <img src="images/song_queue.jpg" width="30%" alt="Song Queue" />
</p>

### 🎤 Lyrics
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Lyrics with Controls" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Lyrics without Controls" />
</p>

### 👥 Community & Profile
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Community Feed" />
  <img src="images/profile_screen.jpg" width="30%" alt="Profile Screen" />
</p>

### ⚙️ Settings & Customization
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Settings" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Theme Selector" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Accent Color" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Custom Accent Color" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Language Selector" />
</p>

### ℹ️ About
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="About Screen" />
</p>

---

## 🏗️ Architecture

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

**Playback reliability.** The app never depends on a single provider. It probes sources in a
priority cascade (local relay → cloud relay → keyless mirrors → metadata/title search), with a
circuit breaker that skips a source that is failing. The **cloud relay** resolves a stream and then
**relays the bytes** through its own connection so resolution and playback share one IP — this is
what avoids the IP-locked 403 on Googlevideo links.

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **State Management** | [Riverpod](https://riverpod.dev/) |
| **Audio Engine** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Extraction** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork by [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Lyrics** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + custom karaoke engine + DeepL translation |
| **Local Storage** | [Hive](https://docs.hivedb.dev/) |
| **Cloud Sync / Auth** | Supabase (Postgres + RLS, anonymous & Google sign-in) |
| **Networking** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Stream Relay** | FastAPI + yt-dlp on Render (`server/`) |
| **UI Components** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Setup & Installation

### Prerequisites
- Flutter SDK (Latest Stable)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

4. **Build release APK** (split by ABI for smaller size):
   ```bash
   flutter build apk --split-per-abi
   ```

> The cloud relay URL is baked into `lib/utils/api_constants.dart`
> (`relayBaseUrl`), so no build flag is required. To point at your own relay:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend & Streaming Servers

### ☁️ Cloud Stream Relay — `server/` (deployed on Render)
Resolves a YouTube audio URL **and relays the bytes** so the phone and the resolver share one IP
(no 403). FastAPI + yt-dlp, Docker, free tier.

| Endpoint | Description |
| --- | --- |
| `GET /health` | Liveness probe (`ok`) |
| `GET /stream?videoId=X&key=K` | Resolves via yt-dlp → returns a `…/relay` URL (200 only if it resolves) |
| `GET /relay?videoId=X&key=K` | Proxies the audio bytes (Range-aware → 206 for seeking) |

Protected by a shared `RELAY_KEY` env var (returns **401** without it). Deploy: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. See `server/README.md`.

### 🎵 App API — `backend/`
The data/search backend (YouTube Music via youtubei.js + open sources: Last.fm genres,
MusicBrainz releases & decades).

| Endpoint | Description |
| --- | --- |
| `/api/search` | Music / video search |
| `/api/trending` | Trending |
| `/api/charts` | YT Music charts |
| `/api/playlist/:id` | Playlist detail |
| `/api/moods`, `/api/moods/:id` | Categories & moods (Last.fm fallback) |
| `/api/tags?tag=` | Genre top tracks/albums (Last.fm) |
| `/api/newreleases` | New releases (MusicBrainz) |
| `/api/decades?year=` | Albums by decade (MusicBrainz) |
| `/api/categories` | Category list |

**Local:** `cd backend && npm install && npm start` (port 8000).
**Deploy (Vercel):** import this repo, **Root Directory = `backend`**. See `backend/README.md`.

### 🗄️ Database — `supabase/`
Postgres schema with **Row-Level Security**: user rows are scoped to `auth.uid()`, the catalog is
read-only for anonymous users and writable only by the service role. Run migrations in the Supabase
SQL Editor (in order).

---

## 🤝 Contributing

Contributions are welcome! Whether it's reporting a bug, suggesting a feature, or writing code, your help is appreciated.

1. **Fork the Project**
2. **Create your Feature Branch** (`git checkout -b feature/AmazingFeature`)
3. **Commit your Changes** (`git commit -m 'Add some AmazingFeature'`)
4. **Push to the Branch** (`git push origin feature/AmazingFeature`)
5. **Open a Pull Request**

**Guidelines:** follow the existing code style, run `flutter analyze` (must be clean), and test new features before submitting.

---

## 🙏 Acknowledgements

Tunefy wouldn't exist without the incredible work of these developers and projects.

### youtube_explode_dart
Thanks to **[Hexer10](https://github.com/Hexer10)**, original author of
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — the backbone of Tunefy's
YouTube streaming — and **[anandnet](https://github.com/anandnet)** for the up-to-date fork that
keeps Tunefy working with the latest YouTube changes.

### Animesh (n-ce) — fast-saavn & ytify
Shoutout to **[Animesh (n-ce)](https://github.com/n-ce)**, creator of
**[fast-saavn](https://github.com/n-ce/saavn)** (the open JioSaavn API powering Tunefy's metadata)
and **[ytify](https://github.com/n-ce/ytify)** (a huge source of inspiration).

### Open-Source Libraries
| Package | Author / Maintainers |
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

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.
