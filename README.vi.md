<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Một trình nghe nhạc mạnh mẽ, đề cao quyền riêng tư, được xây dựng bằng Flutter.</strong><br/>
  Không quảng cáo · Chạy ngoại tuyến · DJ AI · Lời bài hát đồng bộ & dịch · Giao diện Liquid Glass · 15 nguồn · Không cần tài khoản
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Phiên bản" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Nền tảng" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Ngôn ngữ" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Giấy phép" />
</p>

<p align="center">
  <a href="#-key-features">Tính năng</a> ·
  <a href="#-localisation">Ngôn ngữ</a> ·
  <a href="#-screenshots">Hình ảnh</a> ·
  <a href="#-architecture">Kiến trúc</a> ·
  <a href="#-setup--installation">Thiết lập</a> ·
  <a href="#-backend--streaming-servers">Máy chủ</a>
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
  <b>Tiếng Việt</b> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy là một ứng dụng nghe nhạc giàu tính năng, đề cao quyền riêng tư, được xây dựng bằng Flutter. Nó phát từ
**hơn 15 nguồn mở và không cần khóa** với một phân cấp dự phòng tự động, nên một bài không phát được ở nhà cung cấp này
sẽ phát ở nhà cung cấp tiếp theo. Nó mang lại trải nghiệm cao cấp không quảng cáo với phát nền,
tải xuống ngoại tuyến, lời bài hát đồng bộ **và đã dịch**, một **DJ AI**, radio internet, concert,
danh sách phát Blend chia sẻ, giao diện Liquid Glass hiện đại và hệ thống đệm nền thông minh — có hoặc không cần tài khoản.

> [!NOTE]
> Tunefy được phân phối trực tiếp từ kho lưu trữ này (các bản phát hành APK). Nó **không** có sẵn
> trên Google Play Store.

---

## 🚀 Tính năng chính

### 🎨 Giao diện & UX Liquid Glass
- **Chủ đề Glassmorphic động** — Giao diện cao cấp trong Chế độ Tối và Sáng qua `liquid_glass_easy`. Chế độ Sáng dùng sắc trắng bán trong suốt thích ứng với bìa album.
- **Shader & Hiệu ứng mờ tùy chỉnh** — Các bảng kính mờ hiệu năng cao và lớp phủ thích ứng với màu của tranh bìa.
- **Thành phần nhận biết độ tương phản** — Biểu tượng thanh trạng thái, điều khiển, thanh trượt và menu tự đảo màu để dễ đọc.
- **Tối ưu cho màn hình lớn & máy tính để bàn** — Bố cục trình phát đáp ứng (tới 1300px), hộp thoại căn giữa và thanh tìm kiếm riêng ở trên cùng cho máy tính/máy tính bảng.

### 🎧 Âm thanh nhập vai, Lời bài hát & Karaoke
- **Karaoke từng chữ** — Các từ được tô màu theo thời gian thực khi ca sĩ hát (trên 60 FPS).
- **Quét đồng bộ từng dòng** — Hiệu ứng quét tuần tiến, làm nổi bật dòng đang phát và cuộn mượt mà.
- **Lời bài hát đã dịch** — Lời bài hát được dịch máy (DeepL) sang ngôn ngữ của ứng dụng ngay khi phát.
- **Chế độ Lofi** — Biến mọi bài hát thành phong cách Lofi: chậm 0.9×, hiệu chỉnh cao độ, vang tự nhiên.
- **Bộ cân bằng & Hiệu ứng gốc** — Equalizer cấp hệ thống cùng phát nền và âm thanh khi tắt màn hình.
- **Đa ngôn ngữ âm thanh & Kiểm soát chất lượng** — Phát hiện các ngôn ngữ âm thanh có sẵn và phát ở chất lượng Cao/Trung bình/Thấp.

### 🤖 AI DJ & Cá nhân hóa
- **Trợ lý DJ AI (Gemini)** — Một DJ hội thoại hiểu gu của bạn, xây dựng danh sách phát thông minh và nhận yêu cầu.
- **Tín hiệu gu nghe** — Chấm điểm gu theo từng bài học hỏi những gì bạn yêu thích và thúc đẩy gợi ý.
- **Wrapped & Thống kê lượt nghe** — Điểm lại một năm của bạn: nghệ sĩ hàng đầu, tâm trạng và các gói tổng kết.
- **Hệ thống đệm thông minh** — Đệm âm thanh + hình bìa nhiều độ phân giải nền bất đồng bộ để phát tức thì, không chờ đợi.

### 🌍 Khám phá qua 15+ nguồn
Tunefy giải quyết việc phát nhạc thông qua một **phân cấp dự phòng tự động** qua các nhà cung cấp sau (không cần khóa = không cần khóa API):

| Nguồn | Loại | Ghi chú |
|---|---|---|
| **YouTube / YT Music** | Video / Âm thanh | Chính, qua youtube_explode + API nội bộ |
| **Jamendo** | Không cần khóa | Thư mục Creative Commons |
| **Deezer** | Không cần khóa | Thư mục + siêu dữ liệu |
| **Audius** | Không cần khóa | Nghệ sĩ phi tập trung |
| **JioSaavn** | API mở | Siêu dữ liệu & tìm kiếm nhanh |
| **Invidious** | Không cần khóa | Bản sao YouTube (4 instance) |
| **Piped** | API mở | Bản sao YouTube |
| **OpenVerse** | Không cần khóa | Ảnh/âm thanh CC *(mới)* |
| **Wikimedia Commons** | Không cần khóa | Phương tiện mở *(mới)* |
| **Beatport** | Không cần khóa | Nhạc điện tử/dance *(mới)* |
| **Dailymotion** | Không cần khóa | Dự phòng video *(mới)* |
| **ccMixter** | Không cần khóa | Văn hóa remix *(mới)* |
| **Internet Archive** | Không cần khóa | Âm thanh lịch sử *(mới)* |
| **Radio Browser** | Không cần khóa | Đài phát thanh internet |
| **iTunes / MusicBrainz / Last.fm** | Mở | Siêu dữ liệu, bảng xếp hạng, thể loại |

- **Relay luồng đám mây** — Một relay tự lưu trữ giải quyết và **ủy quyền chuyển tiếp các byte âm thanh** từ cùng IP mà trình phát sử dụng, tránh lỗi HTTP 403 mà các liên kết Googlevideo khóa IP thường trả về. Xem [Máy chủ](#-backend--streaming-servers).
- **Nhập từ Spotify** — Dán bất kỳ URL danh sách phát Spotify công khai nào (hoặc quét mã Spotify) để nhập bài hát.
- **Tìm kiếm toàn cục** — Một tìm kiếm duy nhất cho bài hát, video, album, nghệ sĩ và podcast.
- **Chia sẻ để phát** — Chia sẻ liên kết YouTube/YT Music thẳng vào Tunefy.

### 📻 Radio, Buổi hòa nhạc & Video
- **Radio internet** — Hàng nghìn đài phát trực tiếp (Radio Browser).
- **Buổi hòa nhạc** — Khám phá các sự kiện trực tiếp gần bạn với trang chi tiết phong phú.
- **Bảng tin Clip** — Dòng video ngắn dọc gồm các clip của cộng đồng và xu hướng.
- **Trình phát Video** — Phát video đầy đủ với nền video canvas.
- **DJ Mix** — Khám phá và phát riêng cho DJ/mix.

### 🤝 Xã hội, Blend & Cộng đồng
- **Danh sách phát Blend** — Tạo danh sách phát chung với mã tham gia ngắn (ví dụ `KORA-4821`); bất kỳ ai có mã đều có thể nghe và đóng góp, giống các liên kết Spotify Blend.
- **Bảng tin cộng đồng** — Tìm kiếm, phát và khám phá các bài hát do cộng đồng tải lên.
- **Theo dõi nghệ sĩ** — Theo dõi nghệ sĩ/kênh để cập nhật thông tin về họ.
- **Hàng đợi thông minh & Phát không giới hạn** — Tự động xếp hàng với cơ chế dọn hàng đợi thông minh.

### 🔐 Quyền riêng tư & Tài khoản
- **Không cần tài khoản** — Yêu thích, danh sách phát và lịch sử được lưu cục bộ theo mặc định.
- **Đăng nhập Ẩn danh + Google** — Tùy chọn đăng nhập (danh tính thiết bị ẩn danh hoặc Google qua Supabase Auth) để đồng bộ đám mây và hồ sơ.
- **Tải xuống ngoại tuyến** — Tải bài hát và video để nghe khi không có mạng.
- **Deep Linking** — Lớp scheme URL tùy chỉnh đầy đủ để mở/phát bài hát, nghệ sĩ, album và danh sách phát qua trình duyệt hoặc qua các liên kết chia sẻ.
- **Không quảng cáo & Ổn định** — Nghe không gián đoạn, được hỗ trợ bởi các relay mở (Last.fm, MusicBrainz, iTunes) để đảm bảo việc phát lại.

---

## 🌐 Bản địa hóa

Tunefy đi kèm **bản dịch đầy đủ** cho 14 ngôn ngữ (cộng thêm ngôn ngữ hệ thống tự động):

| Ngôn ngữ | Mã | Ngôn ngữ | Mã |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Đặt ngôn ngữ trong **Cài đặt → Ngôn ngữ** (hoặc giữ **Hệ thống** để tự động nhận diện).

---

## 📸 Hình ảnh màn hình

### 🏠 Trang chủ & Điều hướng
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Màn hình Trang chủ" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Trang chủ với Trình phát nhỏ" />
  <img src="images/library.jpg" width="30%" alt="Thư viện" />
</p>

### 🔍 Tìm kiếm
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Kết quả tìm kiếm" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Gợi ý tìm kiếm" />
</p>

### 🎵 Trình phát
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Trình phát nhập vai" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Trình phát cũ" />
  <img src="images/song_queue.jpg" width="30%" alt="Hàng đợi bài hát" />
</p>

### 🎤 Lời bài hát
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Lời bài hát với điều khiển" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Lời bài hát không điều khiển" />
</p>

### 👥 Cộng đồng & Hồ sơ
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Bảng tin Cộng đồng" />
  <img src="images/profile_screen.jpg" width="30%" alt="Màn hình Hồ sơ" />
</p>

### ⚙️ Cài đặt & Tùy chỉnh
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Cài đặt" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Bộ chọn Chủ đề" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Màu nhấn" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Màu nhấn Tùy chỉnh" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Bộ chọn Ngôn ngữ" />
</p>

### ℹ️ Giới thiệu
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Màn hình Giới thiệu" />
</p>

---

## 🏗️ Kiến trúc

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

**Độ ổn định khi phát lại.** Ứng dụng không bao giờ phụ thuộc vào một nhà cung cấp duy nhất. Nó dò các nguồn theo một phân cấp ưu tiên (relay cục bộ → relay đám mây → các bản sao không cần khóa → tìm kiếm theo siêu dữ liệu/tiêu đề), với một cầu chì tự động bỏ qua nguồn đang gặp sự cố. **Relay đám mây** giải quyết luồng phát rồi **chuyển tiếp các byte** qua kết nối riêng của nó, để việc giải quyết và phát lại dùng chung một IP — chính điều này tránh được lỗi 403 khóa IP trên các liên kết Googlevideo.

---

## 🛠️ Bộ công nghệ

| Tầng | Công nghệ |
|---|---|
| **Khung** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Quản lý trạng thái** | [Riverpod](https://riverpod.dev/) |
| **Engine âm thanh** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **Trích xuất YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork của [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Lời bài hát** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + engine karaoke tùy chỉnh + dịch DeepL |
| **Lưu trữ cục bộ** | [Hive](https://docs.hivedb.dev/) |
| **Đồng bộ đám mây / Xác thực** | Supabase (Postgres + RLS, đăng nhập ẩn danh & Google) |
| **Mạng** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relay luồng** | FastAPI + yt-dlp trên Render (`server/`) |
| **Thành phần giao diện** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Thiết lập & Cài đặt

### Yêu cầu tiên quyết
- Flutter SDK (Bản ổn định mới nhất)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Cài đặt

1. **Nhập mã nguồn về:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Cài đặt phụ thuộc:**
   ```bash
   flutter pub get
   ```

3. **Chạy ứng dụng:**
   ```bash
   flutter run
   ```

4. **Bản dựng APK phát hành** (tách theo ABI để dung lượng nhỏ hơn):
   ```bash
   flutter build apk --split-per-abi
   ```

> URL của relay đám mây được nhúng sẵn trong `lib/utils/api_constants.dart`
> (`relayBaseUrl`), nên không cần cờ build nào. Để trỏ tới relay của riêng bạn:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend & Máy chủ phát trực tuyến

### ☁️ Relay luồng đám mây — `server/` (triển khai trên Render)
Giải quyết một URL âm thanh YouTube **và chuyển tiếp các byte** để điện thoại và bộ giải quyết dùng chung một IP (không có lỗi 403). FastAPI + yt-dlp, Docker, gói miễn phí.

| Endpoint | Mô tả |
| --- | --- |
| `GET /health` | Kiểm tra còn sống (`ok`) |
| `GET /stream?videoId=X&key=K` | Giải quyết qua yt-dlp → trả về một URL `…/relay` (200 chỉ khi giải quyết thành công) |
| `GET /relay?videoId=X&key=K` | Ủy quyền chuyển tiếp các byte âm thanh (hỗ trợ Range → 206 khi tua) |

Được bảo vệ bằng biến môi trường dùng chung `RELAY_KEY` (trả về **401** nếu thiếu). Triển khai: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Xem `server/README.md`.

### 🎵 API ứng dụng — `backend/`
Backend dữ liệu/tìm kiếm (YouTube Music qua youtubei.js + các nguồn mở: thể loại Last.fm,
bản phát hành & thập kỷ MusicBrainz).

| Endpoint | Mô tả |
| --- | --- |
| `/api/search` | Tìm kiếm nhạc / video |
| `/api/trending` | Xu hướng |
| `/api/charts` | Bảng xếp hạng YT Music |
| `/api/playlist/:id` | Chi tiết danh sách phát |
| `/api/moods`, `/api/moods/:id` | Thể loại & tâm trạng (dự phòng Last.fm) |
| `/api/tags?tag=` | Bài hát/album hàng đầu theo thể loại (Last.fm) |
| `/api/newreleases` | Bản phát hành mới (MusicBrainz) |
| `/api/decades?year=` | Album theo thập kỷ (MusicBrainz) |
| `/api/categories` | Danh sách thể loại |

**Cục bộ:** `cd backend && npm install && npm start` (cổng 8000).
**Triển khai (Vercel):** nhập kho lưu trữ này về, **Root Directory = `backend`**. Xem `backend/README.md`.

### 🗄️ Cơ sở dữ liệu — `supabase/`
Lược đồ Postgres với **Bảo mật theo cấp hàng (Row-Level Security)**: các hàng người dùng được giới hạn theo `auth.uid()`, thư mục chỉ đọc với người dùng ẩn danh và chỉ ghi được bởi service role. Chạy các migration trong Supabase SQL Editor (theo đúng thứ tự).

---

## 🤝 Đóng góp

Chúng tôi hoan nghênh đóng góp! Dù là báo lỗi, đề xuất tính năng hay viết mã, sự giúp đỡ của bạn đều được trân trọng.

1. **Fork Dự án**
2. **Tạo nhánh Tính năng của bạn** (`git checkout -b feature/AmazingFeature`)
3. **Commit các thay đổi của bạn** (`git commit -m 'Add some AmazingFeature'`)
4. **Push lên nhánh** (`git push origin feature/AmazingFeature`)
5. **Mở một Pull Request**

**Nguyên tắc:** tuân theo phong cách mã hiện có, chạy `flutter analyze` (phải sạch) và kiểm thử các tính năng mới trước khi gửi.

---

## 🙏 Lời cảm ơn

Tunefy sẽ không tồn tại nếu không có những đóng góp tuyệt vời của các nhà phát triển và dự án này.

### youtube_explode_dart
Cảm ơn **[Hexer10](https://github.com/Hexer10)**, tác giả gốc của
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — xương sống cho luồng YouTube của Tunefy —
và **[anandnet](https://github.com/anandnet)** với phiên bản fork được cập nhật, giúp Tunefy hoạt động
với những thay đổi mới nhất của YouTube.

### Animesh (n-ce) — fast-saavn & ytify
Xin gửi lời cảm ơn tới **[Animesh (n-ce)](https://github.com/n-ce)**, tác giả của
**[fast-saavn](https://github.com/n-ce/saavn)** (API JioSaavn mở cung cấp siêu dữ liệu cho Tunefy)
và **[ytify](https://github.com/n-ce/ytify)** (một nguồn cảm hứng lớn).

### Thư viện nguồn mở
| Gói | Tác giả / Người duy trì |
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

## 📄 Giấy phép

Được phân phối theo **Giấy phép MIT**. Xem [`LICENSE`](LICENSE) để biết thêm thông tin.
