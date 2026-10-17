<p align="center">
  <img src="assets/logo.png" alt="Tunefy लोगो" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Flutter से बना एक शक्तिशाली, गोपनीयता-केंद्रित संगीत क्लाइंट।</strong><br/>
  विज्ञापन-मुक्त · ऑफ़लाइन · AI DJ · सिंक और अनुवादित बोल · Liquid Glass UI · 15 स्रोत · किसी खाते की आवश्यकता नहीं
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="संस्करण" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="प्लेटफ़ॉर्म" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="भाषाएँ" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="लाइसेंस" />
</p>

<p align="center">
  <a href="#-key-features">विशेषताएँ</a> ·
  <a href="#-localisation">भाषाएँ</a> ·
  <a href="#-screenshots">स्क्रीनशॉट</a> ·
  <a href="#-architecture">आर्किटेक्चर</a> ·
  <a href="#-setup--installation">सेटअप</a> ·
  <a href="#-backend--streaming-servers">सर्वर</a>
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
  <b>हिन्दी</b> ·
  <a href="README.id.md">Bahasa Indonesia</a> ·
  <a href="README.vi.md">Tiếng Việt</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy एक सुविधा-समृद्ध, गोपनीयता-केंद्रित संगीत क्लाइंट है जो Flutter से बना है। यह
**15+ खुले और बिना कुंजी वाले स्रोतों** से स्ट्रीम करता है, जिसमें स्वचालित फ़ॉलबैक कैस्केड है, इसलिए एक
प्रदाता पर विफल होने वाला ट्रैक अगले पर चलता है। यह बैकग्राउंड प्लेबैक,
ऑफ़लाइन डाउनलोड, सिंक्रोनाइज़्ड **और अनुवादित** बोल, एक **AI DJ**, इंटरनेट रेडियो, कॉन्सर्ट,
साझा Blend प्लेलिस्ट, आधुनिक Liquid Glass UI और स्मार्ट बैकग्राउंड कैशिंग के साथ एक प्रीमियम
विज्ञापन-मुक्त अनुभव प्रदान करता है — खाते के साथ या बिना।

> [!NOTE]
> Tunefy सीधे इस रिपॉज़िटरी से वितरित होता है (APK रिलीज़)। यह Google Play
> Store पर उपलब्ध **नहीं** है।

---

## 🚀 मुख्य विशेषताएँ

### 🎨 Liquid Glass UI/UX
- **डायनामिक Glassmorphic थीम** — `liquid_glass_easy` के माध्यम से डार्क और लाइट मोड में प्रीमियम स्टाइलिंग। लाइट मोड एक अर्ध-पारदर्शी सफ़ेद टिंट का उपयोग करता है जो एल्बम आर्ट के अनुरूप ढलता है।
- **कस्टम शेडर और ब्लर** — उच्च-प्रदर्शन वाले फ़्रॉस्टेड ग्लास पैनल और ओवरले जो आर्टवर्क के रंगों के अनुरूप ढलते हैं।
- **कंट्रास्ट-जागरूक तत्व** — स्टेटस बार आइकन, नियंत्रण, स्लाइडर और मेनू पठनीयता के लिए स्वतः इन्वर्ट हो जाते हैं।
- **बड़ी स्क्रीन और डेस्कटॉप अनुकूलन** — रिस्पॉन्सिव प्लेयर लेआउट (1300px तक), केंद्रित डायलॉग, और डेस्कटॉप/टैबलेट के लिए समर्पित शीर्ष खोज बार।

### 🎧 इमर्सिव ऑडियो, बोल और कराओके
- **शब्द-दर-शब्द कराओके** — जैसे ही कलाकार गाता है, शब्द वास्तविक समय में रंग से भरते जाते हैं (60+ FPS)।
- **लाइन-बाय-लाइन सिंक्ड स्वीप** — सक्रिय लाइन की हाइलाइटिंग और स्मूथ स्क्रोलिंग के साथ प्रगतिशील स्वीप इफ़ेक्ट।
- **अनुवादित बोल** — बोलों का मशीनी अनुवाद (DeepL) आपकी ऐप भाषा में ऑन-द-फ़्लाई किया जाता है।
- **Lofi मोड** — किसी भी ट्रैक को Lofi वाइब में बदलें: 0.9× स्लो, पिच करेक्शन, नेटिव रिवर्ब।
- **इक्वलाइज़र और नेटिव इफ़ेक्ट्स** — बैकग्राउंड प्लेबैक और स्क्रीन-ऑफ़ ऑडियो के साथ सिस्टम-स्तरीय EQ।
- **मल्टी-लैंग्वेज ऑडियो और क्वालिटी कंट्रोल** — उपलब्ध ऑडियो भाषाओं का पता लगाएँ और हाई/मीडियम/लो क्वालिटी में स्ट्रीम करें।

### 🤖 AI DJ और वैयक्तिकरण
- **AI DJ सहायक (Gemini)** — एक संवादात्मक DJ जो आपकी पसंद पढ़ता है, स्मार्ट प्लेलिस्ट बनाता है और अनुरोध लेता है।
- **टेस्ट सिग्नल** — प्रति-ट्रैक टेस्ट स्कोरिंग सीखती है कि आप क्या पसंद करते हैं और सिफ़ारिशों को संचालित करती है।
- **Wrapped और श्रवण आँकड़े** — आपकी वार्षिक समीक्षा: शीर्ष कलाकार, मूड और श्रवण कैप्सूल।
- **स्मार्ट कैश सिस्टम** — तुरंत, बिना प्रतीक्षा प्लेबैक के लिए ऑडियो + मल्टी-रेज़ोल्यूशन आर्टवर्क की एसिंक बैकग्राउंड कैशिंग।

### 🌍 15+ स्रोतों में खोज
Tunefy इन प्रदाताओं में **स्वचालित फ़ॉलबैक कैस्केड** के माध्यम से प्लेबैक हल करता है (बिना कुंजी = किसी API कुंजी की आवश्यकता नहीं):

| स्रोत | प्रकार | टिप्पणियाँ |
|---|---|---|
| **YouTube / YT Music** | वीडियो / ऑडियो | प्राथमिक, youtube_explode + आंतरिक API के माध्यम से |
| **Jamendo** | बिना कुंजी | क्रिएटिव-कॉमन्स कैटलॉग |
| **Deezer** | बिना कुंजी | कैटलॉग + मेटाडेटा |
| **Audius** | बिना कुंजी | विकेंद्रीकृत कलाकार |
| **JioSaavn** | ओपन API | तेज़ मेटाडेटा और खोज |
| **Invidious** | बिना कुंजी | YouTube मिरर (4 इंस्टेंस) |
| **Piped** | ओपन API | YouTube मिरर |
| **OpenVerse** | बिना कुंजी | CC इमेज/ऑडियो *(नया)* |
| **Wikimedia Commons** | बिना कुंजी | ओपन मीडिया *(नया)* |
| **Beatport** | बिना कुंजी | इलेक्ट्रॉनिक/डांस *(नया)* |
| **Dailymotion** | बिना कुंजी | वीडियो फ़ॉलबैक *(नया)* |
| **ccMixter** | बिना कुंजी | रीमिक्स संस्कृति *(नया)* |
| **Internet Archive** | बिना कुंजी | ऐतिहासिक ऑडियो *(नया)* |
| **Radio Browser** | बिना कुंजी | इंटरनेट रेडियो स्टेशन |
| **iTunes / MusicBrainz / Last.fm** | ओपन | मेटाडेटा, चार्ट, विधाएँ |

- **क्लाउड स्ट्रीम रिले** — एक सेल्फ़-होस्टेड रिले उसी IP से ऑडियो बाइट्स को हल करता है **और प्रॉक्सी करता है** जिसका उपयोग प्लेयर करता है, जिससे HTTP 403 से बचा जाता है जो IP-लॉक किए गए Googlevideo लिंक अन्यथा लौटाते हैं। देखें [सर्वर](#-backend--streaming-servers)।
- **Spotify आयात** — किसी भी सार्वजनिक Spotify प्लेलिस्ट URL (या Spotify कोड स्कैन करके) को पेस्ट करके ट्रैक आयात करें।
- **ग्लोबल सर्च** — गाने, वीडियो, एल्बम, कलाकार और पॉडकास्ट में एक ही खोज।
- **शेयर टू प्ले** — YouTube/YT Music लिंक सीधे Tunefy में शेयर करें।

### 📻 रेडियो, कॉन्सर्ट और वीडियो
- **इंटरनेट रेडियो** — हज़ारों लाइव स्टेशन (Radio Browser)।
- **कॉन्सर्ट** — समृद्ध विवरण पृष्ठों के साथ अपने आस-पास के लाइव इवेंट खोजें।
- **क्लिप्स फ़ीड** — समुदाय और ट्रेंडिंग क्लिप्स की वर्टिकल शॉर्ट-वीडियो फ़ीड।
- **वीडियो प्लेयर** — कैनवास वीडियो बैकग्राउंड के साथ पूर्ण वीडियो प्लेबैक।
- **DJ मिक्सेस** — समर्पित DJ/मिक्स खोज और प्लेबैक।

### 🤝 सोशल, Blends और समुदाय
- **Blend प्लेलिस्ट** — एक छोटे जॉइन कोड (जैसे `KORA-4821`) के साथ साझा प्लेलिस्ट बनाएँ; कोड वाला कोई भी व्यक्ति सुन सकता है और योगदान दे सकता है, ठीक Spotify Blend लिंक की तरह।
- **समुदाय फ़ीड** — समुदाय द्वारा अपलोड किए गए ट्रैक खोजें, स्ट्रीम करें और खोजें।
- **कलाकार फ़ॉलोइंग** — कलाकारों/चैनलों को फ़ॉलो करके उन पर नज़र रखें।
- **स्मार्ट क्यू और इनफ़िनिट प्लेबैक** — बुद्धिमान क्लियर व्यवहार के साथ ऑटो-क्यू।

### 🔐 गोपनीयता और खाते
- **किसी खाते की आवश्यकता नहीं** — पसंदीदा, प्लेलिस्ट और इतिहास डिफ़ॉल्ट रूप से स्थानीय रूप से संग्रहीत होते हैं।
- **अनाम + Google साइन-इन** — क्लाउड सिंक और प्रोफ़ाइल के लिए वैकल्पिक साइन-इन (अनाम डिवाइस पहचान या Supabase Auth के माध्यम से Google)।
- **ऑफ़लाइन डाउनलोड** — ऑफ़लाइन सुनने के लिए गाने और वीडियो डाउनलोड करें।
- **डीप लिंकिंग** — ब्राउज़र या साझा लिंक के माध्यम से गाने, कलाकार, एल्बम और प्लेलिस्ट खोलने/चलाने के लिए पूर्ण कस्टम URL स्कीम।
- **विज्ञापन-मुक्त और भरोसेमंद** — खुले रिले (Last.fm, MusicBrainz, iTunes) द्वारा समर्थित निर्बाध श्रवण, प्लेबैक की गारंटी के लिए।

---

## 🌐 स्थानीयकरण

Tunefy 14 भाषाओं में **पूर्ण अनुवाद** के साथ आता है (साथ ही स्वचालित सिस्टम भाषा):

| भाषा | कोड | भाषा | कोड |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

**Settings → Language** में भाषा सेट करें (या स्वचालित पहचान के लिए **System** रखें)।

---

## 📸 स्क्रीनशॉट

### 🏠 होम और नेविगेशन
<p align="center">
  <img src="images/home.jpg" width="30%" alt="होम स्क्रीन" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="मिनी प्लेयर के साथ होम" />
  <img src="images/library.jpg" width="30%" alt="लाइब्रेरी" />
</p>

### 🔍 खोज
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="खोज परिणाम" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="खोज सुझाव" />
</p>

### 🎵 प्लेयर
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="इमर्सिव प्लेयर" />
  <img src="images/leagcy_player.jpg" width="30%" alt="लेगेसी प्लेयर" />
  <img src="images/song_queue.jpg" width="30%" alt="गाना क्यू" />
</p>

### 🎤 बोल
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="नियंत्रणों के साथ बोल" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="बिना नियंत्रणों के बोल" />
</p>

### 👥 समुदाय और प्रोफ़ाइल
<p align="center">
  <img src="images/community.jpg" width="30%" alt="समुदाय फ़ीड" />
  <img src="images/profile_screen.jpg" width="30%" alt="प्रोफ़ाइल स्क्रीन" />
</p>

### ⚙️ सेटिंग्स और अनुकूलन
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="सेटिंग्स" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="थीम चयनकर्ता" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="एक्सेंट रंग" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="कस्टम एक्सेंट रंग" />
  <img src="images/app_language_selector.jpg" width="30%" alt="भाषा चयनकर्ता" />
</p>

### ℹ️ परिचय
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="परिचय स्क्रीन" />
</p>

---

## 🏗️ आर्किटेक्चर

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

**प्लेबैक विश्वसनीयता।** ऐप कभी भी किसी एक प्रदाता पर निर्भर नहीं रहता। यह स्रोतों को प्राथमिकता
कैस्केड में जाँचता है (स्थानीय रिले → क्लाउड रिले → बिना कुंजी वाले मिरर → मेटाडेटा/शीर्षक खोज), जिसमें
एक सर्किट ब्रेकर होता है जो विफल हो रहे स्रोत को छोड़ देता है। **क्लाउड रिले** एक स्ट्रीम हल करता है और फिर
अपने कनेक्शन के माध्यम से **बाइट्स को रिले करता है**, ताकि रिज़ॉल्यूशन और प्लेबैक एक ही IP साझा करें — यही
वह है जो Googlevideo लिंक पर IP-लॉक 403 से बचाता है।

---

## 🛠️ टेक स्टैक

| परत | प्रौद्योगिकी |
|---|---|
| **फ़्रेमवर्क** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **स्टेट प्रबंधन** | [Riverpod](https://riverpod.dev/) |
| **ऑडियो इंजन** | [Just Audio](https://pub.dev/packages/just_audio) और [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube एक्सट्रैक्शन** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) ([anandnet](https://github.com/anandnet) द्वारा फ़ोर्क) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **बोल** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + कस्टम कराओके इंजन + DeepL अनुवाद |
| **स्थानीय स्टोरेज** | [Hive](https://docs.hivedb.dev/) |
| **क्लाउड सिंक / प्रमाणीकरण** | Supabase (Postgres + RLS, अनाम और Google साइन-इन) |
| **नेटवर्किंग** | [Dio](https://pub.dev/packages/dio) और [Http](https://pub.dev/packages/http) |
| **स्ट्रीम रिले** | Render पर FastAPI + yt-dlp (`server/`) |
| **UI कंपोनेंट** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ सेटअप और इंस्टॉलेशन

### पूर्व-आवश्यकताएँ
- Flutter SDK (नवीनतम स्थिर)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### इंस्टॉलेशन

1. **रिपॉज़िटरी क्लोन करें:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **निर्भरताएँ इंस्टॉल करें:**
   ```bash
   flutter pub get
   ```

3. **ऐप चलाएँ:**
   ```bash
   flutter run
   ```

4. **रिलीज़ APK बनाएँ** (छोटे आकार के लिए ABI के अनुसार विभाजित):
   ```bash
   flutter build apk --split-per-abi
   ```

> क्लाउड रिले URL `lib/utils/api_constants.dart` (`relayBaseUrl`) में एम्बेडेड है,
> इसलिए किसी बिल्ड फ़्लैग की आवश्यकता नहीं है। अपने स्वयं के रिले को निर्देशित करने के लिए:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`।

---

## 🖥️ बैकएंड और स्ट्रीमिंग सर्वर

### ☁️ क्लाउड स्ट्रीम रिले — `server/` (Render पर तैनात)
एक YouTube ऑडियो URL हल करता है **और बाइट्स को रिले करता है** ताकि फ़ोन और रिज़ॉल्वर एक ही IP साझा करें (कोई 403 नहीं)। FastAPI + yt-dlp, Docker, फ़्री टियर।

| एंडपॉइंट | विवरण |
| --- | --- |
| `GET /health` | लिवनेस प्रोब (`ok`) |
| `GET /stream?videoId=X&key=K` | yt-dlp के माध्यम से हल करता है → एक `…/relay` URL लौटाता है (केवल तभी 200 जब यह हल हो) |
| `GET /relay?videoId=X&key=K` | ऑडियो बाइट्स को प्रॉक्सी करता है (Range-जागरूक → सीकिंग के लिए 206) |

एक साझा `RELAY_KEY` env वेरिएबल से संरक्षित (इसके बिना **401** लौटाता है)। तैनाती: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**। देखें `server/README.md`।

### 🎵 ऐप API — `backend/`
डेटा/खोज बैकएंड (youtubei.js के माध्यम से YouTube Music + खुले स्रोत: Last.fm विधाएँ,
MusicBrainz रिलीज़ और दशक)।

| एंडपॉइंट | विवरण |
| --- | --- |
| `/api/search` | संगीत / वीडियो खोज |
| `/api/trending` | ट्रेंडिंग |
| `/api/charts` | YT Music चार्ट |
| `/api/playlist/:id` | प्लेलिस्ट विवरण |
| `/api/moods`, `/api/moods/:id` | श्रेणियाँ और मूड (Last.fm फ़ॉलबैक) |
| `/api/tags?tag=` | विधि शीर्ष गाने/एल्बम (Last.fm) |
| `/api/newreleases` | नई रिलीज़ (MusicBrainz) |
| `/api/decades?year=` | दशक के अनुसार एल्बम (MusicBrainz) |
| `/api/categories` | श्रेणी सूची |

**स्थानीय:** `cd backend && npm install && npm start` (पोर्ट 8000)।
**तैनाती (Vercel):** इस रिपॉज़िटरी को आयात करें, **Root Directory = `backend`**। देखें `backend/README.md`।

### 🗄️ डेटाबेस — `supabase/`
**Row-Level Security** के साथ Postgres स्कीम: उपयोगकर्ता पंक्तियाँ `auth.uid()` तक सीमित हैं, कैटलॉग
अनाम उपयोगकर्ताओं के लिए केवल-पठनीय है और केवल service role द्वारा लिखने योग्य है। Supabase SQL
एडिटर में माइग्रेशन चलाएँ (क्रम में)।

---

## 🤝 योगदान

योगदान स्वागत है! चाहे आप कोई बग रिपोर्ट कर रहे हों, कोई सुविधा सुझा रहे हों, या कोड लिख रहे हों, आपकी सहायता सराही जाती है।

1. **प्रोजेक्ट को फ़ोर्क करें**
2. **अपनी फ़ीचर ब्रांच बनाएँ** (`git checkout -b feature/AmazingFeature`)
3. **अपने बदलाव कमिट करें** (`git commit -m 'Add some AmazingFeature'`)
4. **ब्रांच पर पुश करें** (`git push origin feature/AmazingFeature`)
5. **एक Pull Request खोलें**

**दिशानिर्देश:** मौजूदा कोड शैली का पालन करें, `flutter analyze` चलाएँ (स्वच्छ होना चाहिए), और सबमिट करने से पहले नई सुविधाओं का परीक्षण करें।

---

## 🙏 आभार

इन डेवलपर्स और परियोजनाओं के अविश्वसनीय कार्य के बिना Tunefy मौजूद नहीं होता।

### youtube_explode_dart
मूल लेखक **[Hexer10](https://github.com/Hexer10)** को धन्यवाद,
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — Tunefy की YouTube स्ट्रीमिंग की
रीढ़ — और नवीनतम YouTube परिवर्तनों के साथ Tunefy को चालू रखने वाले अप-टू-डेट फ़ोर्क के लिए
**[anandnet](https://github.com/anandnet)** को धन्यवाद।

### Animesh (n-ce) — fast-saavn और ytify
**[fast-saavn](https://github.com/n-ce/saavn)** (Tunefy के मेटाडेटा को शक्ति देने वाला खुला JioSaavn API) के
निर्माता **[Animesh (n-ce)](https://github.com/n-ce)** और प्रेरणा के एक विशाल स्रोत
**[ytify](https://github.com/n-ce/ytify)** को शाउटआउट।

### ओपन-सोर्स लाइब्रेरी
| पैकेज | लेखक / रखरखावकर्ता |
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

## 📄 लाइसेंस

**MIT लाइसेंस** के तहत वितरित। अधिक जानकारी के लिए [`LICENSE`](LICENSE) देखें।
