// HashPath service worker.
// Stale-while-revalidate for the calculator and Chart.js so the app loads
// instantly and works offline; live data calls (BTC price, difficulty,
// halving countdown) are passed through to the network so they never go
// stale silently.
//
// Bump CACHE_NAME on every release that changes hashpath.html so installed
// users get the new version on their next visit.

const CACHE_NAME = 'hashpath-v1';
const CHART_JS = 'https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js';
const PRECACHE = ['./', './hashpath.html', CHART_JS];

const NETWORK_ONLY_HOST_SUFFIXES = [
  'coingecko.com',
  'mempool.space',
  'coinbase.com'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  let url;
  try { url = new URL(event.request.url); } catch (_) { return; }
  if (NETWORK_ONLY_HOST_SUFFIXES.some((h) => url.hostname === h || url.hostname.endsWith('.' + h))) return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const networkFetch = fetch(event.request).then((resp) => {
        if (resp && resp.ok) {
          const clone = resp.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone)).catch(() => {});
        }
        return resp;
      }).catch(() => cached);
      return cached || networkFetch;
    })
  );
});
