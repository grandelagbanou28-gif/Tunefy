<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>一个强大的、注重隐私的音乐客户端，使用Flutter构建。</strong><br/>
  无广告 · 离线 · AI DJ · 同步翻译歌词 · Liquid Glass UI · 15 个来源 · 无需帐户
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
  <a href="#-主要特点">特点</a>·
  <a href="#-本地化">语言</a> ·
  <a href="#-架构">建筑</a> ·
  <a href="#-设置和安装">设置</a> ·
  <a href="#-后端和流媒体服务器">服务器</a>
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
  <a href="README.tr.md">Türkçe</a> ·
  <b>中文（简体）</b>
</p>

---

Tunefy 是一款功能丰富、注重隐私的音乐客户端，使用 Flutter 构建。它流自
**15 多个开放式无钥匙源**，具有自动后备级联，因此轨道在其中一个上失败
提供者在下一个播放。它通过后台播放提供优质的无广告体验，
离线下载、同步**和翻译**歌词、**AI DJ**、网络广播、音乐会、
共享 Blend 播放列表、现代 Liquid Glass UI 和智能后台缓存 - 有或没有
一个帐户。

> [!NOTE]
> Tunefy 直接从此存储库分发（APK 版本）。 **不**可用
> 在 Google Play Store 上。

---

## 🚀 主要特点

### 🎨 Liquid Glass UI/UX
- **动态 Glassmorphic 主题** — 通过 `liquid_glass_easy` 实现深色和浅色模式的高级样式。灯光模式使用适合专辑封面的半透明白色色调。
- **自定义着色器和模糊** — 适应艺术品颜色的高性能磨砂玻璃面板和覆盖层。
- **对比感知元素** — 状态栏图标、控件、滑块和菜单自动反转以提高易读性。
- **大屏幕和桌面优化** - 响应式播放器布局（高达 1300 像素）、居中对话框以及桌面/平板电脑专用的顶部搜索栏。

### 🎧 沉浸式音频、歌词和卡拉 OK
- **逐字卡拉 OK** — 当艺术家唱歌时，单词会实时填充颜色 (60+ FPS)。
- **逐行同步扫描** — 渐进式扫描效果，具有活动行突出显示和平滑滚动。
- **翻译歌词** — 歌词会即时被机器翻译 (DeepL) 为您的应用程序语言。
- **Lofi 模式** — 将任何曲目变成 Lofi 氛围：减慢 0.9 倍、音调校正、原生混响。
- **均衡器和原生效果** — 具有后台播放和屏幕关闭音频的系统级均衡器。
- **多语言音频和质量控制** — 检测可用的音频语言并传输高/中/低质量。

### 🤖 AI DJ 和个性化
- **AI DJ 助理 (Gemini)** — 对话式 DJ，可以读取您的品味、构建智能播放列表并接受请求。
- **口味信号** — 每首曲目的口味评分可了解您的喜好并推动推荐。
- **Wrapped 和听力统计** — 您的年度回顾：顶级艺术家、情绪和听力胶囊。
- **智能缓存系统** — 音频+多分辨率图稿的异步后台缓存，可实现即时、零等待播放。

### 🌍 跨 15 个以上来源的发现
Tunefy 通过跨这些提供者的**自动回退级联**解决播放问题（无密钥 = 不需要 API 密钥）：

|来源 |类型 |笔记|
|---|---|---|
| **YouTube / YT 音乐** |视频/音频|主要，通过 youtube_explode + 内部 API |
| **Jamendo** |无钥匙|知识共享目录 |
| **Deezer** |无钥匙|目录+元数据|
| **Audius** |无钥匙|去中心化艺术家 |
| **JioSaavn** |开放API |快速元数据和搜索 |
| **Invidious** |无钥匙| YouTube 镜子（4 个）|
| **Piped** |开放API | YouTube镜子|
| **OpenVerse** |无钥匙| CC 图像/音频 *（新）* |
| **Wikimedia Commons** |无钥匙|开放媒体*（新）* |
| **Beatport** |无钥匙|电子/舞蹈*（新）* |
| **Dailymotion** |无钥匙|视频后备 *（新）* |
| **ccMixter** |无钥匙|混音文化 *（新）* |
| **Internet Archive** |无钥匙|历史音频 *（新）* |
| **Radio Browser** |无钥匙|网络广播电台 |
| **iTunes / MusicBrainz / Last.fm** |打开|元数据、图表、类型 |

- **云流中继** — 自托管中继解析并**代理来自播放器使用的同一 IP 的音频字节**，避免 IP 锁定的 Googlevideo 链接返回的 HTTP 403。参见[Servers](#-后端和流媒体服务器)。
- **Spotify 导入** — 粘贴任何公共 Spotify 播放列表 URL（或扫描 Spotify 代码）以导入曲目。
- **全局搜索** — 跨歌曲、视频、专辑、艺术家和播客进行一次搜索。
- **分享到播放** — 分享YouTube/YT Music 直接链接到Tunefy。

### 📻 广播、音乐会和视频
- **网络广播** — 数千个直播电台 (Radio Browser)。
- **音乐会** — 通过丰富的详细信息页面发现您附近的现场活动。
- **剪辑提要** — 社区和热门剪辑的垂直短视频提要。
- **视频播放器** — 带画布视频背景的完整视频播放。
- **DJ 混音** — 专用 DJ/混音发现和播放。

### 🤝 社交、混合和社区
- **Blend 播放列表** — 使用短加入代码创建共享播放列表（例如 `KORA-4821`）；任何拥有代码的人都可以收听并做出贡献，例如 Spotify Blend 链接。
- **社区源** — 搜索、流式传输和发现社区上传的曲目。
- **艺术家关注** — 关注艺术家/频道以跟踪他们。
- **智能队列和无限播放** — 具有智能清晰行为的自动队列。

### 🔐 隐私和帐户
- **无需帐户** — 收藏夹、播放列表和历史记录默认存储在本地。
- **匿名 + Google 登录** — 可选登录（匿名设备身份或通过 Supabase Auth 的 Google）进行云同步和配置文件。
- **离线下载** — 下载歌曲和视频以供离线收听。
- **深度链接** — 完整的自定义 URL 方案，可通过浏览器或共享链接打开/播放歌曲、艺术家、专辑和播放列表。
- **无广告且可靠** — 由开放中继（Last.fm、MusicBrainz、iTunes）支持的不间断聆听，以保证播放。

---

## 🌐 本地化

Tunefy 附带 14 种语言的**完整翻译**（加上自动系统语言）：

|语言 |代码|语言 |代码|
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

在**设置→语言**中设置语言（或保留**系统**以进行自动检测）。

---

## 🏗️ 架构

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

**播放可靠性。** 该应用程序从不依赖于单一提供商。它探测源
优先级联（本地中继 → 云中继 → 无钥匙后视镜 → 元数据/标题搜索），具有
跳过发生故障的源的断路器。 **云中继**解析流，然后
**通过自己的连接中继字节**，因此分辨率和播放共享一个 IP — 这是
如何避免 Googlevideo 链接上的 IP 锁定 403。

---

## 🛠️ 技术堆栈

|层 |技术 |
|---|---|
| **框架** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **状态管理** | [Riverpod](https://riverpod.dev/) |
| **音频引擎** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube 萃取** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart)（由[anandnet](https://github.com/anandnet)分叉）|
| **人工智能DJ** |谷歌Gemini (`gemini_service`) |
| **歌词** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + 自定义卡拉 OK 引擎 + DeepL 翻译 |
| **本地存储** | [Hive](https://docs.hivedb.dev/) |
| **云同步/验证** | Supabase（Postgres + RLS、匿名和 Google 登录）|
| **网络** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **流媒体中继** | FastAPI + yt-dlp 于 Render (`server/`) |
| **用户界面组件** | `liquid_glass_easy`、[FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons)、[Google Fonts](https://pub.dev/packages/google_fonts)、[Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ 设置和安装

### 先决条件
- Flutter SDK（最新稳定版）
- Dart SDK
- Android Studio / VS 代码
- JavaJDK 17

### 安装

1. **克隆存储库：**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **安装依赖项：**
   ```bash
   flutter pub get
   ```

3. **运行应用程序：**
   ```bash
   flutter run
   ```

4. **构建发布 APK**（按 ABI 分割以获得更小的尺寸）：
   ```bash
   flutter build apk --split-per-abi
   ```

> 云中继 URL 被烘焙到 `lib/utils/api_constants.dart`
> (`relayBaseUrl`)，因此不需要构建标志。指向你自己的继电器：
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ 后端和流媒体服务器

### ☁️ 云流中继 — `server/`（部署在 Render）
解析 YouTube 音频 URL **并中继字节**，以便手机和解析器共享一个 IP
（第 403 号）。 FastAPI + yt-dlp、Docker，免费套餐。

|端点 |描述 |
| --- | --- |
| `GET /health` |活性探针 (`ok`) |
| `GET /stream?videoId=X&key=K` |通过 yt-dlp 解析 → 返回 `…/relay` URL（仅当解析时为 200）|
| `GET /relay?videoId=X&key=K` |代理音频字节（范围感知 → 206 用于查找）|

由共享的 `RELAY_KEY` 环境变量保护（没有它则返回 **401**）。部署：Render→
**Root Directory = `server`**、Docker、**Health Check = `/health`**。参见`server/README.md`。

### 🎵 应用程序 API — `backend/`
数据/搜索后端（YouTube Music来自 youtubei.js + 开源：Last.fm流派，
MusicBrainz 版本和数十年）。

|端点 |描述 |
| --- | --- |
| `/api/search` |音乐/视频搜索|
| `/api/trending` |热门 |
| `/api/charts` | YT 音乐排行榜 |
| `/api/playlist/:id` |播放列表详细信息 |
| `/api/moods`、`/api/moods/:id` |类别和心情（Last.fm后备）|
| `/api/tags?tag=` |流派热门曲目/专辑 (Last.fm) |
| `/api/newreleases` |新发布（MusicBrainz）|
| `/api/decades?year=` |十年专辑 (MusicBrainz) |
| `/api/categories` |类别列表 |

**本地：** `cd backend && npm install && npm start`（端口 8000）。
**部署（Vercel）：**导入此存储库，**Root Directory = `backend`**。参见`backend/README.md`。

### 🗄️ 数据库 — `supabase/`
具有 **行级安全性** 的 Postgres 架构：用户行的范围为 `auth.uid()`，目录为
对于匿名用户来说是只读的，并且只能由服务角色写入。在 Supabase 中运行迁移
SQL 编辑器（按顺序）。

---

## 🤝 贡献

欢迎贡献！无论是报告错误、建议功能还是编写代码，我们都非常感谢您的帮助。

1. **分叉项目**
2. **创建您的功能分支** (`git checkout -b feature/AmazingFeature`)
3. **提交您的更改** (`git commit -m 'Add some AmazingFeature'`)
4. **推送到分支** (`git push origin feature/AmazingFeature`)
5. **打开拉取请求**

**指南：**遵循现有代码风格，运行`flutter analyze`（必须干净），并在提交前测试新功能。

---

## 🙏致谢

如果没有这些开发人员和项目的出色工作，Tunefy 就不会存在。

### youtube_explode_dart
感谢原作者**[Hexer10](https://github.com/Hexer10)**
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — Tunefy 的支柱
YouTube 流媒体 — 以及**[anandnet](https://github.com/anandnet)** 对于最新的分支
保持 Tunefy 使用最新的 YouTube 更改。

### Animesh (n-ce) — fast-saavn & ytify
向**[Animesh (n-ce)](https://github.com/n-ce)**，的创造者致敬
**[fast-saavn](https://github.com/n-ce/saavn)**（开放的 JioSaavn API 为 Tunefy 的元数据提供支持）
和**[ytify](https://github.com/n-ce/ytify)** （巨大的灵感来源）。

### 开源库
|套餐 |作者/维护者 |
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

## 📄 许可证

根据 **MIT 许可证** 分发。请参阅[`LICENSE`](LICENSE)了解更多信息。
