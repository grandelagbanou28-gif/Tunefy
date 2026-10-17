<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>Un cliente de música potente y centrado en la privacidad creado con Flutter.</strong><br/>
  Sin publicidad · Sin conexión · AI DJ · Letras sincronizadas y traducidas · Liquid Glass UI · 15 fuentes · No se requiere cuenta
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
  <a href="#-características-clave">Características</a> ·
  <a href="#-localización">Idiomas</a> ·
  <a href="#-arquitectura">Arquitectura</a> ·
  <a href="#-configuración-e-instalación">Configuración</a> ·
  <a href="#-servidores-backend-y-de-streaming">Servidores</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.fo.md">Fongbé</a> ·
  <b>Español</b> ·
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

Tunefy es un cliente de música rico en funciones y centrado en la privacidad creado con Flutter. Se transmite desde
**Más de 15 fuentes abiertas y sin llave** con una cascada de respaldo automático, por lo que una pista que falla en una
El proveedor juega en el siguiente. Ofrece una experiencia premium sin publicidad con reproducción en segundo plano,
descargas sin conexión, letras sincronizadas **y traducidas**, un **AI DJ**, radio por Internet, conciertos,
listas de reproducción compartidas Blend, una interfaz de usuario moderna Liquid Glass y almacenamiento en caché en segundo plano inteligente, con o sin
una cuenta.

> [!NOTE]
> Tunefy se distribuye directamente desde este repositorio (versiones APK). **No** disponible
> en el Google Play Store.

---

## 🚀 Características clave

### 🎨 Liquid Glass UI/UX
- **Temas dinámicos Glassmorphic**: estilo premium en los modos Oscuro y Claro a través de `liquid_glass_easy`. El modo de luz utiliza un tinte blanco semitransparente que se adapta a la carátula del álbum.
- **Sombreadores y desenfoque personalizados**: paneles y superposiciones de vidrio esmerilado de alto rendimiento que se adaptan a los colores de las obras de arte.
- **Elementos sensibles al contraste**: los iconos, controles, controles deslizantes y menús de la barra de estado se invierten automáticamente para mayor legibilidad.
- **Optimización de pantalla grande y escritorio**: diseños de reproductor responsivos (hasta 1300 px), cuadros de diálogo centrados y una barra de búsqueda superior dedicada para escritorio/tableta.

### 🎧 Audio, letras y karaoke inmersivos
- **Karaoke palabra por palabra**: las palabras se llenan de color en tiempo real mientras el artista canta (más de 60 FPS).
- **Barrido sincronizado línea por línea**: efecto de barrido progresivo con resaltado de línea activa y desplazamiento suave.
- **Letras traducidas**: las letras se traducen automáticamente (DeepL) al idioma de su aplicación sobre la marcha.
- **Modo Lofi**: convierte cualquier pista en un ambiente Lofi: ralentizado 0,9×, corrección de tono, reverberación nativa.
- **Ecualizador y efectos nativos**: EQ a nivel de sistema con reproducción en segundo plano y audio sin pantalla.
- **Control de calidad y audio en varios idiomas**: detecta los idiomas de audio disponibles y transmite calidad alta/media/baja.

### 🤖 AI DJ y personalización
- **AI DJ Assistant (Gemini)**: un DJ conversacional que lee tus gustos, crea listas de reproducción inteligentes y acepta solicitudes.
- **Señales de sabor**: la puntuación de sabor por pista aprende lo que te gusta y genera recomendaciones.
- **Wrapped y estadísticas de escucha**: resumen del año: artistas destacados, estados de ánimo y cápsulas de escucha.
- **Sistema de caché inteligente**: almacenamiento en caché de fondo asíncrono de audio + ilustraciones de resolución múltiple para una reproducción instantánea y sin esperas.

### 🌍 Descubrimiento en más de 15 fuentes
Tunefy resuelve la reproducción a través de una **cascada de reserva automática** entre estos proveedores (sin clave = no se necesita clave API):

| Fuente | Tipo | Notas |
|---|---|---|
| **YouTube / YT Música** | Vídeo/Audio | Principal, a través de youtube_explode + API interna |
| **Jamendo** | Sin llave | Catálogo Creative-Commons |
| **Deezer** | Sin llave | Catálogo + metadatos |
| **Audius** | Sin llave | Artistas descentralizados |
| **JioSaavn** | Abrir API | Metadatos y búsqueda rápidos |
| **Invidious** | Sin llave | YouTube espejo (4 instancias) |
| **Piped** | Abrir API | YouTube espejo |
| **OpenVerse** | Sin llave | Imágenes CC/audio *(nuevo)* |
| **Wikimedia Commons** | Sin llave | Medios abiertos *(nuevo)* |
| **Beatport** | Sin llave | Electrónica/baile *(nuevo)* |
| **Dailymotion** | Sin llave | Vídeo alternativo *(nuevo)* |
| **ccMixter** | Sin llave | Cultura remezcla *(nuevo)* |
| **Internet Archive** | Sin llave | Audio histórico *(nuevo)* |
| **Radio Browser** | Sin llave | Estaciones de radio por Internet |
| **iTunes / MusicBrainz / Last.fm** | Abrir | Metadatos, gráficos, géneros |

- **Cloud Stream Relay**: una retransmisión autohospedada resuelve y **proxy los bytes de audio** de la misma IP que usa el reproductor, evitando el HTTP 403 que de otro modo devuelven los enlaces de Googlevideo con IP bloqueada. Ver [Servers](#-servidores-backend-y-de-streaming).
- **Spotify Importar**: pegue cualquier URL de lista de reproducción Spotify pública (o escanee un código Spotify) para importar pistas.
- **Búsqueda global**: una búsqueda entre canciones, vídeos, álbumes, artistas y podcasts.
- **Compartir para reproducir**: comparte enlaces de YouTube/YT Music directamente en Tunefy.

### 📻 Radio, Conciertos y Vídeo
- **Radio por Internet**: miles de estaciones en vivo (Radio Browser).
- **Conciertos**: descubra eventos en vivo cerca de usted con páginas detalladas.
- **Clips Feed**: transmisión vertical de videos cortos de clips de la comunidad y de tendencia.
- **Reproductor de vídeo**: reproducción de vídeo completa con fondos de vídeo en lienzo.
- **Mezclas de DJ**: descubrimiento y reproducción de mezclas/DJ dedicados.

### 🤝 Social, mezclas y comunidad
- **Blend Listas de reproducción**: cree una lista de reproducción compartida con un código corto para unirse (por ejemplo, `KORA-4821`); cualquiera que tenga el código puede escuchar y contribuir, como Spotify Blend enlaces.
- **Comunidad de noticias**: busca, transmite y descubre pistas cargadas por la comunidad.
- **Seguimiento de artistas**: sigue artistas/canales para realizar un seguimiento de ellos.
- **Cola inteligente y reproducción infinita**: cola automática con comportamiento claro inteligente.

### 🔐 Privacidad y cuentas
- **No se requiere cuenta**: los favoritos, las listas de reproducción y el historial se almacenan localmente de forma predeterminada.
- **Anónimo + Inicio de sesión de Google**: inicio de sesión opcional (identidad de dispositivo anónima o Google a través de Supabase Auth) para sincronización y perfil en la nube.
- **Descargas sin conexión**: descarga canciones y videos para escucharlos sin conexión.
- **Enlaces profundos**: esquema de URL personalizado completo para abrir/reproducir canciones, artistas, álbumes y listas de reproducción a través del navegador o enlaces compartidos.
- **Sin publicidad y confiable**: escucha ininterrumpida respaldada por relés abiertos (Last.fm, MusicBrainz, iTunes) para garantizar la reproducción.

---

## 🌐 Localización

Tunefy viene con **traducciones completas** en 14 idiomas (más el idioma automático del sistema):

| Idioma | Código | Idioma | Código |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Configure el idioma en **Configuración → Idioma** (o mantenga **Sistema** para la detección automática).

---

## 🏗️ Arquitectura

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

**Fiabilidad de reproducción.** La aplicación nunca depende de un solo proveedor. Sondea fuentes en un
cascada de prioridad (retransmisión local → retransmisión en la nube → espejos sin llave → búsqueda de metadatos/títulos), con un
disyuntor que salta una fuente que está fallando. La **retransmisión de nube** resuelve una transmisión y luego
**retransmite los bytes** a través de su propia conexión para que la resolución y la reproducción compartan una IP: esto es
lo que evita el 403 con IP bloqueada en los enlaces de vídeos de Google.

---

## 🛠️ Pila de tecnología

| Capa | Tecnología |
|---|---|
| **Marco** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestión del Estado** | [Riverpod](https://riverpod.dev/) |
| **Motor de audio** | [Just Audio](https://pub.dev/packages/just_audio) y [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Extracción** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (bifurcación por [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Letra** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + motor de karaoke personalizado + DeepL traducción |
| **Almacenamiento local** | [Hive](https://docs.hivedb.dev/) |
| **Sincronización/autenticación en la nube** | Supabase (Postgres + RLS, anónimo e inicio de sesión de Google) |
| **Redes** | [Dio](https://pub.dev/packages/dio) y [Http](https://pub.dev/packages/http) |
| **Retransmisión de transmisión** | FastAPI + yt-dlp en Render (`server/`) |
| **Componentes de la interfaz de usuario** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Configuración e instalación

### Requisitos previos
- Flutter SDK (Último estable)
- Dart SDK
- Android Studio / Código VS
- Java JDK 17

### Instalación

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Instalar dependencias:**
   ```bash
   flutter pub get
   ```

3. **Ejecute la aplicación:**
   ```bash
   flutter run
   ```

4. **Crear APK de lanzamiento** (dividido por ABI para un tamaño más pequeño):
   ```bash
   flutter build apk --split-per-abi
   ```

> La URL de retransmisión en la nube está integrada en `lib/utils/api_constants.dart`
> (`relayBaseUrl`), por lo que no se requiere ningún indicador de compilación. Para apuntar a su propio relevo:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Servidores backend y de streaming

### ☁️ Cloud Stream Relay — `server/` (implementado en Render)
Resuelve una URL de audio YouTube **y transmite los bytes** para que el teléfono y el solucionador compartan una IP
(nº 403). FastAPI + yt-dlp, Docker, nivel gratuito.

| Punto final | Descripción |
| --- | --- |
| `GET /health` | Sonda de vida (`ok`) |
| `GET /stream?videoId=X&key=K` | Se resuelve mediante yt-dlp → devuelve una URL `…/relay` (200 solo si se resuelve) |
| `GET /relay?videoId=X&key=K` | Representa los bytes de audio (consciente de rango → 206 para búsqueda) |

Protegido por una var de entorno `RELAY_KEY` compartida (devuelve **401** sin ella). Implementar: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Ver `server/README.md`.

### 🎵 API de aplicación — `backend/`
El backend de datos/búsqueda (YouTube Music a través de youtubei.js + fuentes abiertas: Last.fm géneros,
MusicBrainz lanzamientos y décadas).

| Punto final | Descripción |
| --- | --- |
| `/api/search` | Búsqueda de música/vídeo |
| `/api/trending` | Tendencias |
| `/api/charts` | Listas de música de YouTube |
| `/api/playlist/:id` | Detalle de la lista de reproducción |
| `/api/moods`, `/api/moods/:id` | Categorías y estados de ánimo (Last.fm respaldo) |
| `/api/tags?tag=` | Principales pistas/álbumes del género (Last.fm) |
| `/api/newreleases` | Nuevos lanzamientos (MusicBrainz) |
| `/api/decades?year=` | Álbumes por década (MusicBrainz) |
| `/api/categories` | Lista de categorías |

**Local:** `cd backend && npm install && npm start` (puerto 8000).
**Implementar (Vercel):** importar este repositorio, **Root Directory = `backend`**. Ver `backend/README.md`.

### 🗄️ Base de datos — `supabase/`
Postgres esquema con **Seguridad a nivel de fila**: las filas de usuario tienen como alcance `auth.uid()`, el catálogo es
Solo lectura para usuarios anónimos y escritura solo por parte del rol de servicio. Ejecute migraciones en el Supabase
Editor SQL (en orden).

---

## 🤝 Contribuyendo

¡Las contribuciones son bienvenidas! Ya sea para informar un error, sugerir una función o escribir código, agradecemos su ayuda.

1. **Bifurcar el proyecto**
2. **Crea tu rama de funciones** (`git checkout -b feature/AmazingFeature`)
3. **Confirma tus cambios** (`git commit -m 'Add some AmazingFeature'`)
4. **Empujar a la sucursal** (`git push origin feature/AmazingFeature`)
5. **Abrir una solicitud de extracción**

**Pautas:** siga el estilo de código existente, ejecute `flutter analyze` (debe estar limpio) y pruebe las nuevas funciones antes de enviarlas.

---

## 🙏 Agradecimientos

Tunefy no existiría sin el increíble trabajo de estos desarrolladores y proyectos.

### youtube_explode_dart
Gracias a**[Hexer10](https://github.com/Hexer10)**, autor original de
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) - la columna vertebral de Tunefy
YouTube streaming y**[anandnet](https://github.com/anandnet)** para la bifurcación actualizada que
sigue Tunefy funcionando con los últimos YouTube cambios.

### Animesh (n-ce) — fast-saavn & ytify
Un saludo a**[Animesh (n-ce)](https://github.com/n-ce)**, creador de
**[fast-saavn](https://github.com/n-ce/saavn)** (la API abierta de JioSaavn que alimenta los metadatos de Tunefy)
y**[ytify](https://github.com/n-ce/ytify)** (una gran fuente de inspiración).

### Bibliotecas de código abierto
| Paquete | Autor / Mantenedores |
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

## 📄 Licencia

Distribuido bajo la **Licencia MIT**. Consulte [`LICENSE`](LICENSE) para obtener más información.
