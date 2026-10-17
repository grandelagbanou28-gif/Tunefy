# yt-dlp Server for Tunefy / Muzo

Serveur d'extraction audio gratuit et auto-hébergé pour l'app Tunefy.

## Déploiement gratuit

### Railway (recommandé)
1. Fork ce repo sur GitHub
2. Aller sur [railway.app](https://railway.app)
3. Sign up avec GitHub
4. Cliquer "Deploy from GitHub repo"
5. Sélectionner ce repo
6. Railway déploie automatiquement → URL : `https://yourapp.up.railway.app`

### Render
1. Fork ce repo sur GitHub
2. Aller sur [render.com](https://render.com)
3. "New Web Service" → sélectionner le repo
4. Build: `pip install -r requirements.txt`
5. Start: `uvicorn main:app --host 0.0.0.0 --port $PORT`

### Fly.io
1. Installer flyctl: `curl -L https://fly.io/install.sh | sh`
2. `fly launch` dans le dossier `server/`
3. `fly deploy`

## Endpoints

| Endpoint | Méthode | Description |
|----------|---------|-------------|
| `/health` | GET | Health check (retourne "ok") |
| `/stream?videoId=XXX` | GET | Retourne `{ "url": "..." }` avec l'URL du flux audio |

## Configuration

| Variable | Défaut | Description |
|----------|--------|-------------|
| `PORT` | 8080 | Port du serveur |
| `YT_DLP_BIN` | yt-dlp | Chemin vers l'exécutable yt-dlp |
| `COOKIES_PATH` | (vide) | Chemin vers un fichier cookies.txt pour YouTube |

## Intégration dans l'app

Dans les réglages de l'app, entrer l'URL de ton serveur :
```
https://ton-app.up.railway.app
```

L'app l'utilisera automatiquement en fallback si le serveur local est down.

## Limites gratuites

| Plateforme | Heures/mois | RAM | Notes |
|------------|-------------|-----|-------|
| Railway | 500h | 8GB | Pas de carte bancaire |
| Render | 750h | 512MB | Sleep après inactivité |
| Fly.io | 160h (3 shared-cpu-1x) | 256MB | 3GB storage |
