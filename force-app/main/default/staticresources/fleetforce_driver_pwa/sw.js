// FleetForce Driver Service Worker
const CACHE_NAME = 'fleetforce-driver-pwa-v1';
const STATIC_ASSETS = [
  './manifest.webmanifest',
  './app-icon-192.png',
  './app-icon-512.png',
  './app-icon.svg'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  // Cache-first for PWA static assets
  if (event.request.url.includes('/fleetforce_driver_pwa/')) {
    event.respondWith(
      caches.match(event.request).then((cached) => cached || fetch(event.request))
    );
  }
});
