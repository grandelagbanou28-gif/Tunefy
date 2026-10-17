<p align="center">
  <img src="assets/logo.png" alt="Logo di Tunefy" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Un potente client musicale incentrato sulla privacy, realizzato con Flutter.</strong><br/>
  Niente pubblicità · Offline · DJ con IA · Testi sincronizzati e tradotti · Liquid Glass UI · 15 fonti · Nessun account richiesto
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Versione" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Piattaforma" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Lingue" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Licenza" />
</p>

<p align="center">
  <a href="#-key-features">Funzionalità</a> ·
  <a href="#-localisation">Lingue</a> ·
  <a href="#-screenshots">Schermate</a> ·
  <a href="#-architecture">Architettura</a> ·
  <a href="#-setup--installation">Configurazione</a> ·
  <a href="#-backend--streaming-servers">Server</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.fo.md">Fongbé</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt.md">Português</a> ·
  <b>Italiano</b> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.hi.md">हिन्दी</a> ·
  <a href="README.id.md">Bahasa Indonesia</a> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy è un client musicale ricco di funzionalità e incentrato sulla privacy, realizzato con Flutter. Trasmette da
**oltre 15 fonti aperte e senza chiave API** con una cascata di fallback automatica, così un brano che fallisce su un
fornitore viene riprodotto dal successivo. Offre un'esperienza premium senza pubblicità con riproduzione in
background, download offline, testi sincronizzati **e tradotti**, un **DJ con IA**, radio internet, concerti,
playlist Blend condivise, una moderna interfaccia Liquid Glass e una cache intelligente in background —
con o senza account.

> [!NOTE]
> Tunefy è distribuito direttamente da questo repository (rilasci APK). **Non** è disponibile
> su Google Play Store.

---

## 🚀 Funzionalità Principali

### 🎨 Interfaccia/UX Liquid Glass
- **Temi Glassmorfici Dinamici** — Stile premium in modalità Scura e Chiaro tramite `liquid_glass_easy`. La modalità Chiara usa una tinta bianca semitrasparente che si adatta alla copertina dell'album.
- **Shader e Sfocatura Personalizzati** — Pannelli di vetro smerigliato e sovrapposizioni ad alte prestazioni che si adattano ai colori della copertina.
- **Elementi Sensibili al Contrasto** — Le icone della barra di stato, i controlli, gli slider e i menu si invertono automaticamente per una migliore leggibilità.
- **Ottimizzazione per Schermi Grandi e Desktop** — Layout del player reattivi (fino a 1300px), dialoghi centrati e una barra di ricerca in alto dedicata a desktop/tablet.

### 🎧 Audio Immersivo, Testi e Karaoke
- **Karaoke Parola per Parola** — Le parole si riempiono di colore in tempo reale mentre l'artista canta (oltre 60 FPS).
- **Scansione Sincronizzata Riga per Riga** — Effetto di scansione progressiva con evidenziazione della riga attiva e scorrimento fluido.
- **Testi Tradotti** — I testi vengono tradotti automaticamente (DeepL) nella lingua dell'app al volo.
- **Modalità Lofi** — Trasforma qualunque brano in una vibrazione Lofi: rallentato 0.9×, correzione del tono, riverbero nativo.
- **Equalizzatore ed Effetti Nativi** — EQ a livello di sistema con riproduzione in background e audio con schermo spento.
- **Audio Multilingua e Controllo della Qualità** — Rileva le lingue audio disponibili e trasmette ad alta/media/bassa qualità.

### 🤖 DJ con IA e Personalizzazione
- **Assistente DJ con IA (Gemini)** — Un DJ conversazionale che legge i tuoi gusti, crea playlist intelligenti e accetta richieste.
- **Segnali di Gusto** — Il punteggio di gusto per brano impara cosa ami e alimenta i consigli.
- **Wrapped e Statistiche di Ascolto** — Il tuo riepilogo annuale: artisti principali, umori e capsule d'ascolto.
- **Sistema di Cache Intelligente** — Cache asincrona in background di audio + copertine a più risoluzioni per una riproduzione istantanea, senza attese.

### 🌍 Scoperta Attraverso Oltre 15 Fonti
Tunefy risolve la riproduzione attraverso una **cascata di fallback automatica** tra questi fornitori (senza chiave = nessuna chiave API necessaria):

| Fonte | Tipo | Note |
|---|---|---|
| **YouTube / YT Music** | Video / Audio | Principale, tramite youtube_explode + API interna |
| **Jamendo** | Senza chiave | Catalogo Creative Commons |
| **Deezer** | Senza chiave | Catalogo + metadati |
| **Audius** | Senza chiave | Artisti decentralizzati |
| **JioSaavn** | API aperta | Metadati e ricerca veloci |
| **Invidious** | Senza chiave | Mirror di YouTube (4 istanze) |
| **Piped** | API aperta | Mirror di YouTube |
| **OpenVerse** | Senza chiave | Immagini/audio CC *(nuovo)* |
| **Wikimedia Commons** | Senza chiave | Media aperti *(nuovo)* |
| **Beatport** | Senza chiave | Elettronica/dance *(nuovo)* |
| **Dailymotion** | Senza chiave | Fallback video *(nuovo)* |
| **ccMixter** | Senza chiave | Cultura del remix *(nuovo)* |
| **Internet Archive** | Senza chiave | Audio storico *(nuovo)* |
| **Radio Browser** | Senza chiave | Stazioni radio internet |
| **iTunes / MusicBrainz / Last.fm** | Aperta | Metadati, chart, generi |

- **Cloud Stream Relay** — Un relay auto-hosted risolve e **fa proxy dei byte audio** dallo stesso IP usato dal player, evitando l'errore HTTP 403 che altrimenti restituirebbero i link Googlevideo bloccati su IP. Vedi [Servers](#-backend--streaming-servers).
- **Importazione da Spotify** — Incolla l'URL di qualsiasi playlist pubblica di Spotify (o scansiona un codice Spotify) per importare i brani.
- **Ricerca Globale** — Una ricerca unica su canzoni, video, album, artisti e podcast.
- **Condividi per Riprodurre** — Condividi i link di YouTube/YT Music direttamente in Tunefy.

### 📻 Radio, Concerti e Video
- **Radio Internet** — Migliaia di stazioni in diretta (Radio Browser).
- **Concerti** — Scopri eventi dal vivo vicino a te con pagine di dettaglio ricche.
- **Feed di Clip** — Feed verticale di video brevi con clip della community e di tendenza.
- **Player Video** — Riproduzione video completa con sfondi video su canvas.
- **Mix DJ** — Scoperta e riproduzione dedicate di mix DJ.

### 🤝 Social, Blend e Community
- **Playlist Blend** — Crea una playlist condivisa con un breve codice di ingresso (es. `KORA-4821`); chiunque abbia il codice può ascoltare e contribuire, come i link Blend di Spotify.
- **Feed della Community** — Cerca, trasmetti e scopri i brani caricati dalla community.
- **Segui gli Artisti** — Segui artisti/canali per tenertene traccia.
- **Coda Intelligente e Riproduzione Infinita** — Coda automatica con svuotamento intelligente.

### 🔐 Privacy e Account
- **Nessun Account Richiesto** — Preferiti, playlist e cronologia sono salvati localmente per impostazione predefinita.
- **Anonimo + Accesso con Google** — Accesso opzionale (identità anonima del dispositivo o Google tramite Supabase Auth) per sincronizzazione cloud e profilo.
- **Download Offline** — Scarica canzoni e video per l'ascolto offline.
- **Deep Linking** — Scheme URL personalizzato completo per aprire/riprodurre canzoni, artisti, album e playlist tramite browser o link condivisi.
- **Senza Pubblicità e Affidabile** — Ascolto ininterrotto supportato da relay aperti (Last.fm, MusicBrainz, iTunes) per garantire la riproduzione.

---

## 🌐 Localizzazione

Tunefy è fornito con **traduzioni complete** in 14 lingue (più la lingua di sistema automatica):

| Lingua | Codice | Lingua | Codice |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Imposta la lingua in **Impostazioni → Lingua** (o mantieni **Sistema** per il rilevamento automatico).

---

## 📸 Schermate

### 🏠 Home e Navigazione
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Schermata Home" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Home con mini player" />
  <img src="images/library.jpg" width="30%" alt="Libreria" />
</p>

### 🔍 Ricerca
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Risultati di ricerca" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Suggerimenti di ricerca" />
</p>

### 🎵 Player
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Player immersivo" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Player classico" />
  <img src="images/song_queue.jpg" width="30%" alt="Coda brani" />
</p>

### 🎤 Testi
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Testi con controlli" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Testi senza controlli" />
</p>

### 👥 Community e Profilo
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Feed della community" />
  <img src="images/profile_screen.jpg" width="30%" alt="Schermata profilo" />
</p>

### ⚙️ Impostazioni e Personalizzazione
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Impostazioni" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Selettore tema" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Colore accento" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Colore accento personalizzato" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Selettore lingua" />
</p>

### ℹ️ Informazioni
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Schermata Informazioni" />
</p>

---

## 🏗️ Architettura

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

**Affidabilità della riproduzione.** L'app non dipende mai da un singolo fornitore. Sonda le fonti in una cascata
di priorità (relay locale → relay cloud → mirror senza chiave → ricerca per metadati/titolo), con un circuit breaker
che salta una fonte che sta fallendo. Il **relay cloud** risolve un flusso e poi **instrada i byte** attraverso la
sua stessa connessione, così risoluzione e riproduzione condividono un solo IP — è questo che evita il 403 bloccato
su IP nei link Googlevideo.

---

## 🛠️ Stack Tecnologico

| Livello | Tecnologia |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestione dello Stato** | [Riverpod](https://riverpod.dev/) |
| **Motore Audio** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **Estrazione YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork di [anandnet](https://github.com/anandnet)) |
| **DJ con IA** | Google Gemini (`gemini_service`) |
| **Testi** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + motore karaoke personalizzato + traduzione DeepL |
| **Archiviazione Locale** | [Hive](https://docs.hivedb.dev/) |
| **Sincronizzazione Cloud / Auth** | Supabase (Postgres + RLS, accesso anonimo e con Google) |
| **Rete** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relay Stream** | FastAPI + yt-dlp su Render (`server/`) |
| **Componenti UI** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Configurazione e Installazione

### Prerequisiti
- Flutter SDK (ultima versione stabile)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Installazione

1. **Clona il repository:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Installa le dipendenze:**
   ```bash
   flutter pub get
   ```

3. **Esegui l'app:**
   ```bash
   flutter run
   ```

4. **Compila l'APK di release** (suddiviso per ABI per una dimensione ridotta):
   ```bash
   flutter build apk --split-per-abi
   ```

> L'URL del relay cloud è incorporato in `lib/utils/api_constants.dart`
> (`relayBaseUrl`), quindi non è richiesta alcuna flag di build. Per puntare al tuo relay:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend e Server di Streaming

### ☁️ Relay Cloud Stream — `server/` (deployed on Render)
Risolve un URL audio di YouTube **e instrada i byte** così telefono e risolutore condividono un IP
(niente 403). FastAPI + yt-dlp, Docker, piano gratuito.

| Endpoint | Descrizione |
| --- | --- |
| `GET /health` | Sonda di vitalità (`ok`) |
| `GET /stream?videoId=X&key=K` | Risolve tramite yt-dlp → restituisce un URL `…/relay` (200 solo se risolve) |
| `GET /relay?videoId=X&key=K` | Fa proxy dei byte audio (compatibile con Range → 206 per lo scorrimento) |

Protegto da una variabile d'ambiente condivisa `RELAY_KEY` (restituisce **401** senza di essa). Deploy: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Vedi `server/README.md`.

### 🎵 API dell'App — `backend/`
Il backend dati/ricerca (YouTube Music tramite youtubei.js + fonti aperte: generi Last.fm, release e decenni
MusicBrainz).

| Endpoint | Descrizione |
| --- | --- |
| `/api/search` | Ricerca musica/video |
| `/api/trending` | Di tendenza |
| `/api/charts` | Chart YT Music |
| `/api/playlist/:id` | Dettaglio playlist |
| `/api/moods`, `/api/moods/:id` | Categorie e umori (fallback Last.fm) |
| `/api/tags?tag=` | Brani/album top per genere (Last.fm) |
| `/api/newreleases` | Nuove uscite (MusicBrainz) |
| `/api/decades?year=` | Album per decennio (MusicBrainz) |
| `/api/categories` | Elenco categorie |

**Locale:** `cd backend && npm install && npm start` (porta 8000).
**Deploy (Vercel):** importa questa repo, **Root Directory = `backend`**. Vedi `backend/README.md`.

### 🗄️ Database — `supabase/`
Schema Postgres con **Row-Level Security**: le righe utente sono limitate a `auth.uid()`, il catalogo è in sola
lettura per gli utenti anonimi e scrivibile solo dal ruolo di servizio. Esegui le migrazioni nell'Editor SQL di
Supabase (in ordine).

---

## 🤝 Contribuzioni

I contributi sono ben accetti! Che si tratti di segnalare un bug, suggerire una funzionalità o scrivere codice, il
tuo aiuto è apprezzato.

1. **Fork del Progetto**
2. **Crea il tuo Branch della Feature** (`git checkout -b feature/AmazingFeature`)
3. **Commit delle Tue Modifiche** (`git commit -m 'Add some AmazingFeature'`)
4. **Push sul Branch** (`git push origin feature/AmazingFeature`)
5. **Apri una Pull Request**

**Linee guida:** segui lo stile di codice esistente, esegui `flutter analyze` (deve essere pulito) e testa le nuove
funzionalità prima dell'invio.

---

## 🙏 Ringraziamenti

Tunefy non esisterebbe senza l'incredibile lavoro di questi sviluppatori e progetti.

### youtube_explode_dart
Grazie a **[Hexer10](https://github.com/Hexer10)**, autore originale di
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — la spina dorsale dello streaming
YouTube di Tunefy — e a **[anandnet](https://github.com/anandnet)** per il fork aggiornato che
tiene Tunefy funzionante con le ultime modifiche di YouTube.

### Animesh (n-ce) — fast-saavn & ytify
Un plauso a **[Animesh (n-ce)](https://github.com/n-ce)**, creatore di
**[fast-saavn](https://github.com/n-ce/saavn)** (l'API aperta di JioSaavn che alimenta i metadati di Tunefy)
e di **[ytify](https://github.com/n-ce/ytify)** (un'enorme fonte di ispirazione).

### Librerie Open-Source
| Pacchetto | Autore / Manutentori |
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

## 📄 Licenza

Distribuito sotto la **Licenza MIT**. Vedi [`LICENSE`](LICENSE) per maggiori informazioni.
