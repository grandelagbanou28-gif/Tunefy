'use strict';

// ─────────────────────────────────────────────────────────────────────────────
// Tunefy stream proxy — Node/Express + yt-dlp
//
// Le build WEB de l'app ne peut pas extraire un flux audio YouTube depuis le
// navigateur (googlevideo = lie aux IP, pas de CORS). Ce backend fait le
// travail cote serveur et expose :
//
//   GET /api/stream?videoId=<id>[&raw=1]
//        → JSON { url, cached, source } ; `url` est une URL de ce serveur
//          (/api/proxy) streamable par le navigateur avec CORS + byte-ranges.
//          Avec raw=1, renvoie la vraie URL googlevideo a la place.
//   GET /api/proxy?videoId=<id>&streamUrl=<resolue>
//        → relaie les octets du flux (Range supporte, CORS ouvert).
//   GET /api/health
//
// Variables d'env optionnelles :
//   PORT                 port d'ecoute (default 9877)
//   YTDLP_CMD            binaire yt-dlp (default "yt-dlp")
//   CACHE_TTL_SECONDS    TTL du cache memoire (default 5h)
//   SUPABASE_URL / SUPABASE_SERVICE_KEY / SUPABASE_ANON_KEY
//                        cache partage (lecture+ecriture) — optionnel
// ─────────────────────────────────────────────────────────────────────────────

const express = require('express');
const cors = require('cors');
const { execFile } = require('node:child_process');
const http = require('node:http');
const https = require('node:https');
const dns = require('node:dns');
const net = require('node:net');

const PORT = parseInt(process.env.PORT || '9877', 10);
const YTDLP_CMD = process.env.YTDLP_CMD || 'yt-dlp';
const CACHE_TTL_SECONDS = parseInt(process.env.CACHE_TTL_SECONDS || String(5 * 3600), 10);
const VERIFY_TIMEOUT_MS = 8 * 1000;
const CLIENT_TIMEOUT_SECONDS = 45;
const GLOBAL_BUDGET_SECONDS = 90;

const MOBILE_UA =
  'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Mobile Safari/537.36';

// Cascade de clients YouTube : sur IP de datacenter YouTube bloque certains
// clients (bot-check) ; on essaie tout et on garde la premiere URL verifiee.
const CLIENT_SETS = [
  'youtube:player_client=android,tv',
  'youtube:player_client=tv',
  'youtube:player_client=ios',
  'youtube:player_client=web_embedded',
  'youtube:player_client=mweb',
];

const app = express();
app.use(cors()); // CORS ouvert : requis par le frontend web (Vercel / localhost)
app.disable('x-powered-by');

// ─── Cache memoire + single-flight -----------------------------------------
// La clé porte le type : une URL audio (`ba`) n'est pas substituable à une
// URL vidéo muxée pour le même videoId.
const cacheKeyOf = (videoId, kind) => (kind === 'video' ? `v:${videoId}` : `a:${videoId}`);

const CACHE = new Map(); // cacheKey -> { url, exp }

const PENDING = new Map(); // cacheKey -> Promise → evite les extractions jumelles

// Limite de concurrence yt-dlp : une page artiste peut demander ~26
// videoIds d'un coup ; sans cap, autant de process yt-dlp saturent le CPU
// et chaque extraction dépasse le timeout client (10-30s).
const MAX_CONCURRENT_YTDLP = 4;
let activeYtDlp = 0;
const ytdlpQueue = [];

function acquireYtDlpSlot() {
  return new Promise((resolve) => {
    if (activeYtDlp < MAX_CONCURRENT_YTDLP) {
      activeYtDlp++;
      resolve();
    } else {
      ytdlpQueue.push(resolve);
    }
  });
}

function releaseYtDlpSlot() {
  const next = ytdlpQueue.shift();
  if (next) next(); // slot transmis : activeYtDlp inchange
  else activeYtDlp--;
}

function cacheGet(cacheKey) {
  const entry = CACHE.get(cacheKey);
  if (entry && entry.exp > Date.now()) return entry.url;
  if (entry) CACHE.delete(cacheKey);
  return null;
}

function cachePut(cacheKey, url) {
  CACHE.set(cacheKey, { url, exp: Date.now() + CACHE_TTL_SECONDS * 1000 });
}

// ─── Cache Supabase partage (optionnel) ------------------------------------
const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || '';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || '';

function supabaseRead(videoId) {
  if (!(SUPABASE_URL && SUPABASE_ANON_KEY)) return Promise.resolve(null);
  const qs = new URLSearchParams({
    select: 'url',
    'video_id': `eq.${videoId}`,
    'limit': '1',
  });
  return fetch(`${SUPABASE_URL}/rest/v1/stream_cache?${qs}`, {
    headers: { apikey: SUPABASE_ANON_KEY },
    signal: AbortSignal.timeout(8000),
  })
    .then((r) => (r.ok ? r.json() : null))
    .then((rows) => (Array.isArray(rows) && rows[0]?.url ? rows[0].url : null))
    .catch(() => null);
}

function supabaseWrite(videoId, url) {
  if (!(SUPABASE_URL && SUPABASE_SERVICE_KEY)) return;
  const body = {
    video_id: videoId,
    url,
    format: 'ba',
    expires_at: new Date(Date.now() + CACHE_TTL_SECONDS * 1000).toISOString(),
  };
  fetch(`${SUPABASE_URL}/rest/v1/stream_cache`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  }).catch(() => {});
}

// ─── yt-dlp ----------------------------------------------------------------
// Un videoId n'est jamais une URL : on n'accepte que les caractères d'un
// identifiant YouTube. Sans ça, un appelant pourrait faire télécharger par
// yt-dlp n'importe quelle URL (file://, IP internes) depuis ce serveur.
const VIDEO_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

function isValidVideoId(id) {
  return typeof id === 'string' && VIDEO_ID_RE.test(id);
}

// ─── Garde SSRF sur les URL amont ------------------------------------------
// /api/proxy reçoit une `streamUrl` fournie par l'appelant : on ne doit
// relayer que des hôtes publics (jamais loopback, RFC1918, metadata cloud).
const ALLOWED_STREAM_PROTOCOLS = new Set(['http:', 'https:']);
const hostAllowCache = new Map(); // hostname -> { allowed, exp }
const HOST_CACHE_TTL_MS = 5 * 60 * 1000;
const HOST_CACHE_MAX = 512;

function isPrivateIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    if (a === 0 || a === 10 || a === 127) return true;
    if (a === 169 && b === 254) return true; // link-local / metadata cloud
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
    if (a >= 224) return true; // multicast / réservé
    return false;
  }
  if (net.isIPv6(ip)) {
    const h = ip.toLowerCase().replace(/^\[|\]$/g, '');
    if (h === '::' || h === '::1') return true;
    if (h.startsWith('fe80')) return true;
    if (/^f[cd]/.test(h)) return true; // unique local
    if (h.startsWith('::ffff:')) {
      const v4 = h.slice('::ffff:'.length);
      if (net.isIPv4(v4)) return isPrivateIp(v4);
    }
    return false;
  }
  return true; // format inconnu → on bloque
}

async function checkUpstreamUrl(rawUrl) {
  let u;
  try {
    u = new URL(String(rawUrl));
  } catch {
    return { allowed: false, reason: 'unparseable url' };
  }
  if (!ALLOWED_STREAM_PROTOCOLS.has(u.protocol)) {
    return { allowed: false, reason: `protocol ${u.protocol}` };
  }
  const host = u.hostname.toLowerCase().replace(/^\[|\]$/g, '');
  if (!host) return { allowed: false, reason: 'empty host' };
  const now = Date.now();
  const cached = hostAllowCache.get(host);
  if (cached && cached.exp > now) {
    return { allowed: cached.allowed, reason: cached.reason || (cached.allowed ? 'public' : 'blocked') };
  }
  let allowed = false;
  let reason = 'public';
  try {
    const records = await dns.promises.lookup(host, { all: true, verbatim: false });
    const bad = records.filter((r) => isPrivateIp(r.address)).map((r) => r.address);
    if (!records.length) {
      allowed = false;
      reason = 'dns: no record';
    } else if (bad.length) {
      allowed = false;
      reason = `dns: private address ${bad[0]}`;
    } else {
      allowed = true;
    }
  } catch (e) {
    allowed = false;
    reason = `dns: ${String(e && e.code ? e.code : e)}`;
  }
  if (hostAllowCache.size >= HOST_CACHE_MAX) hostAllowCache.clear();
  hostAllowCache.set(host, { allowed, reason, exp: now + HOST_CACHE_TTL_MS });
  return { allowed, reason };
}

async function isAllowedUpstreamUrl(rawUrl) {
  return (await checkUpstreamUrl(rawUrl)).allowed;
}

async function verifyUrl(url) {
  // Même garde : les lignes du cache Supabase sont écrites avec la clé anon
  // (publique) — on ne va jamais interroger une URL interne à votre place.
  if (!(await isAllowedUpstreamUrl(url))) return false;
  const mod = url.startsWith('https:') ? https : http;
  return new Promise((resolve) => {
    const req = mod.get(url, { headers: { Range: 'bytes=0-1' } }, (res) => {
      // Si l'upstream refuse le Range mais repond 200, l'URL est encore vivante.
      resolve(res.statusCode === 200 || res.statusCode === 206);
      res.resume();
    });
    req.on('error', () => resolve(false));
    req.setTimeout(VERIFY_TIMEOUT_MS, () => {
      req.destroy();
      resolve(false);
    });
  });
}

// ─── Formats ───────────────────────────────────────────────────────────────
// audio : flux seul, le plus léger possible (lecture de musique).
// video : rendition muxée plafonnée en hauteur — utilisée par le feed de clips
//         pour afficher le VRAI clip de l'artiste (une URL audio ne peut pas
//         être dessinée par un VideoPlayer).
const FORMATS = {
  audio: 'ba/b',
  video: 'best[height<=480][ext=mp4]/best[height<=480]/bestvideo[height<=480]+bestaudio/best',
};

function extractForClient(videoId, clientSet, kind = 'audio') {
  return new Promise((resolve) => {
    const cmd = [
      '--no-warnings',
      '--no-playlist',
      '-f', FORMATS[kind] || FORMATS.audio,
      '--get-url',
      '--extractor-args', clientSet,
      '--socket-timeout', '20',
      '--', videoId,
    ];
    execFile(
      YTDLP_CMD,
      cmd,
      { timeout: CLIENT_TIMEOUT_SECONDS * 1000, maxBuffer: 8 * 1024 * 1024, windowsHide: true },
      (err, stdout, stderr) => {
        if (!err && stdout && stdout.trim()) {
          resolve({ url: stdout.trim().split(/\r?\n/).pop(), error: null });
          return;
        }
        const tail = String(stderr || '').trim().split(/\r?\n/).filter(Boolean).slice(-1)[0] ||
          `exit ${err && err.code !== null ? err.code : 'timeout'}`;
        resolve({ url: null, error: String(tail).slice(0, 400) });
      }
    );
  });
}

async function resolveWithYtDlp(videoId, kind = 'audio') {
  await acquireYtDlpSlot();
  try {
    const errors = [];
    const deadline = Date.now() + GLOBAL_BUDGET_SECONDS * 1000;
    for (const clientSet of CLIENT_SETS) {
      if (Date.now() > deadline) {
        errors.push('global budget exhausted');
        break;
      }
      const { url, error } = await extractForClient(videoId, clientSet, kind);
      if (!url) {
        errors.push(`${clientSet}: ${error}`);
        continue;
      }
      if (await verifyUrl(url)) return { url, source: clientSet };
      errors.push(`${clientSet}: unverified URL`);
    }
    return { url: null, source: null, error: errors.join(' | ').slice(0, 600) };
  } finally {
    releaseYtDlpSlot();
  }
}

async function resolve(videoId, kind = 'audio') {
  const cacheKey = cacheKeyOf(videoId, kind);
  // Cache memoire
  const mem = cacheGet(cacheKey);
  if (mem) return { url: mem, cached: true, source: 'memory' };

  // Single-flight : une seule extraction concurrente par videoId + type.
  if (PENDING.has(cacheKey)) return PENDING.get(cacheKey);
  const p = (async () => {
    // Le cache partage Supabase ne sert que l'audio : une ligne vidéo liée à
    // l'IP de celui qui l'a écrite flue (403) et polluerait la lecture audio.
    const supa = kind === 'audio' ? await supabaseRead(videoId) : null;
    // Shared cache rows are googlevideo URLs bound to whoever wrote them —
    // often another IP → 403 at proxy time = player Source error. Always
    // verify before serving; dead rows fall through to a fresh yt-dlp run.
    if (supa && (await verifyUrl(supa))) {
      cachePut(cacheKey, supa);
      return { url: supa, cached: true, source: 'supabase' };
    }
    if (supa) {
      console.log(`[${new Date().toISOString()}] supabase dead for ${videoId} — re-extracting`);
    }
    const r = await resolveWithYtDlp(videoId, kind);
    if (r.url) {
      cachePut(cacheKey, r.url);
      if (kind === 'audio') supabaseWrite(videoId, r.url);
    }
    return { url: r.url || null, cached: false, source: r.source || null, error: r.error || null };
  })();
  PENDING.set(cacheKey, p);
  try {
    return await p;
  } finally {
    PENDING.delete(cacheKey);
  }
}

// ─── Helpers HTTP ----------------------------------------------------------
function selfBase(req) {
  const proto = req.get('x-forwarded-proto') === 'https' ? 'https' : 'http';
  // Le header Host est client-controlled : on ne le réutilise tel quel que s'il
  // est syntaxiquement valide (sinon on renvoie sur le port réel du serveur).
  const host = req.get('host') || '';
  const safeHost = /^[A-Za-z0-9.-]+(:\d{1,5})?$/.test(host) ? host : `127.0.0.1:${PORT}`;
  return `${proto}://${safeHost}`;
}

function proxyUrl(req, videoId, rawUrl, kind = 'audio') {
  const kindParam = kind === 'video' ? '&kind=video' : '';
  return `${selfBase(req)}/api/proxy?videoId=${encodeURIComponent(videoId)}${kindParam}&streamUrl=${encodeURIComponent(rawUrl)}`;
}

// `kind=video` demande une rendition muxée (feed de clips) au lieu du flux
// audio seul. Toute valeur inconnue retombe sur 'audio'.
function kindOf(req) {
  return String(req.query.kind || '') === 'video' ? 'video' : 'audio';
}

// ─── Routes -----------------------------------------------------------------
app.get('/api/health', (req, res) => {
  res.json({ ok: true, service: 'tunefy-stream-server', cacheEntries: CACHE.size });
});

app.get('/api/stream', async (req, res) => {
  const started = Date.now();
  const videoId = String(req.query.videoId || '').trim();
  if (!videoId) {
    res.status(400).json({ error: 'missing videoId' });
    return;
  }
  if (!isValidVideoId(videoId)) {
    res.status(400).json({ error: 'invalid videoId' });
    return;
  }
  try {
    const result = await resolve(videoId, kindOf(req));
    if (!result.url) {
      console.log(`[${new Date().toISOString()}] /api/stream videoId=${videoId} => NULL (${result.error || 'no stream'}) [${Date.now() - started}ms]`);
      res.status(502).json({ error: result.error || 'no stream found' });
      return;
    }
    const body = {
      url: proxyUrl(req, videoId, result.url, kindOf(req)),
      cached: result.cached,
      source: result.source,
    };
    if (String(req.query.raw || '') === '1') body.rawUrl = result.url;
    console.log(`[${new Date().toISOString()}] /api/stream videoId=${videoId} => ${result.source} (cached=${result.cached}) [${Date.now() - started}ms]`);
    res.json(body);
  } catch (e) {
    console.log(`[${new Date().toISOString()}] /api/stream videoId=${videoId} => ERROR ${e}`);
    res.status(500).json({ error: String(e && e.message ? e.message : e) });
  }
});

// Alias `/stream` : le player mobile interroge le serveur local via
// `$candidate/stream?videoId=...` (loopback adb reverse). Même comportement
// que /api/stream : on renvoie une URL self-proxy jouable côté client.
app.get('/stream', async (req, res) => {
  const started = Date.now();
  const videoId = String(req.query.videoId || req.query.v || '').trim();
  if (!videoId) {
    res.status(400).json({ error: 'missing videoId' });
    return;
  }
  if (!isValidVideoId(videoId)) {
    res.status(400).json({ error: 'invalid videoId' });
    return;
  }
  try {
    const result = await resolve(videoId, kindOf(req));
    if (!result.url) {
      console.log(`[${new Date().toISOString()}] /stream videoId=${videoId} => NULL (${result.error || 'no stream'}) [${Date.now() - started}ms]`);
      res.status(502).json({ error: result.error || 'no stream found' });
      return;
    }
    const body = {
      url: proxyUrl(req, videoId, result.url, kindOf(req)),
      cached: result.cached,
      source: result.source,
    };
    if (String(req.query.raw || '') === '1') body.rawUrl = result.url;
    console.log(`[${new Date().toISOString()}] /stream videoId=${videoId} => ${result.source} (cached=${result.cached}) [${Date.now() - started}ms]`);
    res.json(body);
  } catch (e) {
    console.log(`[${new Date().toISOString()}] /stream videoId=${videoId} => ERROR ${e}`);
    res.status(500).json({ error: String(e && e.message ? e.message : e) });
  }
});

app.get('/api/proxy', async (req, res) => {
  const started = Date.now();
  const videoId = String(req.query.videoId || '').trim();
  const streamUrl = String(req.query.streamUrl || '').trim();
  if (videoId && !isValidVideoId(videoId)) {
    res.status(400).json({ error: 'invalid videoId' });
    return;
  }
  let rawUrl = streamUrl;
  let cached = false;

  // SSRF : l'appelant peut envoyer n'importe quelle URL ici. On ne relaie que
  // des hôtes publics ; sinon on retombe sur une résolution yt-dlp interne
  // (si un videoId est fourni) plutôt que d'atteindre l'infra locale.
  if (rawUrl) {
    const check = await checkUpstreamUrl(rawUrl);
    if (!check.allowed) {
      console.log(`[${new Date().toISOString()}] /api/proxy blocked upstream (${check.reason}): ${String(rawUrl).slice(0, 120)}`);
      rawUrl = '';
    }
  }

  if (!rawUrl) {
    if (!videoId) {
      res.status(400).json({ error: 'missing videoId' });
      return;
    }
    const result = await resolve(videoId, kindOf(req));
    if (!result.url) {
      console.log(`[${new Date().toISOString()}] /api/proxy videoId=${videoId} => NULL`);
      res.status(502).json({ error: result.error || 'no stream found' });
      return;
    }
    rawUrl = result.url;
    cached = result.cached;
  }

  const mod = rawUrl.startsWith('https:') ? https : http;
  const headers = { 'User-Agent': MOBILE_UA };
  const range = req.get('range');
  if (range) headers.Range = range;

  const up = mod.request(
    rawUrl,
    { headers, signal: AbortSignal.timeout(120 * 1000) },
    (upstream) => {
      const status = upstream.statusCode || 200;
      res.status(status);
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Accept-Ranges', 'bytes');
      res.setHeader('Content-Type', upstream.headers['content-type'] || 'audio/mpeg');
      if (upstream.headers['content-length']) res.setHeader('Content-Length', upstream.headers['content-length']);
      if (upstream.headers['content-range']) res.setHeader('Content-Range', upstream.headers['content-range']);
      console.log(`[${new Date().toISOString()}] /api/proxy videoId=${videoId} => ${status} (cached=${cached}) [${Date.now() - started}ms]`);
      upstream.pipe(res);
      upstream.on('error', () => res.destroy());
    }
  );
  up.on('error', (e) => {
    if (!res.headersSent) {
      res.status(502).json({ error: `upstream: ${e.message}` });
    } else {
      res.destroy();
    }
  });
  up.end();
});

// Vercel/serverless compatible : export l'app Express.
if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[${new Date().toISOString()}] tunefy-stream-server listening on 0.0.0.0:${PORT}`);
  });
} else {
  module.exports = app;
}