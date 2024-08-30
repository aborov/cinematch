self.addEventListener('install', event => {
  console.log("Service worker installed");
  // Perform install steps
});

self.addEventListener('activate', event => {
  console.log("Service worker activated");
  // Clear old caches
});

self.addEventListener('fetch', function(event) {
  event.respondWith(
    caches.match(event.request).then(function(response) {
      return response || fetch(event.request);
    })
  );
});
