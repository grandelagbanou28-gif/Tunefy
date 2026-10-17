<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>Un client musicale potente e incentrato sulla privacy, creato con Flutter.</strong><br/>
  Senza pubblicità · Offline · AI DJ · Testi sincronizzati e tradotti · Liquid Glass UI · 15 fonti · Nessun account richiesto
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
  <a href="#-caratteristiche-principali">Caratteristiche</a> ·
  <a href="#-localizzazione">Lingue</a> ·
  <a href="#-schermate">Screenshot</a> ·
  <a href="#architettura">Architettura</a> ·
  <a href="#-configurazione-e-installazione">Impostazione</a> ·
  <a href="#server-backend-e-streaming">Server</a>
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

Tunefy è un client musicale ricco di funzionalità e incentrato sulla privacy, creato con Flutter. Fluisce da
**Oltre 15 sorgenti aperte e senza chiave** con una cascata di fallback automatica, quindi una traccia che fallisce su una
il provider gioca il prossimo. Offre un'esperienza premium senza pubblicità con riproduzione in background,
download offline, testi sincronizzati **e tradotti**, un **DJ AI**, radio su Internet, concerti,
playlist condivise Blend, una moderna interfaccia utente Liquid Glass e memorizzazione nella cache in background intelligente, con o senza
un conto.

> [!NOTE]
> Tunefy è distribuito direttamente da questo repository (versioni APK). **Non** è disponibile
> sul Google Play Store.

---

## 🚀 Caratteristiche principali

### 🎨 Liquid Glass Interfaccia utente/UX
- **Temi Glassmorphic dinamici**: stile premium nelle modalità Buio e Luce tramite `liquid_glass_easy`. La modalità luce utilizza una tinta bianca semitrasparente che si adatta alla copertina dell'album.
- **Shader e sfocatura personalizzati**: pannelli e sovrapposizioni in vetro smerigliato ad alte prestazioni che si adattano ai colori delle opere d'arte.
- **Elementi sensibili al contrasto**: le icone, i controlli, i cursori e i menu della barra di stato si invertono automaticamente per garantire la leggibilità.
- **Ottimizzazione per grande schermo e desktop**: layout del player reattivi (fino a 1300 px), finestre di dialogo centrate e una barra di ricerca superiore dedicata per desktop/tablet.

### 🎧 Audio, testi e karaoke coinvolgenti
- **Karaoke parola per parola**: le parole si riempiono di colore in tempo reale mentre l'artista canta (oltre 60 FPS).
- **Scansione sincronizzata riga per riga**: effetto di scansione progressivo con evidenziazione della riga attiva e scorrimento fluido.
- **Testi tradotti**: i testi vengono tradotti automaticamente (DeepL) nella lingua dell'app al volo.
- **Modalità Lofi**: trasforma qualsiasi traccia in un'atmosfera Lofi: rallentato 0,9×, correzione dell'intonazione, riverbero nativo.
- **Equalizzatore ed effetti nativi**: EQ a livello di sistema con riproduzione in background e audio a schermo spento.
- **Audio multilingue e controllo qualità**: rileva le lingue audio disponibili e trasmette in streaming di qualità alta/media/bassa.

### 🤖 DJ AI e personalizzazione
- **AI DJ Assistant (Gemini)** — Un DJ conversazionale che interpreta i tuoi gusti, crea playlist intelligenti e accetta richieste.
- **Segnali di gusto**: il punteggio di gusto per traccia apprende ciò che ami e fornisce consigli.
- **Wrapped e statistiche di ascolto** — Il tuo bilancio dell'anno: i migliori artisti, stati d'animo e capsule di ascolto.
- **Sistema Smart Cache**: memorizzazione nella cache asincrona in background di audio e grafica multi-risoluzione per una riproduzione istantanea e senza attesa.

### 🌍 Scoperta da oltre 15 fonti
Tunefy risolve la riproduzione tramite una **cascata di fallback automatica** tra questi provider (keyless = nessuna chiave API necessaria):

| Fonte | Digitare | Note |
|---|---|---|
| **YouTube / YT Musica** | Video/Audio | Primario, tramite youtube_explode + API interna |
| **Jamendo** | Senza chiave | Catalogo Creative Commons |
| **Deezer** | Senza chiave | Catalogo + metadati |
| **Audius** | Senza chiave | Artisti decentralizzati |
| **JioSaavn** | Apri API | Metadati e ricerca veloci |
| **Invidious** | Senza chiave | YouTube specchio (4 istanze) |
| **Piped** | Apri API | YouTube specchio |
| **OpenVerse** | Senza chiave | Immagini/audio CC *(nuovo)* |
| **Wikimedia Commons** | Senza chiave | Apri media *(nuovo)* |
| **Beatport** | Senza chiave | Elettronica/danza *(nuovo)* |
| **Dailymotion** | Senza chiave | Video di riserva *(nuovo)* |
| **ccMixter** | Senza chiave | Cultura del remix *(nuovo)* |
| **Internet Archive** | Senza chiave | Audio storico *(nuovo)* |
| **Radio Browser** | Senza chiave | Stazioni radio Internet |
| **iTunes / MusicBrainz / Last.fm** | Apri | Metadati, grafici, generi |

- **Cloud Stream Relay**: un relè self-hosted risolve e **invia tramite proxy i byte audio** dallo stesso IP utilizzato dal lettore, evitando l'HTTP 403 che altrimenti restituirebbero i collegamenti Googlevideo con IP bloccato. Vedi [Servers](#server-backend-e-streaming).
- **Spotify Importa**: incolla qualsiasi URL di playlist Spotify pubblica (o scansiona un codice Spotify) per importare le tracce.
- **Ricerca globale**: una ricerca tra brani, video, album, artisti e podcast.
- **Condividi per riprodurre**: condividi YouTube/YT Music si collega direttamente a Tunefy.

### 📻 Radio, Concerti e Video
- **Radio Internet**: migliaia di stazioni in diretta (Radio Browser).
- **Concerti**: scopri gli eventi dal vivo vicino a te con pagine ricche di dettagli.
- **Feed clip**: feed verticale di brevi video di clip della community e di tendenza.
- **Lettore video**: riproduzione video completa con sfondi video su tela.
- **Mix DJ**: scoperta e riproduzione di DJ/mix dedicati.

### 🤝 Social, Blends e Community
- **Blend Playlist**: crea una playlist condivisa con un breve codice di accesso (ad esempio `KORA-4821`); chiunque abbia il codice può ascoltare e contribuire, mettendo mi piace ai link Spotify Blend.
- **Feed della community**: cerca, riproduci in streaming e scopri i brani caricati dalla community.
- **Segue artista**: segui artisti/canali per tenerne traccia.
- **Coda intelligente e riproduzione infinita**: coda automatica con comportamento intelligente e chiaro.

### 🔐 Privacy e account
- **Nessun account richiesto**: preferiti, playlist e cronologia vengono archiviati localmente per impostazione predefinita.
- **Accesso anonimo + Google**: accesso opzionale (identità anonima del dispositivo o Google tramite Supabase Auth) per la sincronizzazione cloud e il profilo.
- **Download offline**: scarica brani e video per l'ascolto offline.
- **Collegamenti profondi**: schema URL completamente personalizzato per aprire/riprodurre brani, artisti, album e playlist tramite browser o collegamenti condivisi.
- **Senza pubblicità e affidabile**: ascolto ininterrotto supportato da relè aperti (Last.fm, MusicBrainz, iTunes) per garantire la riproduzione.

---

## 🌐 Localizzazione

Tunefy viene fornito con **traduzioni complete** in 14 lingue (più la lingua del sistema automatico):

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
  <img src="images/home.jpg" width="30%" alt="Schermata iniziale" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="A casa con il minilettore" />
  <img src="images/library.jpg" width="30%" alt="Biblioteca" />
</p>

### 🔍 Cerca
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Risultati della ricerca" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Suggerimenti per la ricerca" />
</p>

### 🎵 Giocatore
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Giocatore coinvolgente" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Giocatore storico" />
  <img src="images/song_queue.jpg" width="30%" alt="Coda di brani" />
</p>

### 🎤 Testi
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Testi con controlli" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Testi senza controlli" />
</p>

### 👥 Comunità e profilo
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Feed della comunità" />
  <img src="images/profile_screen.jpg" width="30%" alt="Schermata del profilo" />
</p>

### ⚙️ Impostazioni e personalizzazione
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Impostazioni" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Selettore di temi" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Colore accento" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Colore accento personalizzato" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Selettore della lingua" />
</p>

### ℹ️ A proposito
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Informazioni sullo schermo" />
</p>

---

## 🏗️Architettura

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

**Affidabilità della riproduzione.** L'app non dipende mai da un singolo provider. Esamina le fonti in a
cascata prioritaria (relè locale → relè cloud → specchietti senza chiave → ricerca metadati/titolo), con a
interruttore automatico che salta una fonte che non funziona. Il **cloud Relay** risolve un flusso e poi
**trasmette i byte** attraverso la propria connessione in modo che la risoluzione e la riproduzione condividano un IP: questo è
cosa evita il 403 con blocco IP sui collegamenti Googlevideo.

---

## 🛠️Stack tecnologico

| Strato | Tecnologia |
|---|---|
| **Quadro** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestione dello Stato** | [Riverpod](https://riverpod.dev/) |
| **Motore audio** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Estrazione** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (biforcazione di [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Testo** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + motore karaoke personalizzato + traduzione DeepL |
| **Archiviazione locale** | [Hive](https://docs.hivedb.dev/) |
| **Sincronizzazione/Autenticazione cloud** | Supabase (Postgres + RLS, accesso anonimo e Google) |
| **Rete** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relè di flusso** | FastAPI + yt-dlp su Render (`server/`) |
| **Componenti dell'interfaccia utente** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Configurazione e installazione

### Prerequisiti
- Flutter SDK (ultima versione stabile)
- Dart SDK
- Android Studio / Codice VS
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

4. **Crea APK di rilascio** (diviso per ABI per dimensioni inferiori):
   ```bash
   flutter build apk --split-per-abi
   ```

> L'URL di inoltro cloud è inserito in `lib/utils/api_constants.dart`
> (`relayBaseUrl`), quindi non è richiesto alcun flag di build. Per puntare al proprio relè:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️Server backend e streaming

### ☁️ Cloud Stream Relay — `server/` (distribuito il Render)
Risolve un URL audio YouTube **e inoltra i byte** in modo che il telefono e il risolutore condividano un IP
(n. 403). FastAPI + yt-dlp, Docker, livello gratuito.

| Punto finale | Descrizione |
| --- | --- |
| `GET /health` | Sonda di vitalità (`ok`) |
| `GET /stream?videoId=X&key=K` | Si risolve tramite yt-dlp → restituisce un URL `…/relay` (200 solo se si risolve) |
| `GET /relay?videoId=X&key=K` | Esegue il proxy dei byte audio (Range-aware → 206 per la ricerca) |

Protetto da una `RELAY_KEY` env var condivisa (restituisce **401** senza di essa). Schieramento: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Vedi `server/README.md`.

### 🎵 API dell'app — `backend/`
Il backend di dati/ricerca (YouTube Music tramite youtubei.js + fonti aperte: Last.fm generi,
MusicBrainz uscite e decenni).

| Punto finale | Descrizione |
| --- | --- |
| `/api/search` | Ricerca musica/video |
| `/api/trending` | Tendenza |
| `/api/charts` | Classifiche musicali YT |
| `/api/playlist/:id` | Dettagli playlist |
| `/api/moods`, `/api/moods/:id` | Categorie e stati d'animo (Last.fm fallback) |
| `/api/tags?tag=` | Genere brani/album principali (Last.fm) |
| `/api/newreleases` | Nuove uscite (MusicBrainz) |
| `/api/decades?year=` | Album per decennio (MusicBrainz) |
| `/api/categories` | Elenco categorie |

**Locale:** `cd backend && npm install && npm start` (porta 8000).
**Distribuisci (Vercel):** importa questo repository, **Root Directory = `backend`**. Vedi `backend/README.md`.

### 🗄️ Banca dati — `supabase/`
Schema Postgres con **Sicurezza a livello di riga**: le righe utente hanno come ambito `auth.uid()`, il catalogo è
di sola lettura per gli utenti anonimi e scrivibile solo dal ruolo del servizio. Esegui le migrazioni in Supabase
Editor SQL (in ordine).

---

## 🤝 Contribuire

I contributi sono benvenuti! Che si tratti di segnalare un bug, suggerire una funzionalità o scrivere codice, il tuo aiuto è apprezzato.

1. **Biforca il progetto**
2. **Crea il tuo ramo di funzionalità** (`git checkout -b feature/AmazingFeature`)
3. **Conferma le modifiche** (`git commit -m 'Add some AmazingFeature'`)
4. **Spingi al ramo** (`git push origin feature/AmazingFeature`)
5. **Apri una richiesta di pull**

**Linee guida:** segui lo stile del codice esistente, esegui `flutter analyze` (deve essere pulito) e testa le nuove funzionalità prima di inviarle.

---

## 🙏Ringraziamenti

Tunefy non esisterebbe senza l'incredibile lavoro di questi sviluppatori e progetti.

### youtube_explode_dart
Grazie a**[Hexer10](https://github.com/Hexer10)**, autore originale di
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) - la spina dorsale di Tunefy
YouTube streaming — e**[anandnet](https://github.com/anandnet)** per il fork aggiornato che
mantiene Tunefy funzionante con le ultime modifiche YouTube.

### Animesh (n-ce) — veloce-saavn e ytify
Un ringraziamento a**[Animesh (n-ce)](https://github.com/n-ce)**, creatore di
**[fast-saavn](https://github.com/n-ce/saavn)** (l'API JioSaavn aperta che alimenta i metadati di Tunefy)
e**[ytify](https://github.com/n-ce/ytify)** (un'enorme fonte di ispirazione).

### Librerie open source
| Pacchetto | Autore/Manutentori |
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

Distribuito sotto la **Licenza MIT**. Vedi [`LICENSE`](LICENSE) per ulteriori informazioni.
