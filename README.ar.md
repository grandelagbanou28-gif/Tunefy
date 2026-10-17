<p align="center">
  <img src="assets/logo.png" alt="شعار Tunefy" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>عميل موسيقى قوي ومركز على الخصوصية، مبني بـ Flutter.</strong><br/>
  بدون إعلانات · بدون اتصال · DJ بالذكاء الاصطناعي · كلمات الأغاني متزامنة ومترجمة · واجهة Liquid Glass · 15 مصدرًا · دون الحاجة إلى حساب
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="الإصدار" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="المنصة" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="اللغات" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="الترخيص" />
</p>

<p align="center">
  <a href="#-key-features">الميزات</a> ·
  <a href="#-localisation">اللغات</a> ·
  <a href="#-screenshots">لقطات الشاشة</a> ·
  <a href="#-architecture">البنية</a> ·
  <a href="#-setup--installation">الإعداد</a> ·
  <a href="#-backend--streaming-servers">الخوادم</a>
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
  <b>العربية</b> ·
  <a href="README.hi.md">हिन्दी</a> ·
  <a href="README.id.md">Bahasa Indonesia</a> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy عميل موسيقى غني بالميزات ومصمم معالجة الخصوصية، مبني بـ Flutter. يقوم بالبث من
**أكثر من 15 مصدرًا مفتوحًا وبلا مفتاح** مع تسلسل احتياطي تلقائي، بحيث تُشغَّل الأغاني التي تفشل في أحد
المزودين على التالي. يوفر تجربة مميزة خالية من الإعلانات مع التشغيل في الخلفية،
والتنزيلات دون اتصال، وكلمات الأغاني المتزامنة **ومترجمة**، و**DJ بالذكاء الاصطناعي**، وإذاعة الإنترنت، والحفلات،
وثِمارات Blend المشتركة، وواجهة Liquid Glass العصرية، والتخزين الذكي في الخلفية — مع حساب أو بدونه.

> [!NOTE]
> يُوزَع Tunefy مباشرة من هذا المستودع (إصدارات APK). وهو **غير** متاح
> على متجر Google Play.

---

## 🚀 الميزات الرئيسية

### 🎨 واجهة وتجربة Liquid Glass
- **سمات Glassmorphic ديناميكية** — تصميم مميز في الوضعين الداكن والفاتح عبر `liquid_glass_easy`. يستخدم الوضع الفاتح تلوينًا أبيض شبه شفاف يتكيّف مع غلاف الألبوم.
- **Shaders مخصصة وضبابية** — ألواح زجاجية مصنفرة وطبقات تراكب عالية الأداء تتكيّف مع ألوان الصورة.
- **عناصر واعية بالتباين** — أيقونات شريط الحالة، عناصر التحكم، أشرطة التمرير، والقوائم تنقلب تلقائيًا لضمان القراءة.
- **تحسين الشاشات الكبيرة وسطح المكتب** — تخطيطات مشغّل متجاوبة (حتى 1300 بكسل)، حوارات موسّطة، وشريط بحث علوي مخصص لسطح المكتب/الجهاز اللوحي.

### 🎧 صوت غامر وكلمات أغانٍ وكاريوكي
- **كاريوكي بالكلمة** — تمتلئ الكلمات بالألوان بشكل لحظي أثناء غنّي الفنان (أكثر من 60 إطارًا/ثانية).
- **تزامن سطر بسطر** — تأثير مسح تدريجي مع إبراز السطر النشت وتمرير سلس.
- **كلمات مترجمة** — تُترجم كلمات الأغاني آليًا (DeepL) إلى لغة التطبيق أثناء التشغيل.
- **وضع Lofi** — حوّل أي أغنية إلى أجواء Lofi: إبطاء 0.9×، تصحيح طبقة الصوت، وصدى أصلي.
- **موازن صوتي وتأثيرات أصلية** — موازن على مستوى النظام مع تشغيل في الخلفية وصوت عند إطفاء الشاشة.
- **لغات صوت متعددة وجودة قابلة للتحكم** — اكتشف اللغات الصوتية المتاحة وابدأ البث بجودة عالية/متوسطة/منخفضة.

### 🤖 DJ بالذكاء الاصطناعي والتخصيص
- **مساعد DJ بالذكاء الاصطناعي (Gemini)** — DJ حواري يقرأ ذوقك، ويبني قوائم تشغيل ذكية، ويستقبل طلباتك.
- **إشارات الذوق** — تقييم ذوق لكل أغنية يتعلّم ما تحبّه ويقود التوصيات.
- **Wrapped وإحصاءات الاستماع** — مراجعتك السنوية: أفضل الفنانين، الأجواء، وكبسولات الاستماع.
- **نظام ذاكرة تخزين ذكي** — تخزين غير متزامن في الخلفية للصوت + صور أغلفة بدقة متعددة لتشغيل فوري دون انتظار.

### 🌍 اكتشاف عبر أكثر من 15 مصدرًا
يقوم Tunefy بحل التشغيل عبر **تسلسل احتياطي تلقائي** عبر هؤلاء المزودين (بلا مفتاح = لا حاجة لمفتاح API):

| المصدر | النوع | ملاحظات |
|---|---|---|
| **YouTube / YT Music** | فيديو / صوت | الأساسي، عبر youtube_explode وواجهة داخلية |
| **Jamendo** | بلا مفتاح | كتالوج بترخيص المشاع الإبداعية |
| **Deezer** | بلا مفتاح | كتالوج + بيانات وصفية |
| **Audius** | بلا مفتاح | فنانون لامركزيون |
| **JioSaavn** | واجهة مفتوحة | بيانات وصفية وبحث سريع |
| **Invidious** | بلا مفتاح | مرآة YouTube (4 نسخ) |
| **Piped** | واجهة مفتوحة | مرآة YouTube |
| **OpenVerse** | بلا مفتاح | صور/صوت بترخيص CC *(جديد)* |
| **Wikimedia Commons** | بلا مفتاح | وسائط مفتوحة *(جديد)* |
| **Beatport** | بلا مفتاح | إلكتروني/دانس *(جديد)* |
| **Dailymotion** | بلا مفتاح | احتياطي الفيديو *(جديد)* |
| **ccMixter** | بلا مفتاح | ثقافة الريمكس *(جديد)* |
| **Internet Archive** | بلا مفتاح | أرشيف صوتي تاريخي *(جديد)* |
| **Radio Browser** | بلا مفتاح | محطات إذاعية إنترنت |
| **iTunes / MusicBrainz / Last.fm** | مفتوح | بيانات وصفية، قوائم ترتيب، أنواع |

- **بث سحابي عبر مُرحِّل** — مُرحِّل مستضاف ذاتيًا يحلّ رابط الصوت و**يوسيط البايتات** من نفس الـ IP الذي يستخدمه المشغّل، مما يتجنّب خطأ HTTP 403 الذي تعيده روابط Googlevideo المقفلة على IP. راجع [الخوادم](#-backend--streaming-servers).
- **الاستيراد من Spotify** — الصق أي رابط قائمة تشغيل Spotify عام (أو امسح رمز Spotify) لاستيراد الأغاني.
- **بحث شامل** — بحث واحد في الأغاني والفيديو والألبومات والفنانين والبودكاست.
- **المشاركة للتشغيل** — شارك روابط YouTube/YT Music مباشرة إلى Tunefy.

### 📻 الراديو والحفلات والفيديو
- **راديو الإنترنت** — آلاف المحطات المباشرة (Radio Browser).
- **الحفلات** — اكتشف الفعاليات المباشرة بالقرب منك مع صفحات تفاصيل غنية.
- **خلاصة الكليبات** — خلاصة فيديوهات قصيرة عمودية للكليبات المجتمعية والرائجة.
- **مشغّل الفيديو** — تشغيل فيديو كامل مع خلفيات فيديو على الـ canvas.
- **دي جي ميكسات** — اكتشاف وتشغيل مخصص لحفلات دي جي/الميكسات.

### 🤝 الاجتماعي والـ Blends والمجتمع
- **قوائم Blend** — أنشئ قائمة تشغيل مشتركة مع رمز انضمام قصير (مثل `KORA-4821`)؛ يمكن لأي شخص يملك الرمز الاستماع والمساهمة، تمامًا مثل روابط Blend في Spotify.
- **خلاصة المجتمع** — ابحث وبث واكتشف الأغاني التي يرفعها المجتمع.
- **متابعة الفنانين** — تابع الفنانين/القنوات لتبقى على اطلاع بأعمالهم.
- **قائمة انتظار ذكية وتشغيل لانهائي** — إضافة تلقائية لقائمة الانتظار مع سلوك مسح ذكي.

### 🔐 الخصوصية والحسابات
- **لا حاجة إلى حساب** — تُخزَّن المفضلة وقوائم التشغيل والسجل محليًا افتراضيًا.
- **تسجيل دخول مجهول + Google** — تسجيل دخول اختياري (هوية جهاز مجهولة أو Google عبر Supabase Auth) للمزامنة السحابية والملف الشخصي.
- **تنزيلات دون اتصال** — نزّل الأغاني والفيديوهات للاستماع دون اتصال.
- **الروابط العميقة** — مخطط URL مخصص بالكامل لفتح/تشغيل الأغاني والفنانين والألبومات وقوائم التشغيل عبر المتصفح أو الروابط المشتركة.
- **بدون إعلانات وموثوق** — استماع بلا انقطاع مدعوم بمُرحِّلات مفتوحة (Last.fm، MusicBrainz، iTunes) لضمان التشغيل.

---

## 🌐 التوطين

يأتي Tunefy بـ **ترجمات كاملة** بـ 14 لغة (بالإضافة إلى لغة النظام التلقائية):

| اللغة | الرمز | اللغة | الرمز |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

اختر اللغة من **الإعدادات ← اللغة** (أو اترك **System** للكشف التلقائي).

---

## 📸 لقطات الشاشة

### 🏠 الرئيسية والتنقل
<p align="center">
  <img src="images/home.jpg" width="30%" alt="الشاشة الرئيسية" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="الرئيسية مع المشغّل المصغّر" />
  <img src="images/library.jpg" width="30%" alt="المكتبة" />
</p>

### 🔍 البحث
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="نتائج البحث" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="اقتراحات البحث" />
</p>

### 🎵 المشغّل
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="المشغّل الغامر" />
  <img src="images/leagcy_player.jpg" width="30%" alt="المشغّل الكلاسيكي" />
  <img src="images/song_queue.jpg" width="30%" alt="قائمة انتظار الأغاني" />
</p>

### 🎤 كلمات الأغاني
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="الكلمات مع عناصر التحكم" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="الكلمات بدون عناصر التحكم" />
</p>

### 👥 المجتمع والملف الشخصي
<p align="center">
  <img src="images/community.jpg" width="30%" alt="خلاصة المجتمع" />
  <img src="images/profile_screen.jpg" width="30%" alt="الملف الشخصي" />
</p>

### ⚙️ الإعدادات والتخصيص
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="الإعدادات" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="منتقي السمة" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="اللون المميّز" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="لون مميّز مخصص" />
  <img src="images/app_language_selector.jpg" width="30%" alt="منتقي اللغة" />
</p>

### ℹ️ حول التطبيق
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="شاشة حول التطبيق" />
</p>

---

## 🏗️ البنية

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

**موثوقية التشغيل.** لا يعتمد التطبيق أبدًا على مزود واحد. فهو يختبر المصادر في
تسلسل أولوية (مُرحِّل محلي ← مُرحِّل سحابي ← مرايا بلا مفتاح ← بحث بالبيانات الوصفية/العنوان)، مع
قاطع دائرة يتجاوز المصدر المتعثر. يقوم **المُرحِّل السحابي** بحل الرابط ثم
**يسيط البايتات** عبر اتصاله الخاص بحيث يتشارك الحل والتشغيل نفس الـ IP — وهذا
ما يتجنّب خطأ 403 المقفل على IP في روابط Googlevideo.

---

## 🛠️ التقنيات المستخدمة

| الطبقة | التقنية |
|---|---|
| **الإطار** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **إدارة الحالة** | [Riverpod](https://riverpod.dev/) |
| **محرّك الصوت** | [Just Audio](https://pub.dev/packages/just_audio) و [Audio Service](https://pub.dev/packages/audio_service) |
| **استخراج YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (نسخة معدّلة من [anandnet](https://github.com/anandnet)) |
| **DJ بالذكاء الاصطناعي** | Google Gemini (`gemini_service`) |
| **كلمات الأغاني** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + محرك كاريوكي مخصص + ترجمة DeepL |
| **التخزين المحلي** | [Hive](https://docs.hivedb.dev/) |
| **المزامنة السحابية / المصادقة** | Supabase (Postgres + RLS، تسجيل دخول مجهول وGoogle) |
| **الشبكات** | [Dio](https://pub.dev/packages/dio) و [Http](https://pub.dev/packages/http) |
| **ترحيل البث** | FastAPI + yt-dlp على Render (`server/`) |
| **مكونات الواجهة** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ الإعداد والتثبيت

### المتطلبات الأساسية
- Flutter SDK (أحدث إصدار مستقر)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### التثبيت

1. **استنسخ المستودع:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **ثبّت الاعتماديات:**
   ```bash
   flutter pub get
   ```

3. **شغّل التطبيق:**
   ```bash
   flutter run
   ```

4. **ابنِ نسخة APK للإصدار** (مقسّمة حسب ABI لحجم أصغر):
   ```bash
   flutter build apk --split-per-abi
   ```

> عنوان مُرحِّل البث السحابي مدمج في `lib/utils/api_constants.dart`
> (`relayBaseUrl`)، لذا لا حاجة لأي علامة بناء. لاستخدام مُرحِّل خاص بك:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ الخوادم والواجهات الخلفية

### ☁️ مُرحِّل البث السحابي — `server/` (مستضاف على Render)
يحلّ رابط صوت YouTube **ويسيط البايتات** بحيث يتشارك الهاتف والحلّ الـ نفسه (لا 403). FastAPI + yt-dlp، Docker، خطة مجانية.

| نقطة النهاية | الوصف |
| --- | --- |
| `GET /health` | فحص البقاء (`ok`) |
| `GET /stream?videoId=X&key=K` | يحلّ عبر yt-dlp → يعيد رابط `…/relay` (200 فقط عند نجاح الحل) |
| `GET /relay?videoId=X&key=K` | يسيط بايتات الصوت (يدعم Range → 206 للتنقل داخل الأغنية) |

محميًا عبر متغير بيئة مشترك `RELAY_KEY` (يعيد **401** بدونه). النشر: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. راجع `server/README.md`.

### 🎵 واجهة التطبيق — `backend/`
واجهة الخلفية للبيانات والبحث (YouTube Music عبر youtubei.js + مصادر مفتوحة: أنواع Last.fm،
إصدارات وعقود MusicBrainz).

| نقطة النهاية | الوصف |
| --- | --- |
| `/api/search` | بحث الموسيقى / الفيديو |
| `/api/trending` | الرائج |
| `/api/charts` | قوائم ترتيب YT Music |
| `/api/playlist/:id` | تفاصيل قائمة التشغيل |
| `/api/moods`, `/api/moods/:id` | الفئات والمزاج (احتياطي Last.fm) |
| `/api/tags?tag=` | أفضل الأغاني/الألبومات حسب النوع (Last.fm) |
| `/api/newreleases` | الإصدارات الجديدة (MusicBrainz) |
| `/api/decades?year=` | ألبومات حسب العقد (MusicBrainz) |
| `/api/categories` | قائمة الفئات |

**محليًا:** `cd backend && npm install && npm start` (المنفذ 8000).
**النشر (Vercel):** استورد هذا المستودع، **Root Directory = `backend`**. راجع `backend/README.md`.

### 🗄️ قاعدة البيانات — `supabase/`
مخطط Postgres مع **أمان على مستوى الصفوف**: تُحدَّد صفوف المستخدم بـ `auth.uid()`، والكتالوج
للقراءة فقط للمستخدمين المجهولين ويُكتب فقط بواسطة service role. شغّل عمليات الترحيل في محرّر SQL
داخل Supabase (بالترتيب).

---

## 🤝 المساهمة

نرحّب بالمساهمات! سواء كنت تبلغ عن خطأ، أو تقترح ميزة، أو تكتب كودًا، فمساعدتك محل تقدير.

1. **عمل Fork للمشروع**
2. **أنشئ فرع ميزاتك** (`git checkout -b feature/AmazingFeature`)
3. **ثبّت تغييراتك** (`git commit -m 'Add some AmazingFeature'`)
4. **ادفع إلى الفرع** (`git push origin feature/AmazingFeature`)
5. **افتح طلب سحب (Pull Request)**

**إرشادات:** اتبع أسلوب الكود الحالي، وشغّل `flutter analyze` (يجب أن يكون نظيفًا)، واختبر الميزات الجديدة قبل الإرسال.

---

## 🙏 الشكر والتقدير

ما كان Tunefy ليوجد لولا العمل المذهل لهؤلاء المطورين والمشاريع.

### youtube_explode_dart
شكر خاص لـ **[Hexer10](https://github.com/Hexer10)**، المؤلف الأصلي لـ
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — العمود الفقري لبث YouTube في
Tunefy — و**[anandnet](https://github.com/anandnet)** على النسخة المحدّثة التي
تحافظ على عمل Tunefy مع أحدث تغييرات YouTube.

### Animesh (n-ce) — fast-saavn و ytify
تحية لـ **[Animesh (n-ce)](https://github.com/n-ce)**، صانع
**[fast-saavn](https://github.com/n-ce/saavn)** (واجهة JioSaavn المفتوحة التي تدعم البيانات الوصفية في Tunefy)
و **[ytify](https://github.com/n-ce/ytify)** (مصدر إلهام كبير).

### المكتبات مفتوحة المصدر
| الحزمة | المؤلف / المشرفون |
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

## 📄 الترخيص

يُوزَع بموجب **ترخيص MIT**. راجع [`LICENSE`](LICENSE) للمزيد من المعلومات.
