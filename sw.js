// Guarda el juego en el teléfono para que abra rápido y se pueda jugar solo sin internet.
const CACHE = 'splash-calabaza-v5';
const FILES = ['./', './index.html', './config.js', './manifest.webmanifest', './vendor/three/three.module.js',
  './vendor/three/addons/BufferGeometryUtils.js', './vendor/three/addons/RoundedBoxGeometry.js', './vendor/supabase.js',
  './icons/icon-192.png', './icons/icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES))); self.skipWaiting(); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;
  // Primero la red (para recibir actualizaciones); si no hay internet, lo guardado.
  e.respondWith(fetch(e.request).then(r => { const c = r.clone(); caches.open(CACHE).then(ca => ca.put(e.request, c)); return r; })
    .catch(() => caches.match(e.request, { ignoreSearch: true })));
});
