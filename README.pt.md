<p align="center">
  <img src="assets/logo.png" alt="Logótipo do Tunefy" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
  <strong>Um cliente de música poderoso e focado na privacidade, criado com Flutter.</strong><br/>
  Sem anúncios · Offline · DJ com IA · Letras sincronizadas e traduzidas · Interface Liquid Glass · 15 fontes · Sem necessidade de conta
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Version-3.9.0-brightgreen" alt="Versão" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Windows-lightgrey" alt="Plataforma" />
  <img src="https://img.shields.io/badge/Languages-14-orange" alt="Idiomas" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="Licença" />
</p>

<p align="center">
  <a href="#-key-features">Funcionalidades</a> ·
  <a href="#-localisation">Idiomas</a> ·
  <a href="#-screenshots">Capturas de ecrã</a> ·
  <a href="#-architecture">Arquitetura</a> ·
  <a href="#-setup--installation">Configuração</a> ·
  <a href="#-backend--streaming-servers">Servidores</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.fo.md">Fongbé</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <b>Português</b> ·
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

O Tunefy é um cliente de música repleto de funcionalidades e focado na privacidade, criado com Flutter. Transmite a
partir de **mais de 15 fontes abertas e sem chave de API** com uma cascata de fallback automática, de modo que uma
faixa que falha num fornecedor toca no seguinte. Oferece uma experiência premium sem anúncios com reprodução em
segundo plano, downloads offline, letras sincronizadas **e traduzidas**, um **DJ com IA**, rádio internet,
concertos, listas Blend partilhadas, uma moderna interface Liquid Glass e cache inteligente em segundo plano —
com ou sem conta.

> [!NOTE]
> O Tunefy é distribuído diretamente a partir deste repositório (lançamentos APK). **Não** está
> disponível na Google Play Store.

---

## 🚀 Funcionalidades Principais

### 🎨 Interface/UX Liquid Glass
- **Temas Glassmórficos Dinâmicos** — Aparência premium nos modos Escuro e Claro através de `liquid_glass_easy`. O modo Claro usa um tom branco semitransparente que se adapta à capa do álbum.
- **Shaders e Desfoque Personalizados** — Painéis de vidro fosco e sobreposições de alto desempenho que se adaptam às cores da capa.
- **Elementos Sensíveis ao Contraste** — Ícones da barra de estado, controlos, controlos deslizantes e menus invertem-se automaticamente para melhor legibilidade.
- **Otimização para Ecrãs Grandes e Ambiente Desktop** — Layouts de leitor responsivos (até 1300px), diálogos centrados e uma barra de pesquisa superior dedicada para desktop/tablet.

### 🎧 Áudio Imersivo, Letras e Karaokê
- **Karaokê Palavra a Palavra** — As palavras são preenchidas a cores em tempo real enquanto o artista canta (60+ FPS).
- **Varredura Sincronizada Linha a Linha** — Efeito de varredura progressivo com destaque da linha ativa e deslocação suave.
- **Letras Traduzidas** — As letras são traduzidas automaticamente (DeepL) para o idioma da aplicação em tempo real.
- **Modo Lofi** — Transforme qualquer faixa num ambiente Lofi: desacelerada 0.9×, correção de tom, reverberação nativa.
- **Equalizador e Efeitos Nativos** — EQ ao nível do sistema com reprodução em segundo plano e áudio com o ecrã desligado.
- **Áudio Multilíngue e Controlo de Qualidade** — Deteta os áudios disponíveis e transmite em qualidade Alta/Média/Baixa.

### 🤖 DJ com IA e Personalização
- **Assistente DJ com IA (Gemini)** — Um DJ conversacional que lê os seus gostos, cria listas inteligentes e aceita pedidos.
- **Sinais de Gosto** — A pontuação de gosto por faixa aprende o que adora e impulsiona as recomendações.
- **Wrapped e Estatísticas de Escuta** — O seu resumo anual: artistas em destaque, estados de espírito e cápsulas de escuta.
- **Sistema de Cache Inteligente** — Cache assíncrona em segundo plano de áudio + capas multirresolução para uma reprodução instantânea, sem espera.

### 🌍 Descoberta em Mais de 15 Fontes
O Tunefy resolve a reprodução através de uma **cascata de fallback automática** junto destes fornecedores (sem chave = não é necessária chave de API):

| Fonte | Tipo | Notas |
|---|---|---|
| **YouTube / YT Music** | Vídeo / Áudio | Principal, através do youtube_explode + API interna |
| **Jamendo** | Sem chave | Catálogo Creative Commons |
| **Deezer** | Sem chave | Catálogo + metadados |
| **Audius** | Sem chave | Artistas descentralizados |
| **JioSaavn** | API aberta | Metadatos e pesquisa rápidos |
| **Invidious** | Sem chave | Espelho do YouTube (4 instâncias) |
| **Piped** | API aberta | Espelho do YouTube |
| **OpenVerse** | Sem chave | Imagens/áudio CC *(novidade)* |
| **Wikimedia Commons** | Sem chave | Media aberto *(novidade)* |
| **Beatport** | Sem chave | Música eletrónica/dance *(novidade)* |
| **Dailymotion** | Sem chave | Fallback de vídeo *(novidade)* |
| **ccMixter** | Sem chave | Cultura do remix *(novidade)* |
| **Internet Archive** | Sem chave | Áudio histórico *(novidade)* |
| **Radio Browser** | Sem chave | Estações de rádio internet |
| **iTunes / MusicBrainz / Last.fm** | Aberta | Metadatos, charts, géneros |

- **Cloud Stream Relay** — Um relé auto-hospedado resolve e **faz proxy dos bytes de áudio** a partir do mesmo IP que o leitor usa, evitando o erro HTTP 403 que os links do Googlevideo bloqueados por IP devolveriam de outra forma. Ver [Servers](#-backend--streaming-servers).
- **Importação do Spotify** — Cole o URL de qualquer lista pública do Spotify (ou escaneie um código do Spotify) para importar faixas.
- **Pesquisa Global** — Uma única pesquisa em músicas, vídeos, álbuns, artistas e podcasts.
- **Partilhar para Reproduzir** — Partilhe links do YouTube/YT Music diretamente no Tunefy.

### 📻 Rádio, Concertos e Vídeo
- **Rádio Internet** — Milhares de emissoras em direto (Radio Browser).
- **Concertos** — Descubra eventos ao vivo perto de si com páginas de detalhe ricas.
- **Feed de Clips** — Feed vertical de vídeos curtos com clips da comunidade e em tendência.
- **Leitor de Vídeo** — Reprodução completa de vídeo com fundos de vídeo em canvas.
- **Mixes DJ** — Descoberta e reprodução dedicadas de mixes de DJ.

### 🤝 Social, Blends e Comunidade
- **Listas Blend** — Crie uma lista partilhada com um código de entrada curto (ex.: `KORA-4821`); qualquer pessoa com o código pode ouvir e contribuir, como os links Blend do Spotify.
- **Feed da Comunidade** — Pesquise, transmita e descubra faixas enviadas pela comunidade.
- **Seguição de Artistas** — Siga artistas/canais para se manter a par.
- **Fila Inteligente e Reprodução Infinita** — Fila automática com comportamento inteligente de limpeza.

### 🔐 Privacidade e Contas
- **Sem Necessidade de Conta** — Favoritos, listas e histórico são armazenados localmente por predefinição.
- **Anónimo + Início de Sessão com Google** — Início de sessão opcional (identidade anónima do dispositivo ou Google através do Supabase Auth) para sincronização na nuvem e perfil.
- **Downloads Offline** — Descarregue músicas e vídeos para ouvir offline.
- **Deep Linking** — Esquema de URL personalizado completo para abrir/reproduzir músicas, artistas, álbuns e listas através do navegador ou de links partilhados.
- **Sem Anúncios e Fiável** — Escuta ininterrupta suportada por relés abertos (Last.fm, MusicBrainz, iTunes) para garantir a reprodução.

---

## 🌐 Localização

O Tunefy é fornecido com **traduções completas** em 14 idiomas (mais o idioma do sistema automaticamente):

| Idioma | Código | Idioma | Código |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Defina o idioma em **Definições → Idioma** (ou mantenha **Sistema** para deteção automática).

---

## 📸 Capturas de Ecrã

### 🏠 Início e Navegação
<p align="center">
  <img src="images/home.jpg" width="30%" alt="Ecrã inicial" />
  <img src="images/home_with_miniplayer.jpg" width="30%" alt="Início com mini leitor" />
  <img src="images/library.jpg" width="30%" alt="Biblioteca" />
</p>

### 🔍 Pesquisa
<p align="center">
  <img src="images/search_with _results.jpg" width="30%" alt="Resultados de pesquisa" />
  <img src="images/search_with _search_suggestions.jpg" width="30%" alt="Sugestões de pesquisa" />
</p>

### 🎵 Leitor
<p align="center">
  <img src="images/Immersive_player.jpg" width="30%" alt="Leitor imersivo" />
  <img src="images/leagcy_player.jpg" width="30%" alt="Leitor clássico" />
  <img src="images/song_queue.jpg" width="30%" alt="Fila de músicas" />
</p>

### 🎤 Letras
<p align="center">
  <img src="images/lyrics_with_controls.jpg" width="30%" alt="Letras com controlos" />
  <img src="images/lyrics_without_controls.jpg" width="30%" alt="Letras sem controlos" />
</p>

### 👥 Comunidade e Perfil
<p align="center">
  <img src="images/community.jpg" width="30%" alt="Feed da comunidade" />
  <img src="images/profile_screen.jpg" width="30%" alt="Ecrã de perfil" />
</p>

### ⚙️ Definições e Personalização
<p align="center">
  <img src="images/settings.jpg" width="30%" alt="Definições" />
  <img src="images/app_theme_selector.jpg" width="30%" alt="Seletor de tema" />
  <img src="images/accent_color_selector.jpg" width="30%" alt="Cor de destaque" />
  <img src="images/custom_accent_color_selector.jpg" width="30%" alt="Cor de destaque personalizada" />
  <img src="images/app_language_selector.jpg" width="30%" alt="Seletor de idioma" />
</p>

### ℹ️ Acerca
<p align="center">
  <img src="images/about_screen.jpg" width="30%" alt="Ecrã Acerca de" />
</p>

---

## 🏗️ Arquitetura

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

**Fiabilidade da reprodução.** A aplicação nunca depende de um único fornecedor. Sonda as fontes numa cascata de
prioridade (relé local → relé na nuvem → espelhos sem chave → pesquisa por metadatos/título), com um disjutor que
ignora uma fonte que esteja a falhar. O **relé na nuvem** resolve um stream e depois **encaminha os bytes** através
da sua própria conexão, de modo que a resolução e a reprodução partilham um IP — é isto que evita o 403 bloqueado
por IP nos links do Googlevideo.

---

## 🛠️ Stack Tecnológico

| Camada | Tecnologia |
|---|---|
| **Framework** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestão de Estado** | [Riverpod](https://riverpod.dev/) |
| **Motor de Áudio** | [Just Audio](https://pub.dev/packages/just_audio) & [Audio Service](https://pub.dev/packages/audio_service) |
| **Extração do YouTube** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (fork de [anandnet](https://github.com/anandnet)) |
| **DJ com IA** | Google Gemini (`gemini_service`) |
| **Letras** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + motor de karaokê personalizado + tradução DeepL |
| **Armazenamento Local** | [Hive](https://docs.hivedb.dev/) |
| **Sincronização na Nuvem / Autenticação** | Supabase (Postgres + RLS, início de sessão anónimo e com Google) |
| **Redes** | [Dio](https://pub.dev/packages/dio) & [Http](https://pub.dev/packages/http) |
| **Relé de Stream** | FastAPI + yt-dlp no Render (`server/`) |
| **Componentes de UI** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Configuração e Instalação

### Pré-requisitos
- Flutter SDK (última versão estável)
- Dart SDK
- Android Studio / VS Code
- Java JDK 17

### Instalação

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Instale as dependências:**
   ```bash
   flutter pub get
   ```

3. **Execute a aplicação:**
   ```bash
   flutter run
   ```

4. **Construa o APK de release** (dividido por ABI para menor tamanho):
   ```bash
   flutter build apk --split-per-abi
   ```

> O URL do relé na nuvem está embutido em `lib/utils/api_constants.dart`
> (`relayBaseUrl`), pelo que não é necessária nenhuma flag de build. Para apontar para o seu próprio relé:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Backend e Servidores de Streaming

### ☁️ Relé de Stream na Nuvem — `server/` (implementado no Render)
Resolve um URL de áudio do YouTube **e encaminha os bytes** para que o telemóvel e o resolvedor partilhem um IP
(sem 403). FastAPI + yt-dlp, Docker, plano gratuito.

| Endpoint | Descrição |
| --- | --- |
| `GET /health` | Sonda de atividade (`ok`) |
| `GET /stream?videoId=X&key=K` | Resolve através do yt-dlp → devolve um URL `…/relay` (200 apenas se resolver) |
| `GET /relay?videoId=X&key=K` | Faz proxy dos bytes de áudio (compatível com Range → 206 para navegação) |

Protegido por uma variável de ambiente partilhada `RELAY_KEY` (devolve **401** sem ela). Implementação: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Ver `server/README.md`.

### 🎵 API da Aplicação — `backend/`
O backend de dados/pesquisa (YouTube Music através do youtubei.js + fontes abertas: géneros do Last.fm,
lançamentos e décadas do MusicBrainz).

| Endpoint | Descrição |
| --- | --- |
| `/api/search` | Pesquisa de música/vídeo |
| `/api/trending` | Em alta |
| `/api/charts` | Charts do YT Music |
| `/api/playlist/:id` | Detalhe da lista |
| `/api/moods`, `/api/moods/:id` | Categorias e estados de espírito (fallback do Last.fm) |
| `/api/tags?tag=` | Melhores faixas/álbuns por género (Last.fm) |
| `/api/newreleases` | Novos lançamentos (MusicBrainz) |
| `/api/decades?year=` | Álbuns por década (MusicBrainz) |
| `/api/categories` | Lista de categorias |

**Local:** `cd backend && npm install && npm start` (porta 8000).
**Implementação (Vercel):** importe este repositório, **Root Directory = `backend`**. Ver `backend/README.md`.

### 🗄️ Base de Dados — `supabase/`
Esquema Postgres com **Segurança ao Nível da Linha**: as linhas do utilizador são limitadas a `auth.uid()`, o
catálogo é apenas de leitura para utilizadores anónimos e só pode ser escrito pelo papel de serviço. Execute as
migrações no Editor SQL do Supabase (por ordem).

---

## 🤝 Contribuições

As contribuições são bem-vindas! Seja a reportar um bug, sugerir uma funcionalidade ou escrever código, a sua ajuda
é apreciada.

1. **Faça Fork do Projeto**
2. **Crie o seu Branch de Funcionalidade** (`git checkout -b feature/AmazingFeature`)
3. **Faça Commit das suas Alterações** (`git commit -m 'Add some AmazingFeature'`)
4. **Faça Push para o Branch** (`git push origin feature/AmazingFeature`)
5. **Abra um Pull Request**

**Diretrizes:** siga o estilo de código existente, execute `flutter analyze` (tem de estar limpo) e teste as novas
funcionalidades antes de submeter.

---

## 🙏 Agradecimentos

O Tunefy não existiria sem o trabalho incrível destes programadores e projetos.

### youtube_explode_dart
Obrigado a **[Hexer10](https://github.com/Hexer10)**, autor original do
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — a espinha dorsal da transmissão do
YouTube do Tunefy — e a **[anandnet](https://github.com/anandnet)** pelo fork atualizado que
mantém o Tunefy a funcionar com as últimas mudanças do YouTube.

### Animesh (n-ce) — fast-saavn & ytify
Menção a **[Animesh (n-ce)](https://github.com/n-ce)**, criador do
**[fast-saavn](https://github.com/n-ce/saavn)** (a API aberta do JioSaavn que fornece os metadados do Tunefy)
e do **[ytify](https://github.com/n-ce/ytify)** (uma enorme fonte de inspiração).

### Bibliotecas de Código Aberto
| Pacote | Autor / Responsáveis |
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

## 📄 Licença

Distribuído sob a **Licença MIT**. Veja [`LICENSE`](LICENSE) para mais informações.
