/* CourtFlow service worker — defensive offline/cache handling.
 * Never resolve respondWith() with undefined: Safari requires a Response.
 */
'use strict';
var CACHE_NAME = 'courtflow-v81-session-clock-top10-v39';
var CORE_FILES = [
  './',
  'index.html',
  'manifest.webmanifest',
  'favicon-64.png',
  'logo.png',
  'logo-dark.png',
  'icon-192.png',
  'courtflow-brand-icon.png',
  'icon-512.png',
  'icon-maskable-512.png',
  'apple-touch-icon.png'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(function (cache) {
        // Cache core files individually. A missing optional icon must not
        // prevent the new worker from installing and fixing fetch handling.
        return Promise.all(CORE_FILES.map(function (url) {
          return cache.add(url).catch(function (error) {
            console.warn('[CourtFlow SW] Could not precache ' + url, error);
          });
        }));
      })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys()
      .then(function (keys) {
        return Promise.all(keys.map(function (key) {
          return key.indexOf('courtflow-') === 0 && key !== CACHE_NAME
            ? caches.delete(key)
            : Promise.resolve(false);
        }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

self.addEventListener('fetch', function (event) {
  var request = event.request;
  if (!request || request.method !== 'GET') return;

  var url;
  try { url = new URL(request.url); } catch (_) { return; }
  // Let the browser handle cross-origin requests normally. CourtFlow's
  // offline assets are all served from the same Netlify origin.
  if (url.origin !== self.location.origin) return;

  event.respondWith((async function () {
    var cache = null;
    var cached = null;

    try {
      cache = await caches.open(CACHE_NAME);
      cached = await cache.match(request, { ignoreSearch: true });
    } catch (cacheReadError) {
      console.warn('[CourtFlow SW] Cache read failed', cacheReadError);
    }

    // Cache-first keeps previously downloaded model/runtime files available
    // offline. A cache hit is a valid Response and can be returned directly.
    if (cached) return cached;

    try {
      var response = await fetch(request);
      if (response && (response.ok || response.type === 'opaque') && cache) {
        // iOS Safari can fail large streamed model/WASM downloads when the
        // service worker tees the response for Cache.put(). Return these
        // large voice assets directly; cache only the small runtime/scripts.
        var largeVoiceAsset = /\.(?:onnx|wasm|data)(?:$|\?)/i.test(url.pathname);
        if (!largeVoiceAsset) {
          try {
            cache.put(request, response.clone()).catch(function (cacheWriteError) {
              console.warn('[CourtFlow SW] Could not cache ' + url.pathname, cacheWriteError);
            });
          } catch (cacheWriteError) {
            console.warn('[CourtFlow SW] Could not start cache write for ' + url.pathname, cacheWriteError);
          }
        }
      }
      if (response) return response;
      throw new Error('Network returned no response');
    } catch (networkError) {
      // Try the app shell for navigations, then return an explicit 503 for
      // missing assets. respondWith() must never receive undefined.
      if (cache) {
        try {
          var fallback = request.mode === 'navigate'
            ? await cache.match('index.html')
            : await cache.match(request, { ignoreSearch: true });
          if (fallback) return fallback;
        } catch (fallbackError) {
          console.warn('[CourtFlow SW] Fallback lookup failed', fallbackError);
        }
      }
      return new Response(
        'CourtFlow could not load this file. Check your connection and reload the app. Resource: ' + url.pathname,
        { status: 503, statusText: 'Offline resource unavailable', headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' } }
      );
    }
  })());
});
