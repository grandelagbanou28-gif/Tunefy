<p align="center">
  <img src="assets/logo.png" alt="Logo Tunefy" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Klien musik yang kuat dan berfokus pada privasi, dibangun dengan Flutter.</strong><br/>
  Tanpa iklan · Offline · DJ AI · Lirik tersinkron & terjemahan · UI Liquid Glass · 15 sumber · Tanpa akun
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Versi" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Platform" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Bahasa" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Lisensi" />
</p>

<p align="center">
  <a href="#-key-features">Fitur</a> ·
  <a href="#-localisation">Bahasa</a> ·
  <a href="#-screenshots">Tangkapan layar</a> ·
  <a href="#-architecture">Arsitektur</a> ·
  <a href="#-setup--installation">Penyiapan</a> ·
  <a href="#-backend--streaming-servers">Server</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.fo.md">Fongbé</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt.md">Português</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.hi.md">हिन्दी</a> ·
  <b>Bahasa Indonesia</b> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy adalah klien musik kaya fitur dan berfokus pada privasi, dibangun dengan Flutter. Ia melakukan streaming dari
**15+ sumber terbuka dan tanpa kunci** dengan kaskade cadangan otomatis, sehingga sebuah lagu yang gagal pada satu
penyedia akan diputar pada penyedia berikutnya. Ia menawarkan pengalaman premium bebas iklan dengan pemutaran latar belakang,
unduhan offline, lirik tersinkron **dan terjemahan**, **DJ AI**, radio internet, konser,
playlist Blend bersama, UI Liquid Glass modern, dan cache latar belakang yang cerdas — dengan atau tanpa akun.

> [!NOTE]
> Tunefy didistribusikan langsung dari repositori ini (rilis APK). Ia **tidak** tersedia
> di Google Play Store.

---

## 🚀 Fitur Utama

### 🎨 UI/UX Liquid Glass
- **Tema Glassmorphic Dinamis** — Gaya premium dalam mode Gelap dan Terang melalui `liquid_glass_easy`. Mode Terang menggunakan rona putih semi-transparan yang menyesuaikan dengan sampul album.
- **Shader Kustom & Blur** — Panel kaca buram dan overlay berperforma tinggi yang menyesuaikan dengan warna artwork.
- **Elemen Sadar Kontras** — Ikon bilah status, kontrol, slider, dan menu otomatis membalik agar tetap terbaca.
- **Optimasi Layar Besar & Desktop** — Tata letak pemutar responsif (hingga 1300px), dialog yang dipusatkan, dan bilah pencarian atas khusus untuk desktop/tablet.

### 🎧 Audio Imersif, Lirik & Karaoke
- **Kata per Kata Karaoke** — Kata-kata terisi warna secara real-time saat artis bernyanyi (60+ FPS).
- **Sinkron Baris demi Baris** — Efek sapuan progresif dengan sorotan baris aktif dan guliran halus.
- **Lirik Terjemahan** — Lirik diterjemahkan secara mesin (DeepL) ke bahasa aplikasi Anda secara langsung.
- **Mode Lofi** — Ubah lagu apa pun menjadi suasana Lofi: melambat 0.9×, koreksi pitch, reverb native.
- **Pemerata Suara & Efek Native** — EQ tingkat sistem dengan pemutaran latar belakang dan audio saat layar mati.
- **Audio Multi-Bahasa & Kontrol Kualitas** — Deteksi bahasa audio yang tersedia dan streaming kualitas Tinggi/Sedang/Rendah.

### 🤖 DJ AI & Personalisasi
- **Asisten DJ AI (Gemini)** — DJ percakapan yang membaca selera Anda, membuat playlist cerdas, dan menerima permintaan.
- **Sinyal Selera** — Penilaian selera per lagu mempelajari apa yang Anda sukai dan menggerakkan rekomendasi.
- **Wrapped & Statistik Dengar** — Tinjauan tahunan Anda: artis teratas, mood, dan kapsul dengar.
- **Sistem Cache Cerdas** — Cache latar belakang asinkron untuk audio + artwork multi-resolusi agar pemutaran instan tanpa menunggu.

### 🌍 Penemuan di 15+ Sumber
Tunefy menyelesaikan pemutaran melalui **kaskade cadangan otomatis** di antara penyedia berikut (tanpa kunci = tidak perlu API key):

| Sumber | Jenis | Catatan |
|---|---|---|
| **YouTube / YT Music** | Video / Audio | Utama, melalui youtube_explode + API internal |
| **Jamendo** | Tanpa kunci | Katalog Creative Commons |
| **Deezer** | Tanpa kunci | Katalog + metadata |
| **Audius** | Tanpa kunci | Artis terdesentralisasi |
| **JioSaavn** | API Terbuka | Metadata & pencarian cepat |
| **Invidious** | Tanpa kunci | Mirror YouTube (4 instance) |
| **Piped** | API Terbuka | Mirror YouTube |
| **OpenVerse** | Tanpa kunci | Gambar/audio CC *(baru)* |
| **Wikimedia Commons** | Tanpa kunci | Media terbuka *(baru)* |
| **Beatport** | Tanpa kunci | Elektronik/dance *(baru)* |
| **Dailymotion** | Tanpa kunci | Cadangan video *(baru)* |
| **ccMixter** | Tanpa kunci | Budaya remix *(baru)* |
| **Internet Archive** | Tanpa kunci | Audio bersejarah *(baru)* |
| **Radio Browser** | Tanpa kunci | Stasiun radio internet |
| **iTunes / MusicBrainz / Last.fm** | Terbuka | Metadata, tangga lagu, genre |

- **Relai Stream Cloud** — Relai yang di-hosting sendiri menyelesaikan dan **meneruskan byte audio** dari IP yang sama yang digunakan pemutar, menghindari HTTP 403 yang biasanya dikembalikan oleh tautan Googlevideo yang terkunci IP. Lihat [Server](#-backend--streaming-servers).
- **Impor Spotify** — Tempel URL playlist Spotify publik apa pun (atau pindai kode Spotify) untuk mengimpor lagu.
- **Pencarian Global** — Satu pencarian di lagu, video, album, artis, dan podcast.
- **Bagikan untuk Diputar** — Bagikan tautan YouTube/YT Music langsung ke Tunefy.

### 📻 Radio, Konser & Video
- **Radio Internet** — Ribuan stasiun langsung (Radio Browser).
- **Konser** — Temukan acara langsung di sekitar Anda dengan halaman detail yang kaya.
- **Feed Klip** — Feed video pendek vertikal berisi klip komunitas dan yang sedang tren.
- **Pemutar Video** — Pemutaran video penuh dengan latar belakang video kanvas.
- **Mix DJ** — Penemuan dan pemutaran DJ/mix khusus.

### 🤝 Sosial, Blend & Komunitas
- **Playlist Blend** — Buat playlist bersama dengan kode gabungan singkat (mis. `KORA-4821`); siapa pun yang memiliki kode dapat mendengarkan dan berkontribusi, seperti tautan Blend di Spotify.
- **Feed Komunitas** — Cari, streaming, dan temukan lagu yang diunggah oleh komunitas.
- **Mengikuti Artis** — Ikuti artis/kanal untuk tetap memantau karya mereka.
- **Antrean Cerdas & Pemutaran Tak Terbatas** — Antrean otomatis dengan perilaku pembersihan yang cerdas.

### 🔐 Privasi & Akun
- **Tanpa Akun** — Favorit, playlist, dan riwayat disimpan secara lokal secara bawaan.
- **Masuk Anonim + Google** — Opsi masuk (identitas perangkat anonim atau Google melalui Supabase Auth) untuk sinkronisasi cloud dan profil.
- **Unduhan Offline** — Unduh lagu dan video untuk didengarkan secara offline.
- **Deep Linking** — Skema URL kustom lengkap untuk membuka/memutar lagu, artis, album, dan playlist melalui browser atau tautan yang dibagikan.
- **Bebas Iklan & Andal** — Dengar tanpa gangguan yang ditopang oleh relai terbuka (Last.fm, MusicBrainz, iTunes) untuk menjamin pemutaran.

---

## 🌐 Lokalisasi

Tunefy hadir dengan **terjemahan lengkap** dalam 14 bahasa (ditambah bahasa sistem otomatis):

| Bahasa | Kode | Bahasa | Kode |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Atur bahasa di **Settings → Language** (atau biarkan **System** untuk deteksi otomatis).

---

## 📸 Tangkapan Layar

### 🏠 Beranda & Navigasi
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Layar Beranda" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Beranda dengan Mini Player" />
  <img src="images/library.jpg" width="30%" alt="Pustaka" />
</p>

### 🔍 Pencarian
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Hasil Pencarian" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Saran Pencarian" />
</p>

### 🎵 Pemutar
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Pemutar Imersif" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Pemutar Legacy" />
  <img src="images/song_queue.jpg" width="30%" alt="Antrean Lagu" />
</p>

### 🎤 Lirik
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Lirik dengan Kontrol" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Lirik tanpa Kontrol" />
</p>

### 👥 Komunitas & Profil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Feed Komunitas" />
  <img src="images/profile_screen.jpg" width="30%" alt="Layar Profil" />
</p>

### ⚙️ Pengaturan & Kustomisasi
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Pengaturan" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Pemilih Tema" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Warna Aksen" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Warna Aksen Kustom" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Pemilih Bahasa" />
</p>

### ℹ️ Tentang
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Layar Tentang" />
</p>

---

## 🏗️ Arsitektur

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

**Keandalan pemutaran.** Aplikasi tidak pernah bergantung pada satu penyedia. Ia meninjau sumber dalam
kaskade prioritas (relai lokal → relai cloud → mirror tanpa kunci → pencarian metadata/judul), dengan
pemutus sirkuit yang melewatkan sumber yang bermasalah. **Relai cloud** menyelesaikan sebuah stream lalu
**meneruskan byte** melalui koneksi miliknya sendiri sehingga resolusi dan pemutaran berbagi satu IP — inilah
yang menghindari 403 terkunci-IP pada tautan Googlevideo.

---

## 🛠️ Tech Stack

| Lapisan | Teknologi |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Manajemen Status** | [Riverpod](https://riverpod.dev/) |
| **Mesin Audio** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **Ekstraksi YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork oleh [anandnet](https://github.com/anandnet)) |
| **DJ AI** | Google Gemini (`gemini_service`) |
| **Lirik** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + mesin karaoke kustom + terjemahan DeepL |
| **Penyimpanan Lokal** | [Hive](https://docs.hivedb.dev/) |
| **Sinkronisasi Cloud / Auth** | Supabase (Postgres + RLS, masuk anonim & Google) |
| **Jaringan** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relai Stream** | FastAPI + yt-dlp di Render (`server/`) |
| **Komponen UI** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Penyiapan & Pemasangan

### Prasyarat
- Flutter SDK (Stable terbaru)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Pemasangan

1. **Clone repositori:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Instal dependensi:**
   ```bash
   flutter pub get
   ```

3. **Jalankan aplikasi:**
   ```bash
   flutter run
   ```

4. **Build APK rilis** (dipecah per ABI agar ukurannya lebih kecil):
   ```bash
   flutter build apk --split-per-abi
   ```

> URL relai cloud tertanam di `lib/utils/api_constants.dart` (`relayBaseUrl`),
> jadi tidak perlu flag build. Untuk menunjuk ke relai Anda sendiri:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend & Server Streaming

### ☁️ Relai Stream Cloud — `server/` (di-deploy di Render)
Menyelesaikan URL audio YouTube **dan meneruskan byte** sehingga ponsel dan pemresolve berbagi satu IP (tanpa 403). FastAPI + yt-dlp, Docker, paket gratis.

| Endpoint | Deskripsi |
| --- | --- |
| `GET /health` | Probe kelangsungan hidup (`ok`) |
| `GET /stream?videoId=X&key=K` | Menyelesaikan via yt-dlp → mengembalikan URL `…/relay` (200 hanya jika berhasil diselesaikan) |
| `GET /relay?videoId=X&key=K` | Meneruskan byte audio (sadar-Range → 206 untuk seeking) |

Dilindungi oleh variabel env bersama `RELAY_KEY` (mengembalikan **401** tanpanya). Deploy: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Lihat `server/README.md`.

### 🎵 API Aplikasi — `backend/`
Backend data/pencarian (YouTube Music via youtubei.js + sumber terbuka: genre Last.fm,
rilis & dekade MusicBrainz).

| Endpoint | Deskripsi |
| --- | --- |
| `/api/search` | Pencarian musik / video |
| `/api/trending` | Sedang tren |
| `/api/charts` | Tangga lagu YT Music |
| `/api/playlist/:id` | Detail playlist |
| `/api/moods`, `/api/moods/:id` | Kategori & mood (cadangan Last.fm) |
| `/api/tags?tag=` | Lagu/album teratas per genre (Last.fm) |
| `/api/newreleases` | Rilis baru (MusicBrainz) |
| `/api/decades?year=` | Album per dekade (MusicBrainz) |
| `/api/categories` | Daftar kategori |

**Lokal:** `cd backend && npm install && npm start` (port 8000).
**Deploy (Vercel):** impor repositori ini, **Root Directory = `backend`**. Lihat `backend/README.md`.

### 🗄️ Database — `supabase/`
Skema Postgres dengan **Row-Level Security**: baris pengguna dibatasi ke `auth.uid()`, katalog
hanya-baca untuk pengguna anonim dan hanya dapat ditulis oleh service role. Jalankan migrasi di SQL
Editor Supabase (sesuai urutan).

---

## 🤝 Kontribusi

Kontribusi sangat diterima! Baik itu melaporkan bug, mengusulkan fitur, maupun menulis kode, bantuan Anda dihargai.

1. **Fork Proyek**
2. **Buat Branch Fitur Anda** (`git checkout -b feature/AmazingFeature`)
3. **Commit Perubahan Anda** (`git commit -m 'Add some AmazingFeature'`)
4. **Push ke Branch** (`git push origin feature/AmazingFeature`)
5. **Buka Pull Request**

**Pedoman:** ikuti gaya kode yang ada, jalankan `flutter analyze` (harus bersih), dan uji fitur baru sebelum mengirim.

---

## 🙏 Penghargaan

Tunefy tidak akan ada tanpa kerja luar biasa dari pengembang dan proyek berikut.

### youtube_explode_dart
Terima kasih untuk **[Hexer10](https://github.com/Hexer10)**, penulis asli
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — tulang punggung streaming YouTube
Tunefy — dan **[anandnet](https://github.com/anandnet)** untuk fork yang selalu diperbarui sehingga
Tunefy tetap berfungsi dengan perubahan terbaru YouTube.

### Animesh (n-ce) — fast-saavn & ytify
Ucapan terima kasih untuk **[Animesh (n-ce)](https://github.com/n-ce)**, pencipta
**[fast-saavn](https://github.com/n-ce/saavn)** (API JioSaavan terbuka yang menggerakkan metadata Tunefy)
dan **[ytify](https://github.com/n-ce/ytify)** (sumber inspirasi yang luar biasa).

### Pustaka Open-Source
| Paket | Penulis / Pemelihara |
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

## 📄 Lisensi

Didistribusikan di bawah **Lisensi MIT**. Lihat [`LICENSE`](LICENSE) untuk informasi lebih lanjut.
