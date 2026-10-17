<p align="center">
  <img src="assets/logo.png" alt="Tunefy Logo" width="150" height="150" />
</p>

<h1 align="center">Tunefy</h1>

<p align="center">
<strong>Um cliente de música poderoso e focado na privacidade, desenvolvido com Flutter.</strong><br/>
  Sem anúncios · Off-line · AI DJ · Letras sincronizadas e traduzidas · Liquid Glass UI · 15 fontes · Não é necessária conta
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
  <a href="#-principais-recursos">Recursos</a> ·
  <a href="#-localização">Idiomas</a> ·
  <a href="#-arquitetura">Arquitetura</a> ·
  <a href="#-configuração-e-instalação">Configuração</a> ·
  <a href="#-servidores-de-back-end-e-streaming">Servidores</a>
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

Tunefy é um cliente de música rico em recursos e com foco na privacidade, desenvolvido com Flutter. Ele flui de
**Mais de 15 fontes abertas e sem chave** com uma cascata de fallback automática, portanto, uma faixa que falha em uma
provedor joga no próximo. Oferece uma experiência premium sem anúncios com reprodução em segundo plano,
downloads off-line, letras sincronizadas **e traduzidas**, um **AI DJ**, rádio na Internet, shows,
listas de reprodução Blend compartilhadas, uma interface de usuário Liquid Glass moderna e cache em segundo plano inteligente — com ou sem
uma conta.

> [!NOTE]
> Tunefy é distribuído diretamente deste repositório (lançamentos de APK). **não** disponível
> no Google Play Store.

---

## 🚀 Principais recursos

### 🎨 Liquid Glass UI/UX
- **Temas Glassmorphic Dinâmicos** — Estilo premium nos modos Escuro e Claro até `liquid_glass_easy`. O Modo Claro usa uma tonalidade branca semitransparente que se adapta à capa do álbum.
- **Sombreadores e desfoque personalizados** — Painéis de vidro fosco de alto desempenho e sobreposições que se adaptam às cores da arte.
- **Elementos sensíveis ao contraste** — Ícones da barra de status, controles, controles deslizantes e menus são invertidos automaticamente para maior legibilidade.
- **Otimização de tela grande e desktop** — Layouts de player responsivos (até 1300px), caixas de diálogo centralizadas e uma barra de pesquisa superior dedicada para desktop/tablet.

### 🎧 Áudio, letras e karaokê envolventes
- **Karaokê palavra por palavra** — As palavras são preenchidas com cores em tempo real enquanto o artista canta (mais de 60 FPS).
- **Varredura sincronizada linha por linha** — Efeito de varredura progressiva com destaque de linha ativa e rolagem suave.
- **Letras traduzidas** — As letras são traduzidas automaticamente (DeepL) para o idioma do seu aplicativo instantaneamente.
- **Modo Lofi** — Transforme qualquer faixa em uma vibração Lofi: desaceleração de 0,9×, correção de tom, reverberação nativa.
- **Equalizador e efeitos nativos** — EQ de nível de sistema com reprodução em segundo plano e áudio com tela desligada.
- **Áudio multilíngue e controle de qualidade** — Detecte idiomas de áudio disponíveis e transmita qualidade alta/média/baixa.

### 🤖 AI DJ e personalização
- **AI DJ Assistant (Gemini)** — Um DJ conversacional que lê seu gosto, cria playlists inteligentes e atende solicitações.
- **Sinais de sabor** — A pontuação de sabor por faixa aprende o que você adora e gera recomendações.
- **Wrapped e estatísticas de audição** — Sua análise do ano: principais artistas, humores e cápsulas de audição.
- **Sistema de Cache Inteligente** — Cache assíncrono em segundo plano de áudio + arte em multi-resolução para reprodução instantânea e sem espera.

### 🌍 Descoberta em mais de 15 fontes
Tunefy resolve a reprodução por meio de uma **cascata de fallback automática** entre esses provedores (sem chave = nenhuma chave de API necessária):

| Fonte | Tipo | Notas |
|---|---|---|
| **YouTube / YT Música** | Vídeo / Áudio | Primário, via youtube_explode + API interna |
| **Jamendo** | Sem chave | Catálogo Creative Commons |
| **Deezer** | Sem chave | Catálogo + metadados |
| **Audius** | Sem chave | Artistas descentralizados |
| **JioSaavn** | API aberta | Metadados e pesquisa rápida |
| **Invidious** | Sem chave | YouTube espelho (4 instâncias) |
| **Piped** | API aberta | YouTube espelho |
| **OpenVerse** | Sem chave | Imagens/áudio CC *(novo)* |
| **Wikimedia Commons** | Sem chave | Mídia aberta *(novo)* |
| **Beatport** | Sem chave | Eletrônica/dança *(novo)* |
| **Dailymotion** | Sem chave | Substituição de vídeo *(novo)* |
| **ccMixter** | Sem chave | Cultura remix *(nova)* |
| **Internet Archive** | Sem chave | Áudio histórico *(novo)* |
| **Radio Browser** | Sem chave | Estações de rádio na Internet |
| **iTunes / MusicBrainz / Last.fm** | Abrir | Metadados, gráficos, gêneros |

- **Cloud Stream Relay** — Uma retransmissão auto-hospedada resolve e **faz proxy dos bytes de áudio** do mesmo IP que o player usa, evitando o HTTP 403 que os links do Googlevideo bloqueados por IP retornam. Consulte [Servers](#-servidores-de-back-end-e-streaming).
- **Spotify Importar** — Cole qualquer URL da lista de reprodução Spotify pública (ou escaneie um código Spotify) para importar faixas.
- **Pesquisa global** — Uma pesquisa em músicas, vídeos, álbuns, artistas e podcasts.
- **Compartilhar para reproduzir** — Compartilhe links de YouTube/YT Music diretamente em Tunefy.

### 📻 Rádio, shows e vídeo
- **Rádio na Internet** — Milhares de estações ao vivo (Radio Browser).
- **Concertos** — Descubra eventos ao vivo perto de você com páginas ricas em detalhes.
- **Feed de clipes** — Feed vertical de vídeos curtos de clipes da comunidade e de tendências.
- **Reprodutor de vídeo** — Reprodução completa de vídeo com fundos de vídeo em tela.
- **DJ Mixes** — Descoberta e reprodução dedicada de DJ/mix.

### 🤝 Social, Misturas e Comunidade
- **Blend Playlists** — Crie uma playlist compartilhada com um código de adesão curto (por exemplo, `KORA-4821`); qualquer pessoa com o código pode ouvir e contribuir, como links Spotify Blend.
- **Feed da comunidade** — Pesquise, transmita e descubra faixas enviadas pela comunidade.
- **Artist Following** — Siga artistas/canais para acompanhá-los.
- **Fila inteligente e reprodução infinita** — Enfileiramento automático com comportamento claro e inteligente.

### 🔐 Privacidade e contas
- **Não é necessária nenhuma conta** — Favoritos, listas de reprodução e histórico são armazenados localmente por padrão.
- **Anônimo + Login do Google** — Login opcional (identidade anônima do dispositivo ou Google via Supabase Auth) para sincronização na nuvem e perfil.
- **Downloads off-line** — Baixe músicas e vídeos para ouvir off-line.
- **Deep Linking** — Esquema de URL totalmente personalizado para abrir/reproduzir músicas, artistas, álbuns e playlists via navegador ou links compartilhados.
- **Sem anúncios e confiável** — Audição ininterrupta apoiada por relés abertos (Last.fm, MusicBrainz, iTunes) para garantir a reprodução.

---

## 🌐 Localização

Tunefy vem com **traduções completas** em 14 idiomas (mais idioma do sistema automático):

| Idioma | Código | Idioma | Código |
| :--- | :---: | :--- | :---: |
| 🇬🇧 English | `en` | 🇷🇺 Русский | `ru` |
| 🇫🇷 Français | `fr` | 🇸🇦 العربية | `ar` |
| 🇧🇯 Fongbé | `fo` | 🇮🇳 हिन्दी | `hi` |
| 🇪🇸 Español | `es` | 🇮🇩 Bahasa Indonesia | `id` |
| 🇩🇪 Deutsch | `de` | 🇻🇳 Tiếng Việt | `vi` |
| 🇵🇹 Português | `pt` | 🇹🇷 Türkçe | `tr` |
| 🇮🇹 Italiano | `it` | 🇨🇳 中文（简体）| `zh` |

Defina o idioma em **Configurações → Idioma** (ou mantenha **Sistema** para detecção automática).

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

**Confiabilidade de reprodução.** O aplicativo nunca depende de um único fornecedor. Ele investiga fontes em um
cascata de prioridade (retransmissão local → retransmissão em nuvem → espelhos sem chave → pesquisa de metadados/título), com um
disjuntor que ignora uma fonte que está falhando. A **transmissão em nuvem** resolve um stream e, em seguida,
**retransmite os bytes** através de sua própria conexão para que a resolução e a reprodução compartilhem um IP — este é
o que evita o 403 bloqueado por IP nos links do Googlevideo.

---

## 🛠️ Pilha de tecnologia

| Camada | Tecnologia |
|---|---|
| **Estrutura** | [Flutter](https://flutter.dev/) + [Dart](https://dart.dev/) |
| **Gestão Estadual** | [Riverpod](https://riverpod.dev/) |
| **Mecanismo de áudio** | [Just Audio](https://pub.dev/packages/just_audio) e [Audio Service](https://pub.dev/packages/audio_service) |
| **YouTube Extração** | [youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) (garfo por [anandnet](https://github.com/anandnet)) |
| **AI DJ** | Google Gemini (`gemini_service`) |
| **Letra** | [flutter_lyric](https://pub.dev/packages/flutter_lyric) + mecanismo de karaokê personalizado + DeepL tradução |
| **Armazenamento local** | [Hive](https://docs.hivedb.dev/) |
| **Sincronização/autenticação na nuvem** | Supabase (Postgres + RLS, anônimo e login do Google) |
| **Rede** | [Dio](https://pub.dev/packages/dio) e [Http](https://pub.dev/packages/http) |
| **Retransmissão de fluxo** | FastAPI + yt-dlp em Render (`server/`) |
| **Componentes da IU** | `liquid_glass_easy`, [FluentUI System Icons](https://pub.dev/packages/fluentui_system_icons), [Google Fonts](https://pub.dev/packages/google_fonts), [Cached Network Image](https://pub.dev/packages/cached_network_image) |

---

## ⚙️ Configuração e instalação

### Pré-requisitos
- Flutter SDK (último estável)
- Dart SDK
- Android Studio / Código VS
- Java JDK 17

### Instalação

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/grandelagbanou28-gif/tunefy-music.git
   cd tunefy-music
   ```

2. **Instalar dependências:**
   ```bash
   flutter pub get
   ```

3. **Execute o aplicativo:**
   ```bash
   flutter run
   ```

4. **Compilação do APK de lançamento** (dividido por ABI para tamanho menor):
   ```bash
   flutter build apk --split-per-abi
   ```

> O URL de retransmissão em nuvem está inserido em `lib/utils/api_constants.dart`
> (`relayBaseUrl`), portanto, nenhum sinalizador de construção é necessário. Para apontar para seu próprio relé:
> `flutter run --dart-define=RELAY_BASE_URL=https://your-relay.onrender.com`.

---

## 🖥️ Servidores de back-end e streaming

### ☁️ Cloud Stream Relay — `server/` (implantado em Render)
Resolve um URL de áudio YouTube **e retransmite os bytes** para que o telefone e o resolvedor compartilhem um IP
(nº 403). FastAPI + yt-dlp, Docker, nível gratuito.

| Ponto final | Descrição |
| --- | --- |
| `GET /health` | Sonda de vivacidade (`ok`) |
| `GET /stream?videoId=X&key=K` | Resolve via yt-dlp → retorna uma URL `…/relay` (200 somente se resolver) |
| `GET /relay?videoId=X&key=K` | Faz proxy dos bytes de áudio (com reconhecimento de intervalo → 206 para busca) |

Protegido por um `RELAY_KEY` env var compartilhado (retorna **401** sem ele). Implantar: Render →
**Root Directory = `server`**, Docker, **Health Check = `/health`**. Consulte `server/README.md`.

### 🎵 API do aplicativo — `backend/`
O back-end de dados/pesquisa (YouTube Music via youtubei.js + fontes abertas: Last.fm gêneros,
MusicBrainz lançamentos e décadas).

| Ponto final | Descrição |
| --- | --- |
| `/api/search` | Pesquisa de música/vídeo |
| `/api/trending` | Tendências |
| `/api/charts` | Paradas musicais do YT |
| `/api/playlist/:id` | Detalhe da lista de reprodução |
| `/api/moods`, `/api/moods/:id` | Categorias e humores (Last.fm substituto) |
| `/api/tags?tag=` | Principais faixas/álbuns do gênero (Last.fm) |
| `/api/newreleases` | Novos lançamentos (MusicBrainz) |
| `/api/decades?year=` | Álbuns por década (MusicBrainz) |
| `/api/categories` | Lista de categorias |

**Local:** `cd backend && npm install && npm start` (porta 8000).
**Implantar (Vercel):** importe este repositório, **Root Directory = `backend`**. Consulte `backend/README.md`.

### 🗄️ Banco de dados — `supabase/`
Postgres esquema com **Segurança em nível de linha**: as linhas do usuário têm como escopo `auth.uid()`, o catálogo é
somente leitura para usuários anônimos e gravável somente pela função de serviço. Execute migrações no Supabase
Editor SQL (em ordem).

---

## 🤝 Contribuindo

Contribuições são bem-vindas! Seja relatando um bug, sugerindo um recurso ou escrevendo código, sua ajuda será apreciada.

1. **Bifurcar o Projeto**
2. **Crie sua ramificação de recursos** (`git checkout -b feature/AmazingFeature`)
3. **Comprometa suas alterações** (`git commit -m 'Add some AmazingFeature'`)
4. **Empurre para a filial** (`git push origin feature/AmazingFeature`)
5. **Abra uma solicitação pull**

**Diretrizes:** siga o estilo de código existente, execute `flutter analyze` (deve estar limpo) e teste novos recursos antes de enviar.

---

## 🙏 Agradecimentos

Tunefy não existiria sem o trabalho incrível desses desenvolvedores e projetos.

### youtube_explode_dart
Agradecimentos a**[Hexer10](https://github.com/Hexer10)**, autor original de
[youtube_explode_dart](https://github.com/Hexer10/youtube_explode_dart) — a espinha dorsal de Tunefy
YouTube streaming — e**[anandnet](https://github.com/anandnet)** para o fork atualizado que
mantém Tunefy trabalhando com as alterações mais recentes de YouTube.

### Animesh (n-ce) — saavn rápido & ytify
Grite para**[Animesh (n-ce)](https://github.com/n-ce)**, criador de
**[fast-saavn](https://github.com/n-ce/saavn)** (a API JioSaavn aberta que alimenta os metadados de Tunefy)
e**[ytify](https://github.com/n-ce/ytify)** (uma grande fonte de inspiração).

### Bibliotecas de código aberto
| Pacote | Autor / Mantenedores |
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

Distribuído sob a **Licença MIT**. Consulte [`LICENSE`](LICENSE) para obter mais informações.
