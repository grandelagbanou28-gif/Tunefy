<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Flutter ile geliştirilmiş, gizliliğe odaklanan güçlü bir müzik istemcisi.</strong><br/>
  Reklamsız · Çevrimdışı · Yapay Zekâ DJ · Senkron & çeviri sözler · Liquid Glass arayüzü · 15 kaynak · Hesap gerekmez
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Sürüm" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Platform" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Diller" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Lisans" />
</p>

<p align="center">
  <a href="#-key-features">Özellikler</a> ·
  <a href="#-localisation">Diller</a> ·
  <a href="#-screenshots">Görüntüler</a> ·
  <a href="#-architecture">Mimari</a> ·
  <a href="#-setup--installation">Kurulum</a> ·
  <a href="#-backend--streaming-servers">Sunucular</a>
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
  <a href="README.id.md">Bahasa Indonesia</a> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <b>Türkçe</b> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy, Flutter ile geliştirilmiş, zengin özellikli ve gizliliğe odaklanan bir müzik istemcisidir.
**15+ açık ve anahtarsız kaynaktan**, otomatik bir yedekleme kaskadı ile yayın yapar; bir sağlayıcıda
başarısız olan parça bir sonrakinde çalınır. Arka planda oynatma, çevrimdışı indirmeler, senkronize
**ve çevrilmiş** sözler, bir **Yapay Zekâ DJ**, internet radyosu, konserler, paylaşılan Blend listeleri,
modern bir Liquid Glass arayüzü ve akıllı arka plan önbellekleme ile premium, reklamsız bir deneyim sunar —
hesaplı ya da hesapsız.

> [!NOTE]
> Tunefy doğrudan bu depodan dağıtılır (APK sürümleri). Google Play Store'da
> **mevcut değildir**.

---

## 🚀 Temel Özellikler

### 🎨 Liquid Glass Arayüz/UX
- **Dinamik Glassmorphic Temalar** — `liquid_glass_easy` aracılığıyla Koyu ve Açık modlarda premium görünüm. Açık Mod, albüm kapaklarına uyum sağlayan yarı saydam beyaz bir ton kullanır.
- **Özel Shader'lar & Bulanıklık** — Sanat eserinin renklerine uyum sağlayan, yüksek performanslı buzlu cam panelleri ve katmanları.
- **Kontrast Duyarlı Öğeler** — Durum çubuğu simgeleri, kontroller, kaydırıcılar ve menüler okunabilirlik için otomatik olarak ters çevrilir.
- **Büyük Ekran & Masaüstü Optimizasyonu** — Duyarlı oynatıcı düzenleri (1300px'e kadar), ortalanmış diyaloglar ve masaüstü/tablet için özel bir üst arama çubuğu.

### 🎧 Sürükleyici Ses, Sözler & Karaoke
- **Kelime Kelime Karaoke** — Şarkıcı söylerken kelimeler gerçek zamanlı olarak renklenir (60+ FPS).
- **Satır Satır Senkron Geçiş** — Etkin satır vurgusu ve akıcı kaydırma ile ilerlemeli geçiş efekti.
- **Çevrilmiş Sözler** — Sözler, uygulamanızın diline anında makinece çevrilir (DeepL).
- **Lofi Modu** — Herhangi bir parçayı Lofi havasına dönüştürün: 0.9× yavaşlatma, perde düzeltme, yerel yankı.
- **Ekolayzer & Yerel Efektler** — Arka planda oynatma ve ekran kapalıyken ses ile sistem düzeyinde EQ.
- **Çok Dilli Ses & Kalite Kontrolü** — Mevcut ses dillerini algılayın ve Yüksek/Orta/Düşük kalitede yayınlayın.

### 🤖 Yapay Zekâ DJ & Kişiselleştirme
- **Yapay Zekâ DJ Asistanı (Gemini)** — Zevkinizi okuyan, akıllı listeler oluşturan ve istekleri alan sohbet tabanlı bir DJ.
- **Zevk Sinyalleri** — Parça başına zevk puanlaması, sevdiğiniz şeyleri öğrenir ve önerileri yönlendirir.
- **Wrapped & Dinleme İstatistikleri** — Yılın özeti: en iyi sanatçılar, ruh halleri ve dinleme kapsülleri.
- **Akıllı Önbellek Sistemi** — Anında, beklemeden oynatma için ses + çok çözünürlüklü kapak görsellerinin arka planda asenkron önbelleklenmesi.

### 🌍 15+ Kaynakta Keşif
Tunefy, oynatmayı şu sağlayıcılar arasında **otomatik bir yedekleme kaskadı** ile çözer (anahtarsız = API anahtarı gerekmez):

| Kaynak | Tür | Notlar |
|---|---|---|
| **YouTube / YT Music** | Video / Ses | Birincil, youtube_explode + dahili API ile |
| **Jamendo** | Anahtarsız | Creative Commons kataloğu |
| **Deezer** | Anahtarsız | Katalog + üst veri |
| **Audius** | Anahtarsız | Merkeziyetsiz sanatçılar |
| **JioSaavn** | Açık API | Hızlı üst veri & arama |
| **Invidious** | Anahtarsız | YouTube yansıması (4 örnek) |
| **Piped** | Açık API | YouTube yansıması |
| **OpenVerse** | Anahtarsız | CC görseller/ses *(yeni)* |
| **Wikimedia Commons** | Anahtarsız | Açık medya *(yeni)* |
| **Beatport** | Anahtarsız | Elektronik/dans *(yeni)* |
| **Dailymotion** | Anahtarsız | Video yedeği *(yeni)* |
| **ccMixter** | Anahtarsız | Remix kültürü *(yeni)* |
| **Internet Archive** | Anahtarsız | Tarihsel ses *(yeni)* |
| **Radio Browser** | Anahtarsız | İnternet radyo istasyonları |
| **iTunes / MusicBrainz / Last.fm** | Açık | Üst veri, listeler, türler |

- **Bulut Akış Aktarıcısı** — Kendi barındırdığınız bir aktarıcı, oynatıcının kullandığı aynı IP'den ses baytlarını çözer ve **aracılık eder**; aksi halde IP kilitli Googlevideo bağlantılarının döndürdüğü HTTP 403 hatalarını önler. Bkz. [Sunucular](#-backend--streaming-servers).
- **Spotify İçe Aktarma** — Herhangi bir herkese açık Spotify liste adresini (veya bir Spotify kodunu) yapıştırarak parçaları içe aktarın.
- **Genel Arama** — Şarkılar, videolar, albümler, sanatçılar ve podcast'ler üzerinde tek arama.
- **Paylaş ve Çal** — YouTube/YT Music bağlantılarını doğrudan Tunefy'ye paylaşın.

### 📻 Radyo, Konserler & Video
- **İnternet Radyosu** — Binlerce canlı istasyon (Radio Browser).
- **Konserler** — Yakınınızdaki canlı etkinlikleri zengin ayrıntı sayfalarıyla keşfedin.
- **Klip Akışı** — Topluluk ve trend kliplerden oluşan dikey kısa video akışı.
- **Video Oynatıcı** — Tuval video arka planlarıyla tam video oynatma.
- **DJ Mix** — Özel DJ/mix keşfi ve oynatımı.

### 🤝 Sosyal, Blend'ler & Topluluk
- **Blend Listeleri** — Kısa bir katılma koduyla (örn. `KORA-4821`) ortak bir liste oluşturun; kodu olan herkes, Spotify Blend bağlantılarında olduğu gibi dinleyebilir ve katkıda bulunabilir.
- **Topluluk Akışı** — Topluluğun yüklediği parçaları arayın, yayınlayın ve keşfedin.
- **Sanatçı Takibi** — Sanatçıları/kanalları takip ederek onlardan haberdar olun.
- **Akıllı Kuyruk & Sonsuz Oynatma** — Akıllı temizleme davranışıyla otomatik kuyruk.

### 🔐 Gizlilik & Hesaplar
- **Hesap Gerekmez** — Favoriler, listeler ve geçmiş varsayılan olarak yerel olarak saklanır.
- **Anonim + Google ile Giriş** — Bulut senkronizasyonu ve profil için isteğe bağlı giriş (anonim cihaz kimliği veya Supabase Auth üzerinden Google).
- **Çevrimdışı İndirmeler** — Çevrimdışı dinlemek için şarkıları ve videoları indirin.
- **Deep Linking** — Tarayıcı veya paylaşılan bağlantılar aracılığıyla şarkıları, sanatçıları, albümleri ve listeleri açmak/oynatmak için tam özel URL şeması.
- **Reklamsız & Güvenilir** — Kesintisiz dinleme; oynatmayı garanti etmek için açık aktarıcılar (Last.fm, MusicBrainz, iTunes) tarafından desteklenir.

---

## 🌐 Yerelleştirme
Tunefy, 14 dilde **tam çevirilerle** gelir (otomatik sistem dili hariç):

| Dil | Kod | Dil | Kod |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Dili **Ayarlar → Dil** bölümünden ayarlayın (otomatik algılama için **Sistem**'de bırakın).

---

## 📸 Görüntüler

### 🏠 Ana Sayfa & Gezinme
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Ana Sayfa Ekranı" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Mini Oynatıcılı Ana Sayfa" />
  <img src="images/library.jpg" width="30%" alt="Kütüphane" />
</p>

### 🔍 Arama
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Arama Sonuçları" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Arama Önerileri" />
</p>

### 🎵 Oynatıcı
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Sürükleyici Oynatıcı" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Eski Oynatıcı" />
  <img src="images/song_queue.jpg" width="30%" alt="Şarkı Kuyruğu" />
</p>

### 🎤 Sözler
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Kontrollü Sözler" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Kontrollersiz Sözler" />
</p>

### 👥 Topluluk & Profil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Topluluk Akışı" />
  <img src="images/profile_screen.jpg" width="30%" alt="Profil Ekranı" />
</p>

### ⚙️ Ayarlar & Özelleştirme
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Ayarlar" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Tema Seçici" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Vurgu Rengi" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Özel Vurgu Rengi" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Dil Seçici" />
</p>

### ℹ️ Hakkında
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Hakkında Ekranı" />
</p>

---

## 🏗️ Mimari

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

**Oynatma güvenilirliği.** Uygulama hiçbir zaman tek bir sağlayıcıya bağlı değildir. Kaynakları öncelik kaskadında tarar (yerel aktarıcı → bulut aktarıcı → anahtarsız yansımlar → üst veri/başlık araması) ve başarısız olan kaynağı atlayan bir devre açma mekanizması kullanır. **Bulut aktarıcı**, bir akışı çözer ve ardından **baytları kendi bağlantısı üzerinden aktarır**; böylece çözümleme ve oynatma aynı IP'yi paylaşır — Googlevideo bağlantılarındaki IP kilitli 403'ü önleyen şey budur.

---

## 🛠️ Teknoloji Yığını

| Katman | Teknoloji |
|---|---|
| **Çerçeve** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Durum Yönetimi** | [Riverpod](https://riverpod.dev/) |
| **Ses Motoru** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Çıkarma** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork: [anandnet](https://github.com/anandnet)) |
| **Yapay Zekâ DJ** | Google Gemini (`gemini_service`) |
| **Sözler** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + özel karaoke motoru + DeepL çevirisi |
| **Yerel Depolama** | [Hive](https://docs.hivedb.dev/) |
| **Bulut Senkronizasyonu / Kimlik Doğrulama** | Supabase (Postgres + RLS, anonim & Google girişi) |
| **Ağ** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Akış Aktarıcısı** | FastAPI + yt-dlp, Render üzerinde (`server/`) |
| **Arayüz Bileşenleri** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Kurulum & Yükleme

### Ön Gereksinimler
- Flutter SDK (En Son Kararlı Sürüm)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Yükleme

1. **Depoyu klonlayın:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Bağımlılıkları yükleyin:**
   ```bash
   flutter pub get
   ```

3. **Uygulamayı çalıştırın:**
   ```bash
   flutter run
   ```

4. **Sürüm APK'sını derleyin** (daha küçük boyut için ABI'ye göre bölünmüş):
   ```bash
   flutter build apk --split-per-abi
   ```

> Bulut aktarıcı URL'si `lib/utils/api_constants.dart`
> (`relayBaseUrl`) dosyasına gömülüdür, dolayısıyla herhangi bir build bayrağı gerekmez. Kendi aktarıcınızı göstermek için:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend & Yayın Sunucuları

### ☁️ Bulut Akış Aktarıcısı — `server/` (Render'da dağıtıldı)
Bir YouTube ses URL'sini çözer **ve baytları aktarır**; böylece telefon ve çözümleyici aynı IP'yi paylaşır (403 yok). FastAPI + yt-dlp, Docker, ücretsiz katman.

| Endpoint | Açıklama |
| --- | --- |
| `GET /health` | Canlılık yoklaması (`ok`) |
| `GET /stream?videoId=X&key=K` | yt-dlp ile çözer → bir `…/relay` URL'si döndürür (yalnızca çözülürse 200) |
| `GET /relay?videoId=X&key=K` | Ses baytlarını proxy'ler (Range farkında → gezinme için 206) |

Ortak bir `RELAY_KEY` ortam değişkeni ile korunur (yoksa **401** döndürür). Dağıtım: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Bkz. `server/README.md`.

### 🎵 Uygulama API'si — `backend/`
Veri/arama backend'i (youtubei.js üzerinden YouTube Music + açık kaynaklar: Last.fm türleri,
MusicBrainz sürümleri ve on yılları).

| Endpoint | Açıklama |
| --- | --- |
| `/api/search` | Müzik / video araması |
| `/api/trending` | Trendler |
| `/api/charts` | YT Music listeleri |
| `/api/playlist/:id` | Liste ayrıntısı |
| `/api/moods`, `/api/moods/:id` | Kategoriler ve ruh halleri (Last.fm yedeği) |
| `/api/tags?tag=` | Tür bazında en iyi şarkılar/albümler (Last.fm) |
| `/api/newreleases` | Yeni sürümler (MusicBrainz) |
| `/api/decades?year=` | On yıllara göre albümler (MusicBrainz) |
| `/api/categories` | Kategori listesi |

**Yerel:** `cd backend && npm install && npm start` (port 8000).
**Dağıtım (Vercel):** bu depoyu içe aktarın, **Root Directory = `backend`**. Bkz. `backend/README.md`.

### 🗄️ Veritabanı — `supabase/`
**Satır Düzeyinde Güvenlik (Row-Level Security)** ile Postgres şeması: kullanıcı satırları `auth.uid()` ile sınırlıdır; katalog anonim kullanıcılar için salt okunur ve yalnızca service role tarafından yazılabilir. Migrasyonları Supabase SQL Editor'de (sırayla) çalıştırın.

---

## 🤝 Katkıda Bulunma

Katkılar hoŞ geldiniz! Bir hata bildirmek, bir özellik önermek ya da kod yazmak fark etmez, yardımınız takdir edilir.

1. **Projeyi Fork'layın**
2. **Özellik Branşınızı Oluşturun** (`git checkout -b feature/AmazingFeature`)
3. **Değişikliklerinizi Commit Edin** (`git commit -m 'Add some AmazingFeature'`)
4. **Branşa Push Edin** (`git push origin feature/AmazingFeature`)
5. **Bir Pull Request Açın**

**Kurallar:** mevcut kod stiline uyun, `flutter analyze` çalıştırın (temiz olmalı) ve göndermeden önce yeni özellikleri test edin.

---

## 🙏 Teşekkürler

Tunefy, bu geliştiricilerin ve projelerin inanılmaz çalışmaları olmadan var olmazdı.

### youtube_explode_dart
Tunefy'nin YouTube yayın omurgası olan [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart)'ın
orijinal yazarı **[Hexer10](https://github.com/Hexer10)**'a ve Tunefy'nin en son YouTube değişiklikleriyle
çalışmaya devam etmesini sağlayan güncel fork için **[anandnet](https://github.com/anandnet)**'e teşekkürler.

### Animesh (n-ce) — fast-saavn & ytify
Tunefy'nin üst verilerini besleyen açık JioSaavn API'si **[fast-saavn](https://github.com/n-ce/saavn)**'ın
(ve büyük bir ilham kaynağı olan **[ytify](https://github.com/n-ce/ytify)**'ın) yaratıcısı
**[Animesh (n-ce)](https://github.com/n-ce)**'e selamlar.

### Açık Kaynak Kütüphaneler
| Paket | Yazar / Bakımcılar |
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

## 📄 Lisans

**MIT Lisansı** altında dağıtılmıştır. Daha fazla bilgi için [`LICENSE`](LICENSE) dosyasına bakın.
