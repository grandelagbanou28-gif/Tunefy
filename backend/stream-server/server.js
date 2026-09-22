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
const CACHE = new Map(); // videoId -> { url, exp }

const PENDING = new Map(); // videoId -> Promise → evite les extractions jumelles

function cacheGet(videoId) {
  const entry = CACHE.get(videoId);
  if (entry && entry.exp > Date.now()) return entry.url;
  if (entry) CACHE.delete(videoId);
  return null;
}

function cachePut(videoId, url) {
  CACHE.set(videoId, { url, exp: Date.now() + CACHE_TTL_SECONDS * 1000 });
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
function verifyUrl(url) {
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

function extractForClient(videoId, clientSet) {
  return new Promise((resolve) => {
    const cmd = [
      '--no-warnings',
      '--no-playlist',
      '-f', 'ba/b',
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

async function resolveWithYtDlp(videoId) {
  const errors = [];
  const deadline = Date.now() + GLOBAL_BUDGET_SECONDS * 1000;
  for (const clientSet of CLIENT_SETS) {
    if (Date.now() > deadline) {
      errors.push('global budget exhausted');
      break;
    }
    const { url, error } = await extractForClient(videoId, clientSet);
    if (!url) {
      errors.push(`${clientSet}: ${error}`);
      continue;
    }
    if (await verifyUrl(url)) return { url, source: clientSet };
    errors.push(`${clientSet}: unverified URL`);
  }
  return { url: null, source: null, error: errors.join(' | ').slice(0, 600) };
}

async function resolve(videoId) {
  // Cache memoire
  const mem = cacheGet(videoId);
  if (mem) return { url: mem, cached: true, source: 'memory' };

  // Single-flight : une seule extraction concurrente par videoId.
  if (PENDING.has(videoId)) return PENDING.get(videoId);
  const p = (async () => {
    const supa = await supabaseRead(videoId);
    if (supa) {
      cachePut(videoId, supa);
      return { url: supa, cached: true, source: 'supabase' };
    }
    const r = await resolveWithYtDlp(videoId);
    if (r.url) {
      cachePut(videoId, r.url);
      supabaseWrite(videoId, r.url);
    }
    return { url: r.url || null, cached: false, source: r.source || null, error: r.error || null };
  })();
  PENDING.set(videoId, p);
  try {
    return await p;
  } finally {
    PENDING.delete(videoId);
  }
}

// ─── Helpers HTTP ----------------------------------------------------------
function selfBase(req) {
  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || `localhost:${PORT}`;
  return `${proto}://${host}`;
}

function proxyUrl(req, videoId, rawUrl) {
  return `${selfBase(req)}/api/proxy?videoId=${encodeURIComponent(videoId)}&streamUrl=${encodeURIComponent(rawUrl)}`;
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
  try {
    const result = await resolve(videoId);
    if (!result.url) {
      console.log(`[${new Date().toISOString()}] /api/stream videoId=${videoId} => NULL (${result.error || 'no stream'}) [${Date.now() - started}ms]`);
      res.status(502).json({ error: result.error || 'no stream found' });
      return;
    }
    const body = {
      url: proxyUrl(req, videoId, result.url),
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

app.get('/api/proxy', async (req, res) => {
  const started = Date.now();
  const videoId = String(req.query.videoId || '').trim();
  const streamUrl = String(req.query.streamUrl || '').trim();
  let rawUrl = streamUrl;
  let cached = false;
  if (!rawUrl) {
    if (!videoId) {
      res.status(400).json({ error: 'missing videoId' });
      return;
    }
    const result = await resolve(videoId);
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