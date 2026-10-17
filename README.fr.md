<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>Un client musical puissant et axé sur la confidentialité, construit avec Flutter.</strong><br/>
  Sans publicité · Hors ligne · AI DJ · Paroles synchronisées et traduites · Liquid Glass UI · 15 sources · Aucun compte requis
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
  <a href="#-principales-fonctionnalités">Caractéristiques</a> ·
  <a href="#-localisation">Langues</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#-configuration-et-installation">Configuration</a> ·
  <a href="#-serveurs-backend-et-streaming">Serveurs</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <b>Français</b> ·
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
  <a href="README.zh.md">中文（简体）</a>
</p>

---

Tunefy est un client musical riche en fonctionnalités et axé sur la confidentialité, construit avec Flutter. Il diffuse depuis
**15+ sources ouvertes et sans clé** avec une cascade de repli automatique, donc une piste qui échoue sur une
Le fournisseur joue sur le suivant. Il offre une expérience premium sans publicité avec lecture en arrière-plan,
téléchargements hors ligne, paroles synchronisées **et traduites**, un **AI DJ**, radio Internet, concerts,
Blend listes de lecture partagées, une interface utilisateur Liquid Glass moderne et une mise en cache intelligente en arrière-plan – avec ou sans
un compte.

> [!NOTE]
> Tunefy est distribué directement depuis ce référentiel (versions APK). Il n'est **pas** disponible
> sur le Google Play Store.

---

## 🚀 Principales fonctionnalités

### 🎨 Liquid Glass UI/UX
- **Thèmes Glassmorphic dynamiques** — Style premium en modes Sombre et Clair via `liquid_glass_easy`. Le mode Lumière utilise une teinte blanche semi-transparente qui s'adapte à la pochette de l'album.
- **Shaders et flou personnalisés** — Panneaux et superpositions en verre dépoli hautes performances qui s'adaptent aux couleurs des illustrations.
- **Éléments sensibles au contraste** — Les icônes de la barre d'état, les commandes, les curseurs et les menus s'inversent automatiquement pour plus de lisibilité.
- **Optimisation grand écran et bureau** — Dispositions de lecteur réactives (jusqu'à 1 300 px), boîtes de dialogue centrées et barre de recherche supérieure dédiée pour ordinateur/tablette.

### 🎧 Audio immersif, paroles et karaoké
- **Karaoké mot par mot** — Les mots se remplissent de couleurs en temps réel pendant que l'artiste chante (60+ FPS).
- **Balayage synchronisé ligne par ligne** — Effet de balayage progressif avec surbrillance de ligne active et défilement fluide.
- **Paroles traduites** — Les paroles sont traduites automatiquement (DeepL) dans la langue de votre application à la volée.
- **Mode Lofi** — Transformez n'importe quelle piste en ambiance Lofi : ralenti 0,9×, correction de hauteur, réverbération native.
- **Égaliseur et effets natifs** — Égaliseur au niveau du système avec lecture en arrière-plan et audio hors écran.
- **Audio multilingue et contrôle de qualité** — Détectez les langues audio disponibles et diffusez en qualité haute/moyenne/basse.

### 🤖 DJ IA et personnalisation
- **AI DJ Assistant (Gemini)** — Un DJ conversationnel qui lit vos goûts, crée des listes de lecture intelligentes et répond aux demandes.
- **Signaux de goût** – La notation du goût par piste apprend ce que vous aimez et génère des recommandations.
- **Wrapped & statistiques d'écoute** — Votre bilan de l'année : meilleurs artistes, ambiances et capsules d'écoute.
- **Smart Cache System** — Mise en cache asynchrone en arrière-plan de l'audio + illustrations multi-résolution pour une lecture instantanée et sans attente.

### 🌍 Découverte à travers plus de 15 sources
Tunefy résout la lecture via une **cascade de secours automatique** entre ces fournisseurs (sans clé = aucune clé API nécessaire) :

| Source | Tapez | Remarques |
|---|---|---|
| **YouTube / YT Musique** | Vidéo/Audio | Primaire, via youtube_explode + API interne |
| **Jamendo** | Sans clé | Catalogue Creative-Commons |
| **Deezer** | Sans clé | Catalogue + métadonnées |
| **Audius** | Sans clé | Artistes décentralisés |
| **JioSaavn** | API ouverte | Métadonnées et recherche rapides |
| **Invidious** | Sans clé | YouTube miroir (4 instances) |
| **Piped** | API ouverte | YouTube miroir |
| **OpenVerse** | Sans clé | Images/audio CC *(nouveau)* |
| **Wikimedia Commons** | Sans clé | Médias ouverts *(nouveau)* |
| **Beatport** | Sans clé | Électronique/danse *(nouveau)* |
| **Dailymotion** | Sans clé | Vidéo de secours *(nouveau)* |
| **ccMixter** | Sans clé | Culture du remix *(nouveau)* |
| **Internet Archive** | Sans clé | Audio historique *(nouveau)* |
| **Radio Browser** | Sans clé | Stations de radio Internet |
| **iTunes / MusicBrainz / Last.fm** | Ouvrir | Métadonnées, graphiques, genres |

- **Cloud Stream Relay** — Un relais auto-hébergé résout et **remplace les octets audio** de la même adresse IP que le lecteur utilise, évitant ainsi le HTTP 403 que les liens vidéo Google verrouillés par IP renvoient autrement. Voir [Servers](#-serveurs-backend-et-streaming).
- **Spotify Importer** — Collez n'importe quelle URL de playlist publique Spotify (ou scannez un code Spotify) pour importer des pistes.
- **Recherche globale** — Une recherche parmi les chansons, vidéos, albums, artistes et podcasts.
- **Partager pour jouer** — Partagez les liens YouTube/YT Music directement dans Tunefy.

### 📻 Radio, Concerts & Vidéo
- **Radio Internet** — Des milliers de stations en direct (Radio Browser).
- **Concerts** — Découvrez des événements en direct près de chez vous grâce à de riches pages de détails.
- **Clips Feed** — Flux vidéo court vertical de clips communautaires et tendances.
- **Lecteur vidéo** — Lecture vidéo complète avec arrière-plans vidéo en toile.
- **DJ Mixes** — Découverte et lecture dédiées aux DJ/mix.

### 🤝 Social, Mélanges & Communauté
- **Blend Playlists** — Créez une liste de lecture partagée avec un court code de jointure (par exemple `KORA-4821`) ; toute personne possédant le code peut écouter et contribuer, comme les liens Spotify Blend.
- **Flux communautaire** — Recherchez, diffusez et découvrez les morceaux téléchargés par la communauté.
- **Suivi d'artistes** — Suivez des artistes/chaînes pour les suivre.
- **File d'attente intelligente et lecture infinie** — Mise en file d'attente automatique avec un comportement clair et intelligent.

### 🔐 Confidentialité et comptes
- **Aucun compte requis** — Les favoris, les listes de lecture et l'historique sont stockés localement par défaut.
- **Anonyme + Google Sign-In** — Connexion facultative (identité anonyme de l'appareil ou Google via Supabase Auth) pour la synchronisation et le profil dans le cloud.
- **Téléchargements hors ligne** — Téléchargez des chansons et des vidéos pour une écoute hors ligne.
- **Deep Linking** — Schéma d'URL entièrement personnalisé pour ouvrir/lire des chansons, des artistes, des albums et des listes de lecture via un navigateur ou des liens partagés.
- **Sans publicité et fiable** — Écoute ininterrompue soutenue par des relais ouverts (Last.fm, MusicBrainz, iTunes) pour garantir la lecture.

---

## 🌐 Localisation

Tunefy est livré avec des **traductions complètes** en 14 langues (plus la langue du système automatique) :

| Langue | Codes | Langue | Codes |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Définissez la langue dans **Paramètres → Langue** (ou conservez **Système** pour une détection automatique).

---

## 🏗️Architecture

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

**Fiabilité de lecture.** L'application ne dépend jamais d'un seul fournisseur. Il sonde les sources dans un
cascade prioritaire (relais local → relais cloud → miroirs sans clé → recherche de métadonnées/titre), avec un
disjoncteur qui ignore une source défaillante. Le **relais cloud** résout un flux, puis
**relais les octets** via sa propre connexion afin que la résolution et la lecture partagent une seule adresse IP – c'est
ce qui évite le 403 verrouillé par IP sur les liens vidéo Google.

---

## 🛠️ Pile technologique

| Couche | Technologie |
|---|---|
| **Cadre** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestion de l'État** | [Riverpod](https://riverpod.dev/) |
| **Moteur audio** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Extraction** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fourchette par [anandnet](https://github.com/anandnet)) |
| **DJ IA** | Google Gemini (`gemini_service`) |
| **Paroles** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + moteur de karaoké personnalisé + traduction DeepL |
| **Stockage local** | [Hive](https://docs.hivedb.dev/) |
| **Synchronisation Cloud/Authentification** | Supabase (Postgres + RLS, anonyme et connexion Google) |
| **Réseau** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relais de flux** | FastAPI + yt-dlp sur Render (`server/`) |
| **Composants de l'interface utilisateur** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Configuration et installation

### Prérequis
- Flutter SDK (dernière version stable)
- Dart SDK
- Android Studio / VS Code
- JavaJDK 17

### Installation

1. **Clonez le référentiel :**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Installer les dépendances :**
   ```bash
   flutter pub get
   ```

3. **Exécutez l'application :**
   ```bash
   flutter run
   ```

4. **Build release APK** (divisé par ABI pour une taille plus petite) :
   ```bash
   flutter build apk --split-per-abi
   ```

> L'URL du relais cloud est intégrée dans `lib/utils/api_constants.dart`
> (`relayBaseUrl`), donc aucun indicateur de build n'est requis. Pour pointer votre propre relais :
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Serveurs backend et streaming

### ☁️ Cloud Stream Relay — `server/` (déployé sur Render)
Résout une URL audio YouTube **et relaie les octets** afin que le téléphone et le résolveur partagent une seule adresse IP
(n° 403). FastAPI + yt-dlp, Docker, niveau gratuit.

| Point de terminaison | Descriptif |
| --- | --- |
| `GET /health` | Sonde de vivacité (`ok`) |
| `GET /stream?videoId=X&key=K` | Résout via yt-dlp → renvoie une URL `…/relay` (200 uniquement si elle est résolue) |
| `GET /relay?videoId=X&key=K` | Proxy les octets audio (Range-aware → 206 pour la recherche) |

Protégé par une variable d'environnement `RELAY_KEY` partagée (renvoie **401** sans elle). Deploy: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. See `server/README.md`.

### 🎵API de l'application — `backend/`
Le backend données/recherche (YouTube Music via youtubei.js + open sources : Last.fm genres,
MusicBrainz versions et décennies).

| Point de terminaison | Descriptif |
| --- | --- |
| `/api/search` | Recherche de musique/vidéo |
| `/api/trending` | Tendances |
| `/api/charts` | Palmarès YouTube Music |
| `/api/playlist/:id` | Détail de la playlist |
| `/api/moods`, `/api/moods/:id` | Catégories et ambiances (Last.fm solution de repli) |
| `/api/tags?tag=` | Meilleurs titres/albums du genre (Last.fm) |
| `/api/newreleases` | Nouveautés (MusicBrainz) |
| `/api/decades?year=` | Albums par décennie (MusicBrainz) |
| `/api/categories` | Liste des catégories |

**Local :** `cd backend && npm install && npm start` (port 8000).
**Déployer (Vercel) :** importez ce dépôt, **Root Directory = `backend`**. Voir `backend/README.md`.

### 🗄️ Base de données — `supabase/`
Schéma Postgres avec **Sécurité au niveau des lignes** : les lignes utilisateur sont étendues à `auth.uid()`, le catalogue est
en lecture seule pour les utilisateurs anonymes et accessible en écriture uniquement par le rôle de service. Exécutez les migrations dans le Supabase
Éditeur SQL (dans l'ordre).

---

## 🤝 Contribuer

Les contributions sont les bienvenues ! Qu'il s'agisse de signaler un bug, de suggérer une fonctionnalité ou d'écrire du code, votre aide est appréciée.

1. **Forkez le projet**
2. **Créez votre branche de fonctionnalités** (`git checkout -b feature/AmazingFeature`)
3. **Validez vos modifications** (`git commit -m 'Add some AmazingFeature'`)
4. **Pousser vers la succursale** (`git push origin feature/AmazingFeature`)
5. **Ouvrez une demande de tirage**

**Directives :** suivez le style de code existant, exécutez `flutter analyze` (doit être propre) et testez les nouvelles fonctionnalités avant de les soumettre.

---

## 🙏 Remerciements

Tunefy n'existerait pas sans le travail incroyable de ces développeurs et projets.

### youtube_explode_dart
Merci à**[Hexer10](https://github.com/Hexer10)**, auteur original de
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — l'épine dorsale des Tunefy
YouTube streaming — and**[anandnet](https://github.com/anandnet)** for the up-to-date fork that
continue à Tunefy de fonctionner avec les dernières YouTube modifications.

### Animesh (n-ce) — saavn rapide & ytify
Merci à**[Animesh (n-ce)](https://github.com/n-ce)**, créateur de
**[fast-saavn](https://github.com/n-ce/saavn)** (the open JioSaavn API powering Tunefy's metadata)
and**[ytify](https://github.com/n-ce/ytify)** (a huge source of inspiration).

### Bibliothèques open source
| Forfait | Auteur/mainteneurs |
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

## 📄 Licence

Distribué sous la **Licence MIT**. Voir [`LICENSE`](LICENSE) pour plus d'informations.
