<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>Мощный музыкальный клиент, ориентированный на конфиденциальность, созданный на основе Flutter.</strong><br/>
  Без рекламы · Офлайн · AI DJ · Синхронизированные и переведенные тексты · Liquid Glass Пользовательский интерфейс · 15 источников · Учетная запись не требуется
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
  <a href="#-ключевые-особенности">Особенности</a> ·
  <a href="#-локализация">Языки</a> ·
  <a href="#-архитектура">Архитектура</a> ·
  <a href="#-настройка-и-установка">Настройка</a> ·
  <a href="#-бэкэнд-и-потоковые-серверы">Серверы</a>
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

Tunefy — это многофункциональный музыкальный клиент, ориентированный на конфиденциальность, созданный на основе Flutter. Он льется из
**более 15 открытых и бесключевых источников** с автоматическим резервным каскадом, поэтому трек, который выходит из строя на одном
провайдер играет на следующем. Он предлагает премиум-класс без рекламы и фоновое воспроизведение.
офлайн-загрузка, синхронизированные **и переведенные** тексты песен, **AI DJ**, интернет-радио, концерты,
общие плейлисты Blend, современный пользовательский интерфейс Liquid Glass и интеллектуальное фоновое кэширование — с или без
счет.

> [!NOTE]
> Tunefy распространяется непосредственно из этого репозитория (APK-релизы). Это **не** доступно
> на Google Play Store.

---

## 🚀 Ключевые особенности

### 🎨 Liquid Glass UI/UX
- **Динамические темы Glassmorphic** — Премиум-стиль в темном и светлом режимах с помощью `liquid_glass_easy`. В светлом режиме используется полупрозрачный белый оттенок, который адаптируется к обложке альбома.
- **Пользовательские шейдеры и размытие** — высокопроизводительные панели и накладки из матового стекла, которые адаптируются к цветам произведения искусства.
- **Элементы с учетом контрастности** — значки строки состояния, элементы управления, ползунки и меню автоматически инвертируются для удобства чтения.
- **Оптимизация большого экрана и рабочего стола** — адаптивный макет проигрывателя (до 1300 пикселей), центрированные диалоговые окна и специальная верхняя панель поиска для настольных компьютеров и планшетов.

### 🎧 Иммерсивный звук, тексты песен и караоке
- **Пословное караоке** — слова окрашиваются в реальном времени во время пения исполнителя (60+ кадров в секунду).
- **Построчная синхронизированная развертка** — эффект прогрессивной развертки с выделением активной строки и плавной прокруткой.
- **Переведенные тексты песен** — тексты песен автоматически переводятся (DeepL) на язык вашего приложения «на лету».
- **Режим Lofi** — превратите любой трек в атмосферу Lofi: замедление 0,9×, коррекция высоты тона, встроенная реверберация.
- **Эквалайзер и встроенные эффекты** — эквалайзер системного уровня с фоновым воспроизведением и звуком при выключенном экране.
- **Многоязычное аудио и контроль качества** — определение доступных языков аудио и потоковая передача высокого/среднего/низкого качества.

### 🤖 AI-диджей и персонализация
- **AI DJ Assistant (Gemini)** — разговорный диджей, который читает ваши вкусы, создает умные плейлисты и принимает запросы.
- **Вкусовые сигналы**. Оценка вкуса каждого трека определяет, что вам нравится, и дает рекомендации.
- **Wrapped и статистика прослушивания** — ваш отчет за год: лучшие исполнители, настроения и капсулы для прослушивания.
- **Интеллектуальная система кэширования** — асинхронное фоновое кэширование аудио + графических изображений с разными разрешениями для мгновенного воспроизведения без ожидания.

### 🌍 Открытие в более чем 15 источниках
Tunefy разрешает воспроизведение посредством **автоматического резервного каскада** между этими поставщиками (без ключа = ключ API не требуется):

| Источник | Тип | Заметки |
|---|---|---|
| **YouTube / YT Music** | Видео/Аудио | Первично, через youtube_explode + внутренний API |
| **Jamendo** | Без ключа | Каталог Creative-Commons |
| **Deezer** | Без ключа | Каталог + метаданные |
| **Audius** | Без ключа | Децентрализованные художники |
| **ДжиоСаавн** | Открытый API | Быстрый метаданные и поиск |
| **Invidious** | Без ключа | YouTube зеркало (4 экземпляра) |
| **Piped** | Открытый API | YouTube зеркало |
| **OpenVerse** | Без ключа | Изображения/аудио CC *(новое)* |
| **Wikimedia Commons** | Без ключа | Открытые СМИ *(новое)* |
| **Beatport** | Без ключа | Электронная/танцевальная *(новая)* |
| **Dailymotion** | Без ключа | Резервное видео *(новое)* |
| **ccMixter** | Без ключа | Культура ремиксов *(новое)* |
| **Internet Archive** | Без ключа | Историческое аудио *(новое)* |
| **Radio Browser** | Без ключа | Интернет-радиостанции |
| **iTunes / MusicBrainz / Last.fm** | Открыть | Метаданные, диаграммы, жанры |

- **Cloud Stream Relay** — автономный ретранслятор разрешает и **проксирует аудиобайты** с того же IP-адреса, который использует плеер, избегая HTTP 403, который в противном случае возвращают ссылки Googlevideo с блокировкой IP. См. [Servers](#-бэкэнд-и-потоковые-серверы).
- **Spotify Импорт** — вставьте любой общедоступный URL-адрес плейлиста Spotify (или отсканируйте код Spotify), чтобы импортировать треки.
- **Глобальный поиск** — единый поиск по песням, видео, альбомам, исполнителям и подкастам.
- **Поделиться для воспроизведения** — Поделитесь ссылкой на YouTube/YT Music прямо в Tunefy.

### 📻 Радио, концерты и видео
- **Интернет-радио** — тысячи радиостанций в прямом эфире (Radio Browser).
- **Концерты**. Откройте для себя живые события рядом с вами на страницах с подробной информацией.
- **Лента клипов** — вертикальная лента коротких видеороликов сообщества и популярных клипов.
- **Видеоплеер** — Полное воспроизведение видео с фоновым видео на холсте.
- **DJ-миксы** — специальное обнаружение и воспроизведение DJ/миксов.

### 🤝 Социальные сети, смеси и сообщество
- **Blend Плейлисты** — создайте общий плейлист с коротким кодом присоединения (например, `KORA-4821`); любой, у кого есть код, может слушать и вносить свой вклад, например ссылки Spotify Blend.
- **Лента сообщества** — ищите, транслируйте и находите треки, загруженные сообществом.
- **Подписка на исполнителя** — подписывайтесь на исполнителей/каналы, чтобы следить за ними.
- **Умная очередь и бесконечное воспроизведение** — автоматическая постановка в очередь с интеллектуальным четким поведением.

### 🔐 Конфиденциальность и учетные записи
- **Учетная запись не требуется** — Избранное, плейлисты и история по умолчанию сохраняются локально.
- **Анонимный вход + вход в Google** — дополнительный вход (анонимный идентификатор устройства или Google через Supabase Auth) для облачной синхронизации и профиля.
- **Загрузка в автономном режиме** — скачивайте песни и видео для прослушивания в автономном режиме.
- **Глубокие ссылки** – полная настраиваемая схема URL-адресов для открытия/воспроизведения песен, исполнителей, альбомов и плейлистов через браузер или общие ссылки.
- **Без рекламы и надежность** — непрерывное прослушивание с помощью открытых реле (Last.fm, MusicBrainz, iTunes), гарантирующих воспроизведение.

---

## 🌐 Локализация

Tunefy поставляется с **полным переводом** на 14 языков (плюс язык автоматической системы):

| Язык | Код | Язык | Код |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Установите язык в **Настройки → Язык** (или оставьте **Система** для автоматического определения).

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

**Надежность воспроизведения.** Приложение никогда не зависит от одного поставщика. Он исследует источники в
каскад приоритетов (локальное реле → облачное реле → зеркала без ключа → поиск по метаданным/заголовку), с
автоматический выключатель, пропускающий неисправный источник. **Облачный ретранслятор** обрабатывает поток, а затем
**передаёт байты** через собственное соединение, поэтому разрешение и воспроизведение используют один IP-адрес — это
что позволяет избежать блокировки 403 по IP-адресу на ссылках Googlevideo.

---

## 🛠️ Технический стек

| Слой | Технология |
|---|---|
| **Рамка** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Государственное управление** | [Riverpod](https://riverpod.dev/) |
| **Аудиосистема** | [Just Audio](https://pub.dev/packages/just_audio) и [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Извлечение** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (вилка от [anandnet](https://github.com/anandnet)) |
| **ИИ-диджей** | Google Gemini (`gemini_service`) |
| **Тексты** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + собственный движок караоке + DeepL перевод |
| **Локальное хранилище** | [Hive](https://docs.hivedb.dev/) |
| **Облачная синхронизация/аутентификация** | Supabase (Postgres + RLS, анонимность и вход в Google) |
| **Сеть** | [Dio](https://pub.dev/packages/dio) и [Http](https://pub.dev/packages/http) |
| **Ретрансляция потока** | FastAPI + yt-dlp на Render (`server/`) |
| **Компоненты пользовательского интерфейса** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Настройка и установка

### Предварительные условия
- Flutter SDK (последняя стабильная версия)
- Dart SDK
- Android Studio / Код VS
- Java JDK 17

### Установка

1. **Клонировать репозиторий:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Установить зависимости:**
   ```bash
   flutter pub get
   ```

3. **Запустите приложение:**
   ```bash
   flutter run
   ```

4. **Построить версию APK** (разделить по ABI для меньшего размера):
   ```bash
   flutter build apk --split-per-abi
   ```

> URL-адрес облачного ретранслятора встроен в `lib/utils/api_constants.dart`
> (`relayBaseUrl`), поэтому флаг сборки не требуется. Чтобы указать на свое реле:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Бэкэнд и потоковые серверы

### ☁️ Реле облачного потока — `server/` (развернуто Render)
Разрешает URL-адрес аудио YouTube **и передает байты**, поэтому телефон и преобразователь имеют один IP-адрес.
(№ 403). FastAPI + yt-dlp, Docker, уровень бесплатного пользования.

| Конечная точка | Описание |
| --- | --- |
| `GET /health` | Датчик живости (`ok`) |
| `GET /stream?videoId=X&key=K` | Разрешается через yt-dlp → возвращает URL-адрес `…/relay` (200, только если он разрешается) |
| `GET /relay?videoId=X&key=K` | Проксирует аудиобайты (с учетом диапазона → 206 для поиска) |

Защищено общей переменной окружения `RELAY_KEY` (без нее возвращается **401**). Размещение: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. См. `server/README.md`.

### 🎵 API приложения — `backend/`
Серверная часть данных/поиска (YouTube Music через youtubei.js + открытые источники: Last.fm жанры,
MusicBrainz релизов и десятилетий).

| Конечная точка | Описание |
| --- | --- |
| `/api/search` | Поиск музыки/видео |
| `/api/trending` | Тренд |
| `/api/charts` | Музыкальные чарты YT |
| `/api/playlist/:id` | Подробности плейлиста |
| `/api/moods`, `/api/moods/:id` | Категории и настроения (Last.fm запасной вариант) |
| `/api/tags?tag=` | Лучшие треки/альбомы по жанрам (Last.fm) |
| `/api/newreleases` | Новые выпуски (MusicBrainz) |
| `/api/decades?year=` | Альбомы по десятилетиям (MusicBrainz) |
| `/api/categories` | Список категорий |

**Локальный:** `cd backend && npm install && npm start` (порт 8000).
**Развертывание (Vercel):** импортируйте этот репозиторий, **Root Directory = `backend`**. См. `backend/README.md`.

### 🗄️ База данных — `supabase/`
Схема Postgres с **Безопасностью на уровне строк**: пользовательские строки ограничены `auth.uid()`, каталог
доступен только для чтения анонимным пользователям и доступен для записи только роли службы. Запустите миграцию в Supabase
Редактор SQL (по порядку).

---

## 🤝 Вносим свой вклад

Вклады приветствуются! Будь то сообщение об ошибке, предложение функции или написание кода, ваша помощь будет оценена по достоинству.

1. **Развилка проекта**
2. **Создайте свою ветку функций** (`git checkout -b feature/AmazingFeature`)
3. **Зафиксируйте изменения** (`git commit -m 'Add some AmazingFeature'`)
4. **Толкать в ветку** (`git push origin feature/AmazingFeature`)
5. **Откройте запрос на включение**

**Рекомендации:** следуйте существующему стилю кода, запустите `flutter analyze` (должен быть чистым) и протестируйте новые функции перед отправкой.

---

## 🙏 Благодарности

Tunefy не существовало бы без невероятной работы этих разработчиков и проектов.

### youtube_explode_dart
Спасибо**[Hexer10](https://github.com/Hexer10)**, оригинальному автору
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — основа Tunefy
YouTube потоковая передача — и**[anandnet](https://github.com/anandnet)** для актуального форка, который
продолжает работать Tunefy с последними изменениями YouTube.

### Animesh (n-ce) — быстрый саавн и ytify
Привет**[Animesh (n-ce)](https://github.com/n-ce)**, создателю
**[fast-saavn](https://github.com/n-ce/saavn)** (открытый API JioSaavn, обеспечивающий метаданные Tunefy)
и**[ytify](https://github.com/n-ce/ytify)** (огромный источник вдохновения).

### Библиотеки с открытым исходным кодом
| Пакет | Автор/Сопровождающие |
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

Распространяется по лицензии **MIT License**. См. [`LICENSE`](LICENSE) для получения дополнительной информации.
