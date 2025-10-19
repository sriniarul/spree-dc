// Spree Push Notifications Service Worker
// This service worker handles both offline functionality and push notifications

const CACHE = "spree-offline";
const offlineFallbackPage = "/offline";

// Service Worker installation
self.addEventListener('install', async (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => {
        // Try to cache offline page, but don't fail if it doesn't exist
        return cache.add(offlineFallbackPage).catch(() => {
          console.log('Offline page not found, skipping cache');
        });
      })
  );
});

// Handle messages from the main thread
self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "SKIP_WAITING") {
    self.skipWaiting();
  }
});

// Fetch event - handle requests with offline fallback
self.addEventListener('fetch', (event) => {
  if (event.request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        // Try to get the response from network first
        const networkResp = await fetch(event.request);
        return networkResp;
      } catch (error) {
        // If network fails, try to serve from cache
        const cache = await caches.open(CACHE);
        const cachedResp = await cache.match(offlineFallbackPage);

        // If offline page is available, serve it; otherwise, create a basic offline response
        if (cachedResp) {
          return cachedResp;
        } else {
          return new Response(`
            <!DOCTYPE html>
            <html>
            <head>
              <title>Offline</title>
              <style>
                body { font-family: sans-serif; text-align: center; padding: 50px; }
                .offline-message { max-width: 400px; margin: 0 auto; }
              </style>
            </head>
            <body>
              <div class="offline-message">
                <h1>You're offline</h1>
                <p>Please check your internet connection and try again.</p>
                <button onclick="window.location.reload()">Retry</button>
              </div>
            </body>
            </html>
          `, {
            headers: { 'Content-Type': 'text/html' }
          });
        }
      }
    })());
  }
});

// Push event - handle incoming push messages
self.addEventListener('push', (event) => {
  let data = {};

  try {
    data = event.data.json();
  } catch (e) {
    data = {
      title: 'New Notification',
      body: event.data ? event.data.text() : 'You have a new notification'
    };
  }

  const title = data.title || 'New Notification';
  const options = {
    body: data.body || 'You have a new notification',
    icon: data.icon || '/icon.png',
    badge: data.badge || '/badge.png',
    image: data.image,
    tag: data.tag || 'spree-notification',
    requireInteraction: data.requireInteraction || false,
    silent: data.silent || false,
    data: {
      url: data.url || '/',
      clickAction: data.clickAction || 'open_url'
    },
    actions: data.actions || []
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Notification click event - handle notification clicks
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const notificationData = event.notification.data || {};
  const url = notificationData.url || '/';

  event.waitUntil(
    clients.matchAll({
      type: 'window',
      includeUncontrolled: true
    }).then((clientList) => {
      // Check if there's already a window open with the target URL
      for (const client of clientList) {
        if (client.url.includes(url) && 'focus' in client) {
          return client.focus();
        }
      }

      // If no suitable window is open, open a new one
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});

// Notification close event - handle when user dismisses notification
self.addEventListener('notificationclose', (event) => {
  console.log('Notification closed:', event.notification.tag);
});

// Background sync event - handle background synchronization
self.addEventListener('sync', (event) => {
  if (event.tag === 'background-sync') {
    event.waitUntil(
      // Perform background sync operations here
      console.log('Background sync triggered')
    );
  }
});

console.log('Spree Push Notifications Service Worker loaded');