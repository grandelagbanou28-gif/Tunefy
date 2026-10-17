<p align="center">
  <img src="assets/logo.png" alt="Logo Tunefy" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Un client musical puissant et respectueux de la vie privée, construit avec Flutter.</strong><br/>
  Sans pubs · Hors ligne · DJ IA · Paroles synchronisées & traduites · UI Liquid Glass · 15 sources · Sans compte
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Version" />
  <img src="https://img.shields.io/badge/Plateforme-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Plateforme" />
  <img src="https://img.shields.io/badge/Langues-14-orange" alt="Langues" />
  <img src="https://img.shields.io/badge/Licence-MIT-green" alt="Licence" />
</p>

<p align="center">
  <a href="#-fonctionnalités-principales">Fonctionnalités</a> ·
  <a href="#-localisation">Langues</a> ·
  <a href="#-captures-décran">Captures</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#--installation">Installation</a> ·
  <a href="#-serveurs--streaming">Serveurs</a>
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

Tunefy est un client musical riche et respectueux de la vie privée, construit avec Flutter. Il
stream depuis **plus de 15 sources ouvertes et sans clé d'API** grâce à une cascade de repli
automatique : un titre qui échoue sur un fournisseur se joue sur le suivant. Il offre une
expérience premium sans pubs avec lecture en arrière-plan, téléchargements hors ligne, paroles
synchronisées **et traduites**, un **DJ IA**, radio internet, concerts, playlists Blend partagées,
une belle interface Liquid Glass et un cache intelligent — avec ou sans compte.

> [!NOTE]
> Tunefy est distribué directement depuis ce dépôt (APK). Il n'est **pas** disponible sur le
> Google Play Store.

---

## 🚀 Fonctionnalités principales

### 🎨 Interface Liquid Glass
- **Thèmes glassmorphism dynamiques** — Style premium en mode sombre et clair via `liquid_glass_easy`. Le mode clair utilise une teinte blanche semi-transparente qui s'adapte à la pochette.
- **Shaders & flou sur mesure** — Panneaux givrés et superpositions performants qui s'adaptent aux couleurs de l'artwork.
- **Éléments à contraste intelligent** — Icônes, contrôles, curseurs et menus s'inversent automatiquement pour rester lisibles.
- **Optimisé grand écran & bureau** — Layouts responsives (jusqu'à 1300px), boîtes centrées et barre de recherche dédiée pour desktop/tablette.

### 🎧 Audio immersif, paroles & karaoké
- **Karaoké mot à mot** — Les mots se remplissent de couleur en temps réel (60+ IPS).
- **Balançoire ligne à ligne** — Effet de balayage progressif avec mise en avant de la ligne active et défilement fluide.
- **Paroles traduites** — Les paroles sont traduites automatiquement (DeepL) dans la langue de l'app.
- **Mode Lofi** — Transforme n'importe quel titre en ambiance Lofi : ralenti 0.9×, correction de hauteur, réverbération native.
- **Égaliseur & effets natifs** — EQ système avec lecture en arrière-plan et audio écran éteint.
- **Audio multi-langues & qualité** — Détecte les langues audio disponibles et stream en Haute/Moyenne/Basse qualité.

### 🤖 DJ IA & personnalisation
- **Assistant DJ IA (Gemini)** — Un DJ conversationnel qui lit vos goûts, construit des playlists intelligentes et prend les demandes.
- **Taste Signals** — Un score de goût par titre apprend ce que vous adorez et guide les recommandations.
- **Wrapped & statistiques** — Votre bilan d'année : artistes, ambiances et capsules d'écoute.
- **Cache intelligent** — Mise en cache asynchrone de l'audio et des pochettes pour une lecture instantanée, sans attente.

### 🌍 Découverte sur 15+ sources
Tunefy résout la lecture via une **cascade de repli automatique** sur ces fournisseurs (sans clé = sans inscription) :

| Source | Type | Notes |
|---|---|---|
| **YouTube / YT Music** | Vidéo / Audio | Principal, via youtube_explode + API interne |
| **Jamendo** | Sans clé | Catalogue Creative-Commons |
| **Deezer** | Sans clé | Catalogue + métadonnées |
| **Audius** | Sans clé | Artistes décentralisés |
| **JioSaavn** | API ouverte | Métadonnées & recherche rapides |
| **Invidious** | Sans clé | Miroir YouTube (4 instances) |
| **Piped** | API ouverte | Miroir YouTube |
| **OpenVerse** | Sans clé | Images/audio CC *(nouveau)* |
| **Wikimedia Commons** | Sans clé | Médias ouverts *(nouveau)* |
| **Beatport** | Sans clé | Électro/danse *(nouveau)* |
| **Dailymotion** | Sans clé | Repli vidéo *(nouveau)* |
| **ccMixter** | Sans clé | Culture du remix *(nouveau)* |
| **Internet Archive** | Sans clé | Audio historique *(nouveau)* |
| **Radio Browser** | Sans clé | Stations de radio internet |
| **iTunes / MusicBrainz / Last.fm** | Ouvert | Métadonnées, charts, genres |

- **Relais de stream cloud** — Un relais auto-hébergé résout et **relaye les octets audio** depuis la même IP que le lecteur, évitant le 403 HTTP propre aux liens Googlevideo verrouillés par IP. Voir [Serveurs](#-serveurs--streaming).
- **Import Spotify** — Collez une URL de playlist Spotify publique (ou scannez un code Spotify) pour importer vos titres.
- **Recherche globale** — Une recherche unique sur titres, vidéos, albums, artistes et podcasts.
- **Partager pour écouter** — Partagez des liens YouTube/YT Music directement dans Tunefy.

### 📻 Radio, concerts & vidéo
- **Radio internet** — Des milliers de stations en direct (Radio Browser).
- **Concerts** — Découvrez les événements live près de chez vous avec des pages détaillées.
- **Feed de clips** — Flux vertical de clips courts tendance et communautaires.
- **Lecteur vidéo** — Lecture vidéo complète avec fonds vidéo canvas.
- **Mixes DJ** — Découverte et lecture dédiées aux mixes DJ.

### 🤝 Social, Blends & communauté
- **Playlists Blend** — Créez une playlist partagée avec un court code (ex. `KORA-4821`) ; quiconque a le code peut écouter et contribuer, comme les liens Blend de Spotify.
- **Feed communautaire** — Cherchez, écoutez et découvrez les titres mis en ligne par la communauté.
- **Suivi des artistes** — Suivez vos artistes/chaînes préférés.
- **File intelligente & lecture infinie** — Auto-file avec gestion intelligente de la vidage.

### 🔐 Confidentialité & comptes
- **Aucun compte requis** — Favoris, playlists et historique sont stockés localement par défaut.
- **Connexion anonyme + Google** — Connexion facultative (identité anonyme de l'appareil ou Google via Supabase Auth) pour la synchro cloud et le profil.
- **Téléchargements hors ligne** — Téléchargez chansons et vidéos pour les écouter sans connexion.
- **Deep linking** — Schéma d'URL personnalisé pour ouvrir/lecture de titres, artistes, albums et playlists via navigateur ou liens partagés.
- **Sans pubs & fiable** — Écoute continue soutenue par des relais ouverts (Last.fm, MusicBrainz, iTunes).

---

## 🌐 Localisation

Tunefy est entièrement traduit en **14 langues** (plus la langue système automatique) :

| Langue | Code | Langue | Code |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Choisissez la langue dans **Réglages → Langue** (ou laissez **Système** pour la détection auto).

---

## 📸 Captures d'écran

### 🏠 Accueil & navigation
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Écran Accueil" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Accueil avec mini-lecteur" />
  <img src="images/library.jpg" width="30%" alt="Bibliothèque" />
</p>

### 🔍 Recherche
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Résultats de recherche" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Suggestions de recherche" />
</p>

### 🎵 Lecteur
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Lecteur immersif" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Lecteur classique" />
  <img src="images/song_queue.jpg" width="30%" alt="File d'attente" />
</p>

### 🎤 Paroles
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Paroles avec contrôles" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Paroles sans contrôles" />
</p>

### 👥 Communauté & profil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Feed communautaire" />
  <img src="images/profile_screen.jpg" width="30%" alt="Écran Profil" />
</p>

### ⚙️ Réglages & personnalisation
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Réglages" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Sélecteur de thème" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Couleur d'accent" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Couleur personnalisée" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Sélecteur de langue" />
</p>

### ℹ️ À propos
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Écran À propos" />
</p>

---

## 🏗️ Architecture

```
tunefy-music/
├── lib/                     # App Flutter (Riverpod + Just Audio)
│   ├── l10n/                # Localisation 14 langues
│   ├── providers/           # État Riverpod
│   ├── screens/             # Écrans UI
│   ├── services/            # Sources, streaming, DJ IA, synchro
│   └── widgets/             # Composants réutilisables
├── server/                  # ☁️ Relais de stream cloud (Render)  ← voir ci-dessous
├── backend/                 # API locale/stream + helpers yt-dlp
├── supabase/migrations/     # Schéma Postgres + politiques RLS
└── images/, assets/         # Captures & assets de marque
```

**Fiabilité de la lecture.** L'app ne dépend jamais d'un seul fournisseur. Elle sonde les sources
par cascade de priorité (relais local → relais cloud → miroirs sans clé → recherche par titre), avec
un disjoncteur qui écarte une source en échec. Le **relais cloud** résout un stream puis **relaye
les octets** via sa propre connexion, pour que résolution et lecture partagent une seule IP — c'est
ce qui évite le 403 verrouillé par IP sur les liens Googlevideo.

---

## 🛠️ Stack technique

| Couche | Technologie |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestion d'état** | [Riverpod](https://riverpod.dev/) |
| **Moteur audio** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **Extraction YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork par [anandnet](https://github.com/anandnet)) |
| **DJ IA** | Google Gemini (`gemini_service`) |
| **Paroles** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + moteur karaoké + traduction DeepL |
| **Stockage local** | [Hive](https://docs.hivedb.dev/) |
| **Synchro cloud / Auth** | Supabase (Postgres + RLS, connexion anonyme & Google) |
| **Réseau** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relais de stream** | FastAPI + yt-dlp sur Render (`server/`) |
| **Composants UI** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Installation

### Prérequis
- Flutter SDK (dernière version stable)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Installation

1. **Cloner le dépôt :**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Installer les dépendances :**
   ```bash
   flutter pub get
   ```

3. **Lancer l'app :**
   ```bash
   flutter run
   ```

4. **Build APK release** (divisé par ABI pour une taille réduite) :
   ```bash
   flutter build apk --split-per-abi
   ```

> L'URL du relais cloud est intégrée dans `lib/utils/api_constants.dart`
> (`relayBaseUrl`), aucun flag n'est nécessaire. Pour viser votre propre relais :
> `flutter run --dart-define=RELAY_BASE_URL=https://votre-relais.onrender.com`.

---

## 🖥️ Serveurs & streaming

### ☁️ Relais de stream cloud — `server/` (déployé sur Render)
Résout une URL audio YouTube **et relaye les octets** pour que le téléphone et le résolveur
partagent une seule IP (pas de 403). FastAPI + yt-dlp, Docker, offre gratuite.

| Endpoint | Description |
| --- | --- |
| `GET /health` | Sonde de vie (`ok`) |
| `GET /stream?videoId=X&key=K` | Résout via yt-dlp → renvoie une URL `…/relay` (200 seulement si résolution OK) |
| `GET /relay?videoId=X&key=K` | Relaye les octets audio (compatible Range → 206 pour le seek) |

Protégé par une variable `RELAY_KEY` partagée (renvoie **401** sans elle). Déploiement : Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Voir `server/README.md`.

### 🎵 API de l'app — `backend/`
Le backend données/recherche (YouTube Music via youtubei.js + sources ouvertes : Last.fm genres,
MusicBrainz sorties & décennies).

| Endpoint | Description |
| --- | --- |
| `/api/search` | Recherche musique / vidéo |
| `/api/trending` | Tendances |
| `/api/charts` | Charts YT Music |
| `/api/playlist/:id` | Détail playlist |
| `/api/moods`, `/api/moods/:id` | Catégories & moods (repli Last.fm) |
| `/api/tags?tag=` | Genres top titres/albums (Last.fm) |
| `/api/newreleases` | Nouvelles sorties (MusicBrainz) |
| `/api/decades?year=` | Albums par décennie (MusicBrainz) |
| `/api/categories` | Liste des catégories |

**Local :** `cd backend && npm install && npm start` (port 8000).
**Déploiement (Vercel) :** importer ce dépôt, **Root Directory = `backend`**. Voir `backend/README.md`.

### 🗄️ Base de données — `supabase/`
Schéma Postgres avec **sécurité au niveau des lignes (RLS)** : les lignes utilisateur sont limitées
à `auth.uid()`, le catalogue est en lecture seule pour les utilisateurs anonymes et inscriptible
uniquement par le service role. Exécutez les migrations dans l'éditeur SQL Supabase (dans l'ordre).

---

## 🤝 Contribuer

Les contributions sont les bienvenues ! Rapport de bug, idée de fonctionnalité ou code : tout aide.

1. **Forkuez le projet**
2. **Créez votre branche** (`git checkout -b feature/AmazingFeature`)
3. **Committez vos changements** (`git commit -m 'Add some AmazingFeature'`)
4. **Poussez la branche** (`git push origin feature/AmazingFeature`)
5. **Ouvrez une Pull Request**

**Consignes :** suivez le style existant, lancez `flutter analyze` (doit être propre), et testez les
nouvelles fonctionnalités avant de soumettre.

---

## 🙏 Remerciements

Tunefy n'existerait pas sans le travail incroyable de ces développeurs et projets.

### youtube_explode_dart
Merci à **[Hexer10](https://github.com/Hexer10)**, auteur original de
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — la colonne vertébrale du
streaming YouTube de Tunefy — et à **[anandnet](https://github.com/anandnet)** pour la fork à jour.

### Animesh (n-ce) — fast-saavn & ytify
Merci à **[Animesh (n-ce)](https://github.com/n-ce)**, créateur de
**[fast-saavn](https://github.com/n-ce/saavn)** (l'API JioSaavn ouverte) et
**[ytify](https://github.com/n-ce/ytify)** (une grande source d'inspiration).

### Bibliothèques open-source
| Package | Auteur / Mainteneurs |
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
