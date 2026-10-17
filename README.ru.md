<p align="center">
  <img src="assets/logo.png" alt="Логотип Tunefy" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Мощный музыкальный клиент с упором на приватность, построенный на Flutter.</strong><br/>
  Без рекламы · Оффлайн · AI DJ · Синхронные и переведённые тексты песен · Liquid Glass UI · 15 источников · Без регистрации
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Версия" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Платформа" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Языки" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Лицензия" />
</p>

<p align="center">
  <a href="#-key-features">Функции</a> ·
  <a href="#-localisation">Языки</a> ·
  <a href="#-screenshots">Скриншоты</a> ·
  <a href="#-architecture">Архитектура</a> ·
  <a href="#-setup--installation">Настройка</a> ·
  <a href="#-backend--streaming-servers">Серверы</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.fo.md">Fongbé</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt.md">Português</a> ·
  <a href="README.it.md">Italiano</a> ·
  <b>Русский</b> ·
  <a href="README.ar.md">العربية</a> ·
  <a href="README.hi.md">हिन्दी</a> ·
  <a href="README.id.md">Bahasa Indonesia</a> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy — это функциональный музыкальный клиент с упором на приватность, построенный на Flutter. Он стримит
**с 15+ открытых и не требующих ключа источников** с автоматической каскадной переброской, поэтому трек, не
запустившийся у одного провайдера, проигрывается у следующего. Он предлагает премиальный опыт без рекламы:
фоновое воспроизведение, оффлайн-загрузки, синхронные **и переведённые** тексты песен, **AI DJ**,
интернет-радио, концерты, общие плейлисты Blend, современный интерфейс Liquid Glass и умное фоновое
кеширование — с аккаунтом или без него.

> [!NOTE]
> Tunefy распространяется напрямую из этого репозитория (APK-релизы). Его **нет**
> в Google Play Store.

---

## 🚀 Основные возможности

### 🎨 Интерфейс Liquid Glass UI/UX
- **Динамические темы Glassmorphic** — Премиальное оформление в тёмной и светлой темах через `liquid_glass_easy`. Светлая тема использует полупрозрачный белый оттенок, адаптирующийся к обложке альбома.
- **Собственные шейдеры и размытие** — Высокопроизводительные матовые панели и оверлеи, адаптирующиеся к цветам обложки.
- **Элементы с учётом контраста** — Иконки строки состояния, элементы управления, ползунки и меню автоматически инвертируются для читаемости.
- **Оптимизация для больших экранов и десктопа** — Адаптивные макеты плеера (до 1300px), центрированные диалоги и отдельная строка поиска сверху для десктопа/планшета.

### 🎧 Иммерсивный звук, тексты песен и караоке
- **Караоке по словам** — Слова окрашиваются в реальном времени, пока артист поёт (60+ FPS).
- **Построчная синхронная заливка** — Последовательный эффект заливки с подсветкой активной строки и плавной прокруткой.
- **Переведённые тексты песен** — Тексты машинно переводятся (DeepL) на язык приложения.
- **Режим Lofi** — Превращает любой трек в Lofi-настроение: замедление 0,9×, коррекция высоты тона, нативная реверберация.
- **Эквалайзер и нативные эффекты** — Системный EQ с фоновым воспроизведением и звуком при выключенном экране.
- **Многоязычный звук и контроль качества** — Определяет доступные языки звуковой дорожки и стримит качество High/Medium/Low.

### 🤖 AI DJ и персонализация
- **AI DJ-ассистент (Gemini)** — Разговорный DJ, который понимает ваши вкусы, составляет умные плейлисты и выполняет запросы.
- **Сигналы вкуса** — Оценка вкуса для каждого трека обучается на ваших предпочтениях и управляет рекомендациями.
- **Wrapped и статистика прослушиваний** — Ваш итог года: лучшие артисты, настроения и «капсулы» прослушиваний.
- **Умная система кеша** — Асинхронное фоновое кеширование звука и обложек в нескольких разрешениях для мгновенного воспроизведения без ожидания.

### 🌍 Поиск среди 15+ источников
Tunefy определяет источник воспроизведения через **автоматическую каскадную переброску** среди этих провайдеров (keyless = без API-ключа):

| Источник | Тип | Примечания |
|---|---|---|
| **YouTube / YT Music** | Video / Audio | Основной, через youtube_explode + внутренний API |
| **Jamendo** | Keyless | Каталог Creative Commons |
| **Deezer** | Keyless | Каталог + метаданные |
| **Audius** | Keyless | Децентрализованные артисты |
| **JioSaavn** | Open API | Быстрые метаданные и поиск |
| **Invidious** | Keyless | Зеркало YouTube (4 инстанции) |
| **Piped** | Open API | Зеркало YouTube |
| **OpenVerse** | Keyless | CC-изображения/аудио *(новое)* |
| **Wikimedia Commons** | Keyless | Открытые медиа *(новое)* |
| **Beatport** | Keyless | Электронная/танцевальная музыка *(новое)* |
| **Dailymotion** | Keyless | Видео-фоллбэк *(новое)* |
| **ccMixter** | Keyless | Культура ремиксов *(новое)* |
| **Internet Archive** | Keyless | Историческое аудио *(новое)* |
| **Radio Browser** | Keyless | Интернет-радиостанции |
| **iTunes / MusicBrainz / Last.fm** | Open | Метаданные, чарты, жанры |

- **Cloud Stream Relay** — Самостоятельно размещённый резолвер разбирает ссылку и **проксирует байты аудио** с того же IP, что использует плеер, избегая ошибки HTTP 403, которую возвращают привязанные к IP ссылки Googlevideo. См. [Серверы](#-backend--streaming-servers).
- **Импорт из Spotify** — Вставьте URL любого открытого плейлиста Spotify (или отсканируйте код Spotify), чтобы импортировать треки.
- **Глобальный поиск** — Один поиск по песням, видео, альбомам, артистам и подкастам.
- **Шаринг для воспроизведения** — Отправляйте ссылки YouTube/YT Music прямо в Tunefy.

### 📻 Радио, концерты и видео
- **Интернет-радио** — Тысячи прямых эфиров (Radio Browser).
- **Концерты** — Находите живые события рядом с вами с подробными страницами.
- **Лента клипов** — Вертикальная лента коротких видео сообщества и трендов.
- **Видеоплеер** — Полноценное воспроизведение видео с фоном на основе canvas.
- **DJ-миксы** — Отдельный поиск и воспроизведение DJ-миксов.

### 🤝 Общение, Blend и сообщество
- **Плейлисты Blend** — Создайте общий плейлист с коротким кодом входа (например, `KORA-4821`); любой с этим кодом может слушать и вносить вклад, как в ссылках Spotify Blend.
- **Лента сообщества** — Ищите, стримите и находите треки, загруженные сообществом.
- **Подписка на артистов** — Подписывайтесь на артистов и каналы, чтобы следить за ними.
- **Умная очередь и бесконечное воспроизведение** — Автоматическая постановка в очередь с умной логикой очистки.

### 🔐 Приватность и аккаунты
- **Аккаунт не требуется** — Избранное, плейлисты и история по умолчанию хранятся локально.
- **Анонимный вход + Google** — Необязательный вход (анонимный идентификатор устройства или Google через Supabase Auth) для облачной синхронизации и профиля.
- **Оффлайн-загрузки** — Загружайте песни и видео для прослушивания без сети.
- **Deep Linking** — Полноценная собственная URL-схема для открытия и воспроизведения песен, артистов, альбомов и плейлистов через браузер или общие ссылки.
- **Без рекламы и надёжно** — Непрерывное прослушивание с поддержкой открытых релеев (Last.fm, MusicBrainz, iTunes) для гарантированного воспроизведения.

---

## 🌐 Локализация

Tunefy поставляется с **полными переводами** на 14 языков (плюс автоматический язык системы):

| Язык | Код | Язык | Код |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Выберите язык в **Настройки → Язык** (или оставьте **Система** для автоматического определения).

---

## 📸 Скриншоты

### 🏠 Главная и навигация
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Главный экран" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Главная с мини-плеером" />
  <img src="images/library.jpg" width="30%" alt="Медиатека" />
</p>

### 🔍 Поиск
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Результаты поиска" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Подсказки поиска" />
</p>

### 🎵 Плеер
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Иммерсивный плеер" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Классический плеер" />
  <img src="images/song_queue.jpg" width="30%" alt="Очередь песен" />
</p>

### 🎤 Тексты песен
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Тексты с элементами управления" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Тексты без элементов управления" />
</p>

### 👥 Сообщество и профиль
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Лента сообщества" />
  <img src="images/profile_screen.jpg" width="30%" alt="Экран профиля" />
</p>

### ⚙️ Настройки и кастомизация
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Настройки" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Выбор темы" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Акцентный цвет" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Свой акцентный цвет" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Выбор языка" />
</p>

### ℹ️ О приложении
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Экран «О приложении»" />
</p>

---

## 🏗️ Архитектура

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

**Надёжность воспроизведения.** Приложение никогда не зависит от одного провайдера. Оно опрашивает источники в
каскаде приоритетов (локальный релей → облачный релей → зеркала без ключа → поиск по метаданным и названию),
а автоматический выключатель пропускает сбойный источник. **Облачный релей** разрешает стрим и затем
**проксирует байты** через собственное соединение, поэтому разрешение и воспроизведение делят один IP — именно
это исключает привязку по IP и ошибку 403 на ссылках Googlevideo.

---

## 🛠️ Стек технологий

| Слой | Технология |
|---|---|
| **Фреймворк** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Управление состоянием** | [Riverpod](https://riverpod.dev/) |
| **Аудио-движок** | [Just Audio](https://pub.dev/packages/just_audio) и [Audio Service](https://pub.dev/packages/audio_service) |
| **Извлечение YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork от [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Тексты песен** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + собственный караоке-движок + перевод DeepL |
| **Локальное хранилище** | [Hive](https://docs.hivedb.dev/) |
| **Облачная синхронизация / Auth** | Supabase (Postgres + RLS, анонимный вход и вход через Google) |
| **Сетевое взаимодействие** | [Dio](https://pub.dev/packages/dio) и [Http](https://pub.dev/packages/http) |
| **Релеи стримов** | FastAPI + yt-dlp на Render (`server/`) |
| **UI-компоненты** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Настройка и установка

### Предварительные требования
- Flutter SDK (последняя стабильная версия)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Установка

1. **Клонируйте репозиторий:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Установите зависимости:**
   ```bash
   flutter pub get
   ```

3. **Запустите приложение:**
   ```bash
   flutter run
   ```

4. **Соберите release APK** (с разделением по ABI для уменьшения размера):
   ```bash
   flutter build apk --split-per-abi
   ```

> URL облачного релея зашит в `lib/utils/api_constants.dart`
> (`relayBaseUrl`), поэтому флаг сборки не нужен. Чтобы указать собственный релей:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend и серверы стриминга

### ☁️ Cloud Stream Relay — `server/` (deployed on Render)
Разрешает URL аудио YouTube **и проксирует байты**, чтобы телефон и резолвер делили один IP
(без 403). FastAPI + yt-dlp, Docker, бесплатный тариф.

| Endpoint | Описание |
| --- | --- |
| `GET /health` | Проверка живости (`ok`) |
| `GET /stream?videoId=X&key=K` | Разрешается через yt-dlp → возвращает URL `…/relay` (только 200, если разрешение успешно) |
| `GET /relay?videoId=X&key=K` | Проксирует байты аудио (учитывает Range → 206 для перемотки) |

Защита общей переменной окружения `RELAY_KEY` (без неё возвращается **401**). Деплой: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. См. `server/README.md`.

### 🎵 API приложения — `backend/`
Бэкенд данных и поиска (YouTube Music через youtubei.js + открытые источники: жанры Last.fm,
релизы и десятилетия MusicBrainz).

| Endpoint | Описание |
| --- | --- |
| `/api/search` | Поиск музыки/видео |
| `/api/trending` | Тренды |
| `/api/charts` | Чарты YT Music |
| `/api/playlist/:id` | Детали плейлиста |
| `/api/moods`, `/api/moods/:id` | Категории и настроения (фоллбэк Last.fm) |
| `/api/tags?tag=` | Топ треков/альбомов по жанру (Last.fm) |
| `/api/newreleases` | Новые релизы (MusicBrainz) |
| `/api/decades?year=` | Альбомы по десятилетиям (MusicBrainz) |
| `/api/categories` | Список категорий |

**Локально:** `cd backend && npm install && npm start` (порт 8000).
**Деплой (Vercel):** импортируйте этот репозиторий, **Root Directory = `backend`**. См. `backend/README.md`.

### 🗄️ База данных — `supabase/`
Схема Postgres с **Row-Level Security**: строки пользователей ограничены `auth.uid()`, каталог доступен
анонимным пользователям только для чтения, а запись доступна лишь сервисной роли. Запускайте миграции в
Supabase SQL Editor (по порядку).

---

## 🤝 Участие в развитии

Будем рады вашему вкладу! Неважно, сообщите вы об ошибке, предложите функцию или напишете код — ваша помощь будет ценной.

1. **Сделайте форк проекта**
2. **Создайте ветку фичи** (`git checkout -b feature/AmazingFeature`)
3. **Зафиксируйте изменения** (`git commit -m 'Add some AmazingFeature'`)
4. **Отправьте в ветку** (`git push origin feature/AmazingFeature`)
5. **Откройте Pull Request**

**Рекомендации:** следуйте существующему стилю кода, запускайте `flutter analyze` (он должен быть чистым) и тестируйте новые функции перед отправкой.

---

## 🙏 Благодарности

Tunefy не существовал бы без потрясающей работы этих разработчиков и проектов.

### youtube_explode_dart
Спасибо **[Hexer10](https://github.com/Hexer10)**, первоначальному автору
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — основе
YouTube-стриминга Tunefy — и **[anandnet](https://github.com/anandnet)** за актуальный fork,
который поддерживает работу Tunefy с последними изменениями YouTube.

### Animesh (n-ce) — fast-saavn & ytify
Отдельная благодарность **[Animesh (n-ce)](https://github.com/n-ce)**, создателю
**[fast-saavn](https://github.com/n-ce/saavn)** (открытого JioSaavn API, питающего метаданные Tunefy)
и **[ytify](https://github.com/n-ce/ytify)** (огромного источника вдохновения).

### Библиотеки с открытым исходным кодом
| Пакет | Автор / мейнтейнеры |
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

## 📄 Лицензия

Распространяется по **MIT License**. Подробности см. в [`LICENSE`](LICENSE).
