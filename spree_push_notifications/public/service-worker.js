// Spree Push Notifications Service Worker
// This service worker handles push notifications and basic offline functionality

importScripts('https://storage.googleapis.com/workbox-cdn/releases/5.1.2/workbox-sw.js');

const CACHE = "spree-notifications-cache";

// Offline fallback page
const offlineFallbackPage = "offline.html";

self.addEventListener("message", (event) => {
  if (event.data && event.data.type === "SKIP_WAITING") {
    self.skipWaiting();
  }
});

self.addEventListener('install', async (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.add(offlineFallbackPage))
  );
});

if (workbox.navigationPreload.isSupported()) {
  workbox.navigationPreload.enable();
}

self.addEventListener('fetch', (event) => {
  if (event.request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const preloadResp = await event.preloadResponse;

        if (preloadResp) {
          return preloadResp;
        }

        const networkResp = await fetch(event.request);
        return networkResp;
      } catch (error) {
        const cache = await caches.open(CACHE);
        const cachedResp = await cache.match(offlineFallbackPage);
        return cachedResp;
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
      title: 'Notification',
      body: event.data ? event.data.text() : 'New notification'
    };
  }

  const title = data.title || 'Notification';
  const options = {
    body: data.body || 'You have a new notification',
    icon: data.icon || '/icon.png',
    badge: data.badge || '/icon.png',
    data: {
      url: data.url || '/'
    },
    tag: 'spree-notification',
    requireInteraction: false,
    actions: []
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Notification click event - handle notification clicks
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  event.waitUntil(
    clients.matchAll({ type: 'window' }).then((clientList) => {
      const url = event.notification.data && event.notification.data.url ?
        event.notification.data.url : '/';

      // Check if there's already a window open with the target URL
      for (const client of clientList) {
        if (client.url === url && 'focus' in client) {
          return client.focus();
        }
      }

      // If no window is already open, open a new one
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});

// Background sync for failed notifications (future enhancement)
self.addEventListener('sync', (event) => {
  if (event.tag === 'spree-notification-retry') {
    event.waitUntil(
      // Handle retry logic if needed
      Promise.resolve()
    );
  }
});