<p align="center">
  <img src="assets/logo.png" alt="Tunefy 标志" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>一款基于 Flutter 打造的强大的、注重隐私的音乐客户端。</strong><br/>
  无广告 · 离线 · AI DJ · 同步与翻译歌词 · Liquid Glass UI · 15 个音源 · 无需账号
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="版本" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="平台" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="语言" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="许可证" />
</p>

<p align="center">
  <a href="#-key-features">功能</a> ·
  <a href="#-localisation">语言</a> ·
  <a href="#-screenshots">截图</a> ·
  <a href="#-architecture">架构</a> ·
  <a href="#-setup--installation">安装</a> ·
  <a href="#-backend--streaming-servers">服务器</a>
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

Tunefy 是一款功能丰富、注重隐私的基于 Flutter 打造的音乐客户端。它从
**15 个以上开放且无需密钥的音源**进行串流，并带有自动回退级联——当某个音源播放失败时，
会自动切换到下一个。它提供高级的无广告体验，支持后台播放、离线下载、同步
**且翻译**的歌词、**AI DJ**、网络电台、演唱会、共享 Blend 歌单、现代 Liquid Glass
界面以及智能后台缓存——无论是否拥有账号均可使用。

> [!NOTE]
> Tunefy 直接从本仓库分发（APK 版本）。它**并未**上架
> Google Play Store。

---

## 🚀 核心功能

### 🎨 Liquid Glass UI/UX
- **动态玻璃拟态主题** — 通过 `liquid_glass_easy` 在深色与浅色模式下呈现高级质感。浅色模式使用半透明白色调，会随专辑封面自适应。
- **自定义着色器与模糊** — 高性能磨砂玻璃面板与覆盖层，颜色随封面自动适配。
- **对比度感知元素** — 状态栏图标、控件、滑块和菜单会自动反色以保证清晰可读。
- **大屏与桌面优化** — 响应式播放器布局（最大 1300px）、居中对话框，以及为桌面/平板准备的顶部搜索栏。

### 🎧 沉浸式音频、歌词与卡拉 OK
- **逐词卡拉 OK** — 歌词随歌手演唱实时逐词填色（60+ FPS）。
- **逐行同步扫描** — 渐进式扫描效果，高亮当前行并平滑滚动。
- **翻译歌词** — 歌词会实时机器翻译（DeepL）为应用语言。
- **Lofi 模式** — 将任意歌曲变成 Lofi 氛围：0.9× 减速、音高修正、原生混响。
- **均衡器与原生音效** — 系统级均衡器，支持后台播放与息屏发声。
- **多语言音轨与音质控制** — 检测可用的音轨语言，可串流高/中/低音质。

### 🤖 AI DJ 与个性化
- **AI DJ 助手（Gemini）** — 会对话的 DJ，能读懂你的口味、打造智能歌单并接受点歌。
- **口味信号** — 每首歌曲的口味评分会学习你的喜好并驱动推荐。
- **Wrapped 与收听统计** — 你的年度回顾：最喜爱的艺人、心情与收听胶囊。
- **智能缓存系统** — 在后台异步缓存音频与多分辨率封面，实现零等待即时播放。

### 🌍 跨越 15+ 音源的发现
Tunefy 通过**自动回退级联**在以下提供商之间解析播放（keyless = 无需 API 密钥）：

| 音源 | 类型 | 说明 |
|---|---|---|
| **YouTube / YT Music** | Video / Audio | 主要，通过 youtube_explode + 内部 API |
| **Jamendo** | Keyless | Creative Commons 目录 |
| **Deezer** | Keyless | 目录 + 元数据 |
| **Audius** | Keyless | 去中心化艺人 |
| **JioSaavn** | Open API | 快速元数据与搜索 |
| **Invidious** | Keyless | YouTube 镜像（4 个实例） |
| **Piped** | Open API | YouTube 镜像 |
| **OpenVerse** | Keyless | CC 图片/音频 *（新）* |
| **Wikimedia Commons** | Keyless | 开放媒体 *（新）* |
| **Beatport** | Keyless | 电子/舞曲 *（新）* |
| **Dailymotion** | Keyless | 视频回退 *（新）* |
| **ccMixter** | Keyless | 混音文化 *（新）* |
| **Internet Archive** | Keyless | 历史音频 *（新）* |
| **Radio Browser** | Keyless | 网络电台 |
| **iTunes / MusicBrainz / Last.fm** | Open | 元数据、榜单、流派 |

- **Cloud Stream Relay** — 自托管的中继会通过播放器所用的同一 IP 解析并**中继音频字节**，从而避免 IP 锁定的 Googlevideo 链接返回的 HTTP 403。参见[服务器](#-backend--streaming-servers)。
- **Spotify 导入** — 粘贴任意公开的 Spotify 歌单 URL（或扫描 Spotify 码）即可导入歌曲。
- **全局搜索** — 一次搜索涵盖歌曲、视频、专辑、艺人和播客。
- **分享即播放** — 将 YouTube/YT Music 链接直接分享到 Tunefy。

### 📻 电台、演唱会与视频
- **网络电台** — 数千个直播电台（Radio Browser）。
- **演唱会** — 发现你附近的现场活动，页面信息丰富。
- **短视频流** — 社区与热门剪辑的竖屏短视频流。
- **视频播放器** — 完整的视频播放，支持 canvas 视频背景。
- **DJ 混音** — 专门的 DJ/混音发现与播放。

### 🤝 社交、Blend 与社区
- **Blend 歌单** — 创建共享歌单并生成简短的加入码（例如 `KORA-4821`）；任何拥有该码的人都可以收听和贡献，类似 Spotify Blend 链接。
- **社区动态** — 搜索、串流并发现社区上传的歌曲。
- **关注艺人** — 关注艺人/频道以跟踪他们的动态。
- **智能队列与无限播放** — 自动排队，具备智能清空逻辑。

### 🔐 隐私与账号
- **无需账号** — 收藏、歌单和历史记录默认存储在本地。
- **匿名 + Google 登录** — 可选登录（匿名设备身份，或通过 Supabase Auth 使用 Google），用于云端同步和个人资料。
- **离线下载** — 下载歌曲和视频以便离线收听。
- **深度链接** — 完整的自定义 URL scheme，可通过浏览器或分享链接打开/播放歌曲、艺人、专辑和歌单。
- **无广告且可靠** — 由开放中继（Last.fm、MusicBrainz、iTunes）保障的不间断收听，确保正常播放。

---

## 🌐 本地化

Tunefy 内置 **14 种语言的完整翻译**（外加自动跟随系统语言）：

| 语言 | 代码 | 语言 | 代码 |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

在**设置 → 语言**中设置语言（或保持**系统**以进行自动检测）。

---

## 📸 截图

### 🏠 首页与导航
<p align="center">
  <img src="images/home.jpg" width="30%" alt="首页" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="带迷你播放器的首页" />
  <img src="images/library.jpg" width="30%" alt="资料库" />
</p>

### 🔍 搜索
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="搜索结果" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="搜索建议" />
</p>

### 🎵 播放器
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="沉浸式播放器" />
  <img src="images/leagcy_player.jpg" width="30%" alt="经典播放器" />
  <img src="images/song_queue.jpg" width="30%" alt="播放队列" />
</p>

### 🎤 歌词
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="带控件的歌词" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="无控件的歌词" />
</p>

### 👥 社区与个人资料
<p align="center">
  <img src="images/community.jpg" width="30%" alt="社区动态" />
  <img src="images/profile_screen.jpg" width="30%" alt="个人资料页面" />
</p>

### ⚙️ 设置与自定义
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="设置" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="主题选择器" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="强调色" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="自定义强调色" />
  <img src="images/app_language_selector.jpg" width="30%" alt="语言选择器" />
</p>

### ℹ️ 关于
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="关于页面" />
</p>

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

**播放可靠性。** 本应用从不依赖单一提供商。它按优先级级联探测音源（本地中继 → 云端中继 → 无需密钥的镜像 → 元数据/标题搜索），并带有熔断机制，会跳过发生故障的音源。**云端中继**先解析串流，然后通过自身连接**中继字节数据**，使解析与播放共享同一个 IP——这正是避免 Googlevideo 链接 IP 锁定 403 的关键。

---

## 🛠️ 技术栈

| 层级 | 技术 |
|---|---|
| **框架** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **状态管理** | [Riverpod](https://riverpod.dev/) |
| **音频引擎** | [Just Audio](https://pub.dev/packages/just_audio) 和 [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube 解析** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart)（由 [anandnet](https://github.com/anandnet) 维护的 fork） |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **歌词** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + 自研卡拉 OK 引擎 + DeepL 翻译 |
| **本地存储** | [Hive](https://docs.hivedb.dev/) |
| **云端同步 / 认证** | Supabase（Postgres + RLS，匿名登录与 Google 登录） |
| **网络** | [Dio](https://pub.dev/packages/dio) 和 [Http](https://pub.dev/packages/http) |
| **串流中继** | FastAPI + yt-dlp，部署在 Render（`server/`） |
| **UI 组件** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ 安装与配置

### 前置要求
- Flutter SDK（最新稳定版）
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### 安装

1. **克隆仓库：**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **安装依赖：**
   ```bash
   flutter pub get
   ```

3. **运行应用：**
   ```bash
   flutter run
   ```

4. **构建 release APK**（按 ABI 拆分以减小体积）：
   ```bash
   flutter build apk --split-per-abi
   ```

> 云端中继 URL 已内置于 `lib/utils/api_constants.dart`
> （`relayBaseUrl`），因此无需构建标志。若要指向你自己的中继：
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`。

---

## 🖥️ 后端与串流服务器

### ☁️ Cloud Stream Relay — `server/`（deployed on Render）
解析 YouTube 音频 URL **并中继字节数据**，使手机与解析端共享同一个 IP
（不会出现 403）。FastAPI + yt-dlp，Docker，免费套餐。

| 端点 | 说明 |
| --- | --- |
| `GET /health` | 存活探针（`ok`） |
| `GET /stream?videoId=X&key=K` | 通过 yt-dlp 解析 → 返回 `…/relay` URL（仅在解析成功时返回 200） |
| `GET /relay?videoId=X&key=K` | 中继音频字节（支持 Range → 拖动时返回 206） |

通过共享的 `RELAY_KEY` 环境变量保护（缺失时返回 **401**）。部署：Render →
**Root Directory = `server`**，Docker，**Health Check = `/health`**。参见 `server/README.md`。

### 🎵 应用 API — `backend/`
数据/搜索后端（通过 youtubei.js 的 YouTube Music + 开放数据源：Last.fm 流派、
MusicBrainz 发行版与年代）。

| 端点 | 说明 |
| --- | --- |
| `/api/search` | 音乐/视频搜索 |
| `/api/trending` | 热门趋势 |
| `/api/charts` | YT Music 榜单 |
| `/api/playlist/:id` | 歌单详情 |
| `/api/moods`, `/api/moods/:id` | 分类与心情（Last.fm 回退） |
| `/api/tags?tag=` | 按流派的热门歌曲/专辑（Last.fm） |
| `/api/newreleases` | 新发行（MusicBrainz） |
| `/api/decades?year=` | 按年代的专辑（MusicBrainz） |
| `/api/categories` | 分类列表 |

**本地：** `cd backend && npm install && npm start`（端口 8000）。
**部署（Vercel）：** 导入本仓库，**Root Directory = `backend`**。参见 `backend/README.md`。

### 🗄️ 数据库 — `supabase/`
Postgres 架构，具备 **Row-Level Security**：用户行限定为 `auth.uid()`，目录对匿名用户只读、仅服务角色可写。请在 Supabase SQL Editor 中（按顺序）运行迁移。

---

## 🤝 贡献

欢迎任何形式的贡献！无论是报告错误、建议功能还是编写代码，你的帮助都会受到感谢。

1. **Fork 本项目**
2. **创建你的功能分支** (`git checkout -b feature/AmazingFeature`)
3. **提交你的更改** (`git commit -m 'Add some AmazingFeature'`)
4. **推送到该分支** (`git push origin feature/AmazingFeature`)
5. **发起 Pull Request**

**指南：** 遵循现有代码风格，运行 `flutter analyze`（必须无警告），并在提交前测试新功能。

---

## 🙏 致谢

没有这些开发者和项目的出色工作，Tunefy 不会存在。

### youtube_explode_dart
感谢 **[Hexer10](https://github.com/Hexer10)**，[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) 的原作者——Tunefy YouTube 串流的基石——以及 **[anandnet](https://github.com/anandnet)**，其及时更新的 fork 让 Tunefy 能够跟上 YouTube 的最新变化。

### Animesh (n-ce) — fast-saavn & ytify
特别致谢 **[Animesh (n-ce)](https://github.com/n-ce)**，**[fast-saavn](https://github.com/n-ce/saavn)**（为 Tunefy 元数据提供支持的开放 JioSaavn API）和 **[ytify](https://github.com/n-ce/ytify)**（巨大的灵感来源）的创造者。

### 开源库
| 包 | 作者 / 维护者 |
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

基于 **MIT License** 分发。详见 [`LICENSE`](LICENSE)。
