<p align="center">
  <img src="assets/logo.png" alt="Logotipo de Tunefy" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Un cliente de música potente y centrado en la privacidad creado con Flutter.</strong><br/>
  Sin anuncios · Sin conexión · DJ con IA · Letras sincronizadas y traducidas · Interfaz Liquid Glass · 15 fuentes · Sin cuenta requerida
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Versión" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Plataforma" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Idiomas" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Licencia" />
</p>

<p align="center">
  <a href="#-key-features">Funciones</a> ·
  <a href="#-localisation">Idiomas</a> ·
  <a href="#-screenshots">Capturas de pantalla</a> ·
  <a href="#-architecture">Arquitectura</a> ·
  <a href="#-setup--installation">Configuración</a> ·
  <a href="#-backend--streaming-servers">Servidores</a>
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

Tunefy es un cliente de música rico en funciones y centrado en la privacidad, creado con Flutter. Transmite desde
**más de 15 fuentes abiertas y sin clave de API** con una cascada de respaldo automática, de modo que una pista que
falla en un proveedor se reproduce en el siguiente. Ofrece una experiencia premium sin anuncios con reproducción en
segundo plano, descargas sin conexión, letras sincronizadas **y traducidas**, un **DJ con IA**, radio por internet,
conciertos, listas Blend compartidas, una moderna interfaz Liquid Glass y un caché inteligente en segundo plano —
con o sin cuenta.

> [!NOTE]
> Tunefy se distribuye directamente desde este repositorio (versiones APK). **No** está disponible
> en la Google Play Store.

---

## 🚀 Funciones Clave

### 🎨 Interfaz/UX Liquid Glass
- **Temas Glassmórficos Dinámicos** — Estilo premium en modos Oscuro y Claro mediante `liquid_glass_easy`. El modo Claro usa un tinte blanco semitransparente que se adapta a la carátula del álbum.
- **Shaders y Desenfoque Personalizados** — Paneles de vidrio esmerilado y superposiciones de alto rendimiento que se adaptan a los colores de la carátula.
- **Elementos Conscientes del Contraste** — Los iconos de la barra de estado, los controles, los controles deslizantes y los menús se invierten automáticamente para garantizar la legibilidad.
- **Optimización para Pantallas Grandes y Escritorio** — Diseños de reproductor responsivos (hasta 1300px), diálogos centrados y una barra de búsqueda superior dedicada para escritorio/tableta.

### 🎧 Audio Inmersivo, Letras y Karaoke
- **Karaoke Palabra por Palabra** — Las palabras se llenan de color en tiempo real mientras canta el artista (más de 60 FPS).
- **Barrido Sincronizado Línea por Línea** — Efecto de barrido progresivo con resaltado de la línea activa y desplazamiento suave.
- **Letras Traducidas** — Las letras se traducen automáticamente (DeepL) al idioma de la aplicación sobre la marcha.
- **Modo Lofi** — Convierte cualquier pista en una vibra Lofi: ralentizada 0.9×, corrección de tono, reverberación nativa.
- **Ecualizador y Efectos Nativos** — Ecualizador a nivel de sistema con reproducción en segundo plano y audio con la pantalla apagada.
- **Audio Multilingüe y Control de Calidad** — Detecta los idiomas de audio disponibles y transmite en calidad Alta/Media/Baja.

### 🤖 DJ con IA y Personalización
- **Asistente DJ con IA (Gemini)** — Un DJ conversacional que lee tus gustos, crea listas inteligentes y acepta peticiones.
- **Señales de Gusto** — La puntuación de gusto por pista aprende lo que te encanta y impulsa las recomendaciones.
- **Wrapped y Estadísticas de Escucha** — Tu resumen anual: artistas principales, estados de ánimo y cápsulas de escucha.
- **Sistema de Caché Inteligente** — Caché asíncrono en segundo plano de audio + carátulas multiresolución para una reproducción instantánea, sin esperas.

### 🌍 Descubrimiento en Más de 15 Fuentes
Tunefy resuelve la reproducción a través de una **cascada de respaldo automática** entre estos proveedores (sin clave = no se necesita clave de API):

| Fuente | Tipo | Notas |
|---|---|---|
| **YouTube / YT Music** | Vídeo / Audio | Principal, vía youtube_explode + API interna |
| **Jamendo** | Sin clave | Catálogo Creative Commons |
| **Deezer** | Sin clave | Catálogo + metadatos |
| **Audius** | Sin clave | Artistas descentralizados |
| **JioSaavn** | API abierta | Metadatos y búsqueda rápidos |
| **Invidious** | Sin clave | Réplica de YouTube (4 instancias) |
| **Piped** | API abierta | Réplica de YouTube |
| **OpenVerse** | Sin clave | Imágenes/audio CC *(nuevo)* |
| **Wikimedia Commons** | Sin clave | Medios abiertos *(nuevo)* |
| **Beatport** | Sin clave | Electrónica/dance *(nuevo)* |
| **Dailymotion** | Sin clave | Respaldo de vídeo *(nuevo)* |
| **ccMixter** | Sin clave | Cultura del remix *(nuevo)* |
| **Internet Archive** | Sin clave | Audio histórico *(nuevo)* |
| **Radio Browser** | Sin clave | Emisoras de radio por internet |
| **iTunes / MusicBrainz / Last.fm** | Abierta | Metadatos, listas, géneros |

- **Cloud Stream Relay** — Un relé autoalojado resuelve y **hace proxy de los bytes de audio** desde la misma IP que usa el reproductor, evitando el error HTTP 403 que de otro modo devolverían los enlaces de Googlevideo bloqueados por IP. Ver [Servers](#-backend--streaming-servers).
- **Importación de Spotify** — Pega la URL de cualquier lista pública de Spotify (o escanea un código de Spotify) para importar pistas.
- **Búsqueda Global** — Una única búsqueda en canciones, vídeos, álbumes, artistas y pódcasts.
- **Compartir para Reproducir** — Comparte enlaces de YouTube/YT Music directamente en Tunefy.

### 📻 Radio, Conciertos y Vídeo
- **Radio por Internet** — Miles de emisoras en directo (Radio Browser).
- **Conciertos** — Descubre eventos en directo cerca de ti con páginas de detalle completas.
- **Feed de Clips** — Feed vertical de vídeos cortos con clips de la comunidad y en tendencia.
- **Reproductor de Vídeo** — Reproducción completa de vídeo con fondos de vídeo en lienzo.
- **Mezclas DJ** — Descubrimiento y reproducción dedicados de mezclas de DJ.

### 🤝 Social, Blends y Comunidad
- **Listas Blend** — Crea una lista compartida con un código de unión corto (p. ej. `KORA-4821`); cualquier persona con el código puede escuchar y contribuir, como los enlaces Blend de Spotify.
- **Feed de la Comunidad** — Busca, transmite y descubre pistas subidas por la comunidad.
- **Seguimiento de Artistas** — Sigue artistas/canales para mantenerte al tanto.
- **Cola Inteligente y Reproducción Infinita** — Cola automática con un comportamiento de limpieza inteligente.

### 🔐 Privacidad y Cuentas
- **Sin Cuenta Obligatoria** — Favoritos, listas e historial se almacenan localmente de forma predeterminada.
- **Anónimo + Inicio de Sesión con Google** — Inicio de sesión opcional (identidad anónima del dispositivo o Google mediante Supabase Auth) para la sincronización en la nube y el perfil.
- **Descargas sin Conexión** — Descarga canciones y vídeos para escucharlos sin conexión.
- **Deep Linking** — Esquema de URL personalizado completo para abrir/reproducir canciones, artistas, álbumes y listas mediante el navegador o enlaces compartidos.
- **Sin Anuncios y Fiable** — Escucha ininterrumpida respaldada por relés abiertos (Last.fm, MusicBrainz, iTunes) para garantizar la reproducción.

---

## 🌐 Localización

Tunefy se entrega con **traducciones completas** en 14 idiomas (más el idioma del sistema automáticamente):

| Idioma | Código | Idioma | Código |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Configura el idioma en **Ajustes → Idioma** (o deja **Sistema** para la detección automática).

---

## 📸 Capturas de Pantalla

### 🏠 Inicio y Navegación
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Pantalla de inicio" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Inicio con mini reproductor" />
  <img src="images/library.jpg" width="30%" alt="Biblioteca" />
</p>

### 🔍 Búsqueda
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Resultados de búsqueda" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Sugerencias de búsqueda" />
</p>

### 🎵 Reproductor
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Reproductor inmersivo" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Reproductor clásico" />
  <img src="images/song_queue.jpg" width="30%" alt="Cola de canciones" />
</p>

### 🎤 Letras
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Letras con controles" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Letras sin controles" />
</p>

### 👥 Comunidad y Perfil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Feed de la comunidad" />
  <img src="images/profile_screen.jpg" width="30%" alt="Pantalla de perfil" />
</p>

### ⚙️ Ajustes y Personalización
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Ajustes" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Selector de tema" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Color de acento" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Color de acento personalizado" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Selector de idioma" />
</p>

### ℹ️ Acerca de
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Pantalla Acerca de" />
</p>

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

**Fiabilidad de reproducción.** La aplicación nunca depende de un solo proveedor. Sondea las fuentes en una
cascada de prioridad (relé local → relé en la nube → réplicas sin clave → búsqueda por metadatos/título), con un
interruptor que omite una fuente que esté fallando. El **relé en la nube** resuelve un flujo y luego
**reenvía los bytes** a través de su propia conexión, de modo que la resolución y la reproducción comparten una
misma IP — esto es lo que evita el 403 bloqueado por IP en los enlaces de Googlevideo.

---

## 🛠️ Stack Tecnológico

| Capa | Tecnología |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestión de Estado** | [Riverpod](https://riverpod.dev/) |
| **Motor de Audio** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **Extracción de YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork de [anandnet](https://github.com/anandnet)) |
| **DJ con IA** | Google Gemini (`gemini_service`) |
| **Letras** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + motor de karaoke personalizado + traducción DeepL |
| **Almacenamiento Local** | [Hive](https://docs.hivedb.dev/) |
| **Sincronización en la Nube / Autenticación** | Supabase (Postgres + RLS, inicio de sesión anónimo y con Google) |
| **Redes** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relé de Stream** | FastAPI + yt-dlp en Render (`server/`) |
| **Componentes de UI** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Configuración e Instalación

### Requisitos Previos
- Flutter SDK (Última versión estable)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Instalación

1. **Clona el repositorio:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Instala las dependencias:**
   ```bash
   flutter pub get
   ```

3. **Ejecuta la aplicación:**
   ```bash
   flutter run
   ```

4. **Compila el APK de la versión** (dividido por ABI para reducir el tamaño):
   ```bash
   flutter build apk --split-per-abi
   ```

> La URL del relé en la nube está incrustada en `lib/utils/api_constants.dart`
> (`relayBaseUrl`), por lo que no se necesita ninguna bandera de compilación. Para apuntar a tu propio relé:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend y Servidores de Streaming

### ☁️ Relé de Stream en la Nuvem — `server/` (desplegado en Render)
Resuelve una URL de audio de YouTube **y reenvía los bytes** para que el teléfono y el resolvedor compartan una
misma IP (sin 403). FastAPI + yt-dlp, Docker, plan gratuito.

| Endpoint | Descripción |
| --- | --- |
| `GET /health` | Sonda de actividad (`ok`) |
| `GET /stream?videoId=X&key=K` | Resuelve mediante yt-dlp → devuelve una URL `…/relay` (200 solo si se resuelve) |
| `GET /relay?videoId=X&key=K` | Hace proxy de los bytes de audio (compatible con Range → 206 para el desplazamiento) |

Protegido por una variable de entorno compartida `RELAY_KEY` (devuelve **401** sin ella). Despliegue: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Ver `server/README.md`.

### 🎵 API de la Aplicación — `backend/`
El backend de datos/búsqueda (YouTube Music mediante youtubei.js + fuentes abertas: géneros de Last.fm,
lanzamientos y décadas de MusicBrainz).

| Endpoint | Descripción |
| --- | --- |
| `/api/search` | Búsqueda de música/vídeo |
| `/api/trending` | Tendencias |
| `/api/charts` | Listas de YT Music |
| `/api/playlist/:id` | Detalle de la lista |
| `/api/moods`, `/api/moods/:id` | Categorías y estados de ánimo (respaldo de Last.fm) |
| `/api/tags?tag=` | Mejores pistas/álbumes por género (Last.fm) |
| `/api/newreleases` | Nuevos lanzamientos (MusicBrainz) |
| `/api/decades?year=` | Álbumes por década (MusicBrainz) |
| `/api/categories` | Lista de categorías |

**Local:** `cd backend && npm install && npm start` (puerto 8000).
**Despliegue (Vercel):** importa este repositorio, **Root Directory = `backend`**. Ver `backend/README.md`.

### 🗄️ Base de Datos — `supabase/`
Esquema de Postgres con **Seguridad a Nivel de Fila**: las filas de usuario están limitadas a `auth.uid()`, el
catálogo es de solo lectura para los usuarios anónimos y solo el rol de servicio puede escribir en él. Ejecuta las
migraciones en el Editor SQL de Supabase (en orden).

---

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas! Ya sea informar de un error, sugerir una función o escribir código, tu ayuda es
apreciada.

1. **Haz un fork del Proyecto**
2. **Crea tu Rama de Funcionalidad** (`git checkout -b feature/AmazingFeature`)
3. **Confirma tus Cambios** (`git commit -m 'Add some AmazingFeature'`)
4. **Sube a la Rama** (`git push origin feature/AmazingFeature`)
5. **Abre una Pull Request**

**Directrices:** sigue el estilo de código existente, ejecuta `flutter analyze` (debe estar limpio) y prueba las
nuevas funciones antes de enviarlas.

---

## 🙏 Agradecimientos

Tunefy no existiría sin el increíble trabajo de estos desarrolladores y proyectos.

### youtube_explode_dart
Gracias a **[Hexer10](https://github.com/Hexer10)**, autor original de
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — la columna vertebral del streaming de
YouTube de Tunefy — y a **[anandnet](https://github.com/anandnet)** por el fork actualizado que
mantiene a Tunefy funcionando con los últimos cambios de YouTube.

### Animesh (n-ce) — fast-saavn & ytify
Mención a **[Animesh (n-ce)](https://github.com/n-ce)**, creador de
**[fast-saavn](https://github.com/n-ce/saavn)** (la API abierta de JioSaavn que impulsa los metadatos de Tunefy)
y **[ytify](https://github.com/n-ce/ytify)** (una enorme fuente de inspiración).

### Bibliotecas de Código Abierto
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

Distribuido bajo la **Licencia MIT**. Consulta [`LICENSE`](LICENSE) para más información.
