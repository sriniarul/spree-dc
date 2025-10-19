//= require spree/push_notifications/main

// Fallback initialization for older browsers
if (typeof window.SpreePushNotifications === 'undefined') {
  console.log('Spree Push Notifications: Fallback initialization');

  document.addEventListener('DOMContentLoaded', function() {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      console.log('Spree Push Notifications: Not supported in this browser');
      return;
    }

    console.log('Spree Push Notifications: Legacy initialization');

    // Simple fallback registration
    navigator.serviceWorker.register('/service-worker.js')
      .then(function(registration) {
        console.log('Service Worker registered (fallback)');
      })
      .catch(function(error) {
        console.error('Service Worker registration failed (fallback):', error);
      });
  });
}