# Tunefy stream server (Node/Express + yt-dlp)

Backend proxy de streaming pour le build **web** de Tunefy/Muzo. Le navigateur ne peut pas extraire un flux audio YouTube lui-même (les URL googlevideo sont liées à l'IP du serveur et sans CORS), donc c'est ce serveur qui résout la vraie URL audio avec yt-dlp et la rend streamable.

## Routes

- `GET /api/stream?videoId=<id>` → `{ "url": "...", "cached": bool, "source": "..." }`
  - `url` est une URL de ce serveur (`/api/proxy`) jouable par le navigateur (CORS + byte-ranges).
  - `?raw=1` ajoute `rawUrl` (la vraie URL googlevideo) pour debug.
- `GET /api/proxy?videoId=<id>&streamUrl=<url>` → relaie les octets du flux (Range supporté, CORS ouvert).
- `GET /api/health` → état du service.

## Démarrage local

```bash
npm install
# yt-dlp doit être dans le PATH (ou définir YTDLP_CMD)
node server.js      # écoute sur 0.0.0.0:9877
```

Test :

```bash
curl "http://127.0.0.1:9877/api/stream?videoId=dQw4w9WgXcQ"
```

## Options (variables d'environnement)

| Variable | Rôle |
|---|---|
| `PORT` | Port d'écoute (9877 par défaut) |
| `YTDLP_CMD` | Binaire yt-dlp (défaut `yt-dlp`) |
| `CACHE_TTL_SECONDS` | TTL du cache mémoire (5 h par défaut) |
| `SUPABASE_URL` / `SUPABASE_SERVICE_KEY` / `SUPABASE_ANON_KEY` | Cache partagé Supabase (optionnel) |

## Déploiement (Render)

Créer un service **web** Node, `Start command: npm start`. En mémoire de 512 Mo c'est suffisant (une exigence : Network = IPv4, et de préférence une réplique sur une IP résidentielle pour éviter le bot-check YouTube). Ajouter un health check sur `/api/health`.

Une fois déployé, configurer l'URL dans Flutter :

```bash
flutter build web --dart-define=WEB_STREAM_API_BASE=https://<hôte>/api
```

Si rien n'est défini, le code utilise `https://tunefy-ytdlp.onrender.com` par défaut (votre service Render `tunefy-ytdlp`).

## Côté Flutter

`YouTubeApiService.getStreamUrl()` (branche `kIsWeb`) appelle ce backend au lieu d'essayer d'extraire dans le navigateur ; le mobile (ANDROID_VR / youtube_explode / Invidious / Cobalt...) reste inchangé.