<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>Klien musik yang kuat dan berfokus pada privasi yang dibuat dengan Flutter.</strong><br/>
  Bebas iklan · Offline · AI DJ · Lirik yang disinkronkan & diterjemahkan · Liquid Glass UI · 15 sumber · Tidak perlu akun
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
  <a href="#-fitur-utama">Fitur</a> ·
  <a href="#-lokalisasi">Bahasa</a> ·
  <a href="#-tangkapan-layar">Tangkapan Layar</a> ·
  <a href="#-arsitektur">Arsitektur</a> ·
  <a href="#-penyiapan--pemasangan">Pengaturan</a> ·
  <a href="#-server-backend--streaming">Server</a>
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

Tunefy adalah klien musik kaya fitur dan berfokus pada privasi yang dibuat dengan Flutter. Itu mengalir dari
**15+ sumber terbuka dan tanpa kunci** dengan kaskade fallback otomatis, sehingga track gagal pada salah satunya
penyedia bermain di berikutnya. Ini menawarkan pengalaman premium bebas iklan dengan pemutaran di latar belakang,
unduhan offline, lirik yang disinkronkan **dan diterjemahkan**, **AI DJ**, radio internet, konser,
berbagi daftar putar Blend, UI Liquid Glass modern, dan cache latar belakang cerdas — dengan atau tanpa
sebuah akun.

> [!NOTE]
> Tunefy didistribusikan langsung dari repositori ini (rilis APK). Ini **tidak** tersedia
> di Google Play Store.

---

## 🚀 Fitur Utama

### 🎨 Liquid Glass UI/UX
- **Tema Glassmorphic Dinamis** — Gaya premium dalam mode Gelap dan Terang melalui `liquid_glass_easy`. Mode Cahaya menggunakan warna putih semi transparan yang menyesuaikan dengan sampul album.
- **Shader & Blur Khusus** — Panel kaca buram berperforma tinggi dan lapisan luar yang beradaptasi dengan warna karya seni.
- **Elemen Sadar Kontras** — Ikon bilah status, kontrol, penggeser, dan menu dibalik secara otomatis agar mudah dibaca.
- **Pengoptimalan Layar Besar & Desktop** — Tata letak pemutar responsif (hingga 1300 piksel), dialog terpusat, dan bilah pencarian teratas khusus untuk desktop/tablet.

### 🎧 Audio, Lirik & Karaoke yang Imersif
- **Karaoke Kata demi Kata** — Kata-kata dipenuhi warna secara real-time saat artis bernyanyi (60+ FPS).
- **Sapuan Tersinkronisasi Baris demi Baris** — Efek sapuan progresif dengan sorotan garis aktif dan pengguliran halus.
- **Lirik yang Diterjemahkan** — Lirik diterjemahkan oleh mesin (DeepL) ke dalam bahasa aplikasi Anda dengan cepat.
- **Mode Lofi** — Ubah trek apa pun menjadi getaran Lofi: diperlambat 0,9×, koreksi nada, gema asli.
- **Equalizer & Efek Asli** — EQ tingkat sistem dengan pemutaran latar belakang dan audio layar mati.
- **Audio Multi-Bahasa & Kontrol Kualitas** — Mendeteksi bahasa audio yang tersedia dan streaming kualitas Tinggi/Sedang/Rendah.

### 🤖 AI DJ & Personalisasi
- **AI DJ Assistant (Gemini)** — DJ percakapan yang membaca selera Anda, membuat playlist cerdas, dan menerima permintaan.
- **Sinyal Rasa** — Penilaian rasa per lagu mempelajari apa yang Anda sukai dan mendorong rekomendasi.
- **Wrapped & Statistik Mendengarkan** — Ulasan Anda selama setahun: artis papan atas, suasana hati, dan kapsul pendengaran.
- **Sistem Cache Cerdas** — Caching latar belakang audio asinkron + karya seni multi-resolusi untuk pemutaran instan tanpa menunggu.

### 🌍 Penemuan di 15+ Sumber
Tunefy menyelesaikan pemutaran melalui **kaskade fallback otomatis** di seluruh penyedia ini (tanpa kunci = tidak diperlukan kunci API):

| Sumber | Ketik | Catatan |
|---|---|---|
| **YouTube / Musik YT** | Video / Audio | Utama, melalui youtube_explode + API internal |
| **Jamendo** | Tanpa kunci | Katalog Creative-Commons |
| **Deezer** | Tanpa kunci | Katalog + metadata |
| **Audius** | Tanpa kunci | Seniman yang terdesentralisasi |
| **JioSaavn** | Buka API | Fast metadata & search |
| **Invidious** | Keyless | YouTube cermin (4 contoh) |
| **Piped** | Buka API | YouTube mirror |
| **OpenVerse** | Keyless | Gambar/audio CC *(baru)* |
| **Wikimedia Commons** | Tanpa kunci | Buka media *(baru)* |
| **Beatport** | Keyless | Elektronik/tari *(baru)* |
| **Dailymotion** | Keyless | Video fallback *(new)* |
| **ccMixter** | Keyless | Remix culture *(new)* |
| **Internet Archive** | Keyless | Audio historis *(baru)* |
| **Radio Browser** | Keyless | Stasiun radio internet |
| **iTunes / MusicBrainz / Last.fm** | Open | Metadata, bagan, genre |

- **Cloud Stream Relay** — Relai yang dihosting sendiri menyelesaikan dan **memproksi byte audio** dari IP yang sama dengan yang digunakan pemutar, menghindari HTTP 403 yang dikembalikan oleh tautan Googlevideo yang dikunci IP. See [Servers](#-server-backend--streaming).
- **Spotify Impor** — Tempelkan URL daftar putar Spotify publik mana pun (atau pindai kode Spotify) untuk mengimpor lagu.
- **Pencarian Global** — Satu pencarian untuk lagu, video, album, artis, dan podcast.
- **Bagikan untuk Memutar** — Bagikan tautan Musik YouTube/YT langsung ke Tunefy.

### 📻 Radio, Konser & Video
- **Radio Internet** — Ribuan stasiun langsung (Radio Browser).
- **Konser** — Temukan acara langsung di dekat Anda dengan halaman yang kaya detail.
- **Umpan Klip** — Umpan video pendek vertikal dari komunitas dan klip yang sedang tren.
- **Pemutar Video** — Pemutaran video penuh dengan latar belakang video kanvas.
- **DJ Mixes** — Penemuan dan pemutaran DJ/mix khusus.

### 🤝 Sosial, Campuran & Komunitas
- **Blend Daftar Putar** — Membuat daftar putar bersama dengan kode gabungan singkat (misalnya `KORA-4821`); siapa pun yang memiliki kode dapat mendengarkan dan berkontribusi, seperti tautan Spotify Blend.
- **Umpan Komunitas** — Telusuri, streaming, dan temukan lagu yang diunggah oleh komunitas.
- **Mengikuti Artis** — Ikuti artis/saluran untuk melacaknya.
- **Antrian Cerdas & Pemutaran Tak Terbatas** — Antrean otomatis dengan perilaku cerdas yang jelas.

### 🔐 Privasi & Akun
- **Tidak Perlu Akun** — Favorit, daftar putar, dan riwayat disimpan secara lokal secara default.
- **Anonim + Masuk dengan Google** — Masuk opsional (identitas perangkat anonim atau Google melalui Supabase Auth) untuk sinkronisasi dan profil cloud.
- **Unduhan Offline** — Unduh lagu dan video untuk didengarkan secara offline.
- **Tautan Dalam** — Skema URL khusus lengkap untuk membuka/memutar lagu, artis, album, dan daftar putar melalui browser atau tautan bersama.
- **Bebas Iklan & Andal** — Mendengarkan tanpa gangguan yang didukung oleh relay terbuka (Last.fm, MusicBrainz, iTunes) untuk menjamin pemutaran.

---

## 🌐 Lokalisasi

Tunefy dikirimkan dengan **terjemahan lengkap** dalam 14 bahasa (ditambah bahasa sistem otomatis):

| Bahasa | Kode | Bahasa | Kode |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Atur bahasa di **Pengaturan → Bahasa** (atau simpan **Sistem** untuk deteksi otomatis).

---

## 📸 Tangkapan layar

### 🏠 Beranda & Navigasi
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Layar Beranda" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Rumah dengan Mini Player" />
  <img src="images/library.jpg" width="30%" alt="Perpustakaan" />
</p>

### 🔍 Cari
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Hasil Pencarian" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Saran Pencarian" />
</p>

### 🎵 Pemain
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Pemain Imersif" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Pemain Warisan" />
  <img src="images/song_queue.jpg" width="30%" alt="Antrean Lagu" />
</p>

### 🎤 Lyrics
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Lirik dengan Kontrol" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Lirik tanpa Kontrol" />
</p>

### 👥 Komunitas & Profil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Umpan Komunitas" />
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
  <img src="images/about_screen.jpg" width="30%" alt="Tentang Layar" />
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

**Keandalan pemutaran.** Aplikasi tidak pernah bergantung pada satu penyedia. Ini menyelidiki sumber di a
kaskade prioritas (relai lokal → relai cloud → cermin tanpa kunci → pencarian metadata/judul), dengan a
pemutus sirkuit yang melewatkan sumber yang gagal. **cloud relay** menyelesaikan streaming, lalu
**menyampaikan byte** melalui koneksinya sendiri sehingga resolusi dan pemutaran berbagi satu IP — ini dia
apa yang menghindari 403 yang dikunci IP pada tautan video Google.

---

## 🛠️ Tumpukan Teknologi

| Lapisan | Teknologi |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Manajemen Negara** | [Riverpod](https://riverpod.dev/) |
| **Audio Engine** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Ekstraksi** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (bercabang oleh [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Lyrics** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + mesin karaoke khusus + DeepL terjemahan |
| **Local Storage** | [Hive](https://docs.hivedb.dev/) |
| **Cloud Sync / Auth** | Supabase (Postgres + RLS, anonim & masuk Google) |
| **Networking** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Stream Relay** | FastAPI + yt-dlp pada Render (`server/`) |
| **UI Components** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Penyiapan & Pemasangan

### Prasyarat
- Flutter SDK (Stabil Terbaru)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Installation

1. **Kloning repositori:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Instal dependensi:**
   ```bash
   flutter pub get
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

4. **Buat APK rilis** (dibagi berdasarkan ABI untuk ukuran lebih kecil):
   ```bash
   flutter build apk --split-per-abi
   ```

> URL relai cloud dimasukkan ke dalam `lib/utils/api_constants.dart`
> (`relayBaseUrl`), jadi tidak diperlukan flag build. Untuk menunjuk pada relai Anda sendiri:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Server Backend & Streaming

### ☁️ Cloud Stream Relay — `server/` (digunakan pada Render)
Menyelesaikan URL audio YouTube **dan meneruskan byte** sehingga ponsel dan penyelesai berbagi satu IP
(no 403). FastAPI + yt-dlp, Docker, tingkat gratis.

| Endpoint | Deskripsi |
| --- | --- |
| `GET /health` | Pemeriksaan keaktifan (`ok`) |
| `GET /stream?videoId=X&key=K` | Diselesaikan melalui yt-dlp → mengembalikan URL `…/relay` (200 hanya jika terselesaikan) |
| `GET /relay?videoId=X&key=K` | Proksi byte audio (Range-aware → 206 untuk mencari) |

Dilindungi oleh `RELAY_KEY` env var bersama (mengembalikan **401** tanpanya). Terapkan: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. See `server/README.md`.

### 🎵 API Aplikasi — `backend/`
Backend data/pencarian (YouTube Music melalui youtubei.js + sumber terbuka: Last.fm genre,
MusicBrainz rilis & dekade).

| Endpoint | Deskripsi |
| --- | --- |
| `/api/search` | Music / video search |
| `/api/trending` | Sedang Tren |
| `/api/charts` | YT Music charts |
| `/api/playlist/:id` | Detail daftar putar |
| `/api/moods`, `/api/moods/:id` | Kategori & suasana hati (Last.fm fallback) |
| `/api/tags?tag=` | Lagu/album teratas bergenre (Last.fm) |
| `/api/newreleases` | Rilis baru (MusicBrainz) |
| `/api/decades?year=` | Album berdasarkan dekade (MusicBrainz) |
| `/api/categories` | Daftar kategori |

**Lokal:** `cd backend && npm install && npm start` (pelabuhan 8000).
**Deploy (Vercel):** impor repo ini, **Root Directory = `backend`**. Lihat `backend/README.md`.

### 🗄️ Basis Data — `supabase/`
Skema Postgres dengan **Keamanan Tingkat Baris**: baris pengguna dicakup ke `auth.uid()`, katalognya adalah
hanya baca untuk pengguna anonim dan hanya dapat ditulis oleh peran layanan. Jalankan migrasi di Supabase
Editor SQL (secara berurutan).

---

## 🤝 Berkontribusi

Kontribusi dipersilakan! Baik itu melaporkan bug, menyarankan fitur, atau menulis kode, bantuan Anda sangat kami hargai.

1. **Bagikan Proyek**
2. **Buat Cabang Fitur Anda** (`git checkout -b feature/AmazingFeature`)
3. **Komit Perubahan Anda** (`git commit -m 'Add some AmazingFeature'`)
4. **Dorong ke Cabang** (`git push origin feature/AmazingFeature`)
5. **Buka Permintaan Tarik**

**Pedoman:** ikuti gaya kode yang ada, jalankan `flutter analyze` (harus bersih), dan uji fitur baru sebelum mengirimkan.

---

## 🙏 Ucapan Terima Kasih

Tunefy tidak akan ada tanpa kerja luar biasa dari para pengembang dan proyek ini.

### youtube_explode_dart
Terima kasih kepada**[Hexer10](https://github.com/Hexer10)**, penulis asli
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — tulang punggung Tunefy
YouTube streaming — dan**[anandnet](https://github.com/anandnet)** untuk fork terkini yang
terus Tunefy berfungsi dengan perubahan YouTube terbaru.

### Animesh (n-ce) — saavn cepat & ytify
Berteriak kepada**[Animesh (n-ce)](https://github.com/n-ce)**, pencipta
**[fast-saavn](https://github.com/n-ce/saavn)** (API JioSaavn terbuka yang mendukung metadata Tunefy)
dan**[ytify](https://github.com/n-ce/ytify)** (sumber inspirasi yang sangat besar).

### Perpustakaan Sumber Terbuka
| Paket | Penulis / Pengelola |
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
