const CACHE_NAME = 'stockai-v6';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './data/quotes.json'
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Network-first for quotes data, cache the response for offline
  if (url.pathname.includes('quotes.json')) {
    e.respondWith(
      fetch(e.request).then(response => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(c => {
            // Cache both with and without query param
            c.put(new Request(url.origin + url.pathname), clone);
          });
        }
        return response;
      }).catch(() => {
        // Serve cached quotes when offline
        return caches.match(url.origin + url.pathname)
          .then(r => r || caches.match(e.request))
          .then(r => r || new Response('{"updated":"","quotes":{}}', {
            headers: {'Content-Type': 'application/json'}
          }));
      })
    );
    return;
  }

  // Stale-while-revalidate for app shell
  e.respondWith(
    caches.match(e.request).then(cached => {
      const fetchPromise = fetch(e.request).then(response => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
        }
        return response;
      }).catch(() => cached);
      return cached || fetchPromise;
    })
  );
});
