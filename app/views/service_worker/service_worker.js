self.addEventListener('install', event => {
  console.log("Service worker installed");
  // Perform install steps
});

self.addEventListener('activate', event => {
  console.log("Service worker activated");
  // Clear old caches
});

self.addEventListener('fetch', event => {
  console.log("Service worker fetching:", event.request.url);
  // Here you could add code to respond to the request
});
