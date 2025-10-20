// Spree Push Notifications Client-side Implementation
document.addEventListener('DOMContentLoaded', function() {
  // Only proceed if service workers are supported
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    console.warn('Push notifications not supported by this browser');
    return;
  }

  // First, ensure the notification banner exists in the DOM
  ensureBannerExists();

  // Register service worker
  navigator.serviceWorker.register('/service-worker.js')
    .then(function(registration) {
      console.log('Spree Push Notifications: Service Worker registered successfully:', registration.scope);

      // Check if we already have permission
      if (Notification.permission === 'granted') {
        // Check if we have a valid subscription
        checkSubscription(registration);
      // } else if (shouldShowBanner()) {
      } else  {
        // Show banner for permission request
        showPushNotificationBanner();
      }
    })
    .catch(function(error) {
      console.error('Spree Push Notifications: Service Worker registration failed:', error);
    });
});

// Ensure the notification banner exists in the DOM
function ensureBannerExists() {
  // Only add the banner if it doesn't already exist
  if (!document.getElementById('spree-push-notification-banner')) {
    // Create banner element
    const banner = document.createElement('div');
    banner.id = 'spree-push-notification-banner';
    banner.innerHTML = `
      <h4>Stay Updated</h4>
      <p>Get notifications about special offers, discounts, and order updates.</p>
      <div class="notification-buttons">
        <button id="spree-notification-allow">Allow</button>
        <button id="spree-notification-deny">Not Now</button>
      </div>
    `;
    document.body.appendChild(banner);

    // Create success message element
    const success = document.createElement('div');
    success.id = 'spree-notification-success';
    success.textContent = 'Notifications enabled! Thank you.';
    document.body.appendChild(success);

    // Add CSS if not already present
    if (!document.getElementById('spree-push-notification-css')) {
      const style = document.createElement('style');
      style.id = 'spree-push-notification-css';
      style.textContent = `
        #spree-push-notification-banner {
          display: none;
          position: fixed;
          bottom: 20px;
          right: 20px;
          width: 300px;
          background-color: white;
          border-radius: 8px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
          padding: 16px;
          z-index: 9999;
          animation: spree-slide-in 0.3s ease-out;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }
        @keyframes spree-slide-in {
          from { transform: translateY(100px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }
        #spree-push-notification-banner h4 {
          margin-top: 0;
          margin-bottom: 8px;
          font-size: 16px;
          color: #333;
        }
        #spree-push-notification-banner p {
          margin-bottom: 12px;
          font-size: 14px;
          color: #666;
        }
        .notification-buttons {
          display: flex;
          justify-content: space-between;
        }
        #spree-notification-allow {
          background-color: #4CAF50;
          color: white;
          border: none;
          padding: 8px 16px;
          border-radius: 4px;
          cursor: pointer;
          font-weight: 500;
        }
        #spree-notification-allow:hover {
          background-color: #45a049;
        }
        #spree-notification-deny {
          background-color: #f1f1f1;
          color: #333;
          border: none;
          padding: 8px 16px;
          border-radius: 4px;
          cursor: pointer;
          font-weight: 500;
        }
        #spree-notification-deny:hover {
          background-color: #e7e7e7;
        }
        #spree-notification-success {
          display: none;
          position: fixed;
          bottom: 20px;
          right: 20px;
          background-color: #4CAF50;
          color: white;
          padding: 16px;
          border-radius: 8px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
          z-index: 9999;
          animation: spree-fade-in 0.3s ease-out;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
        }
        @keyframes spree-fade-in {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @media (max-width: 768px) {
          #spree-push-notification-banner {
            width: calc(100% - 40px);
            bottom: 10px;
            right: 10px;
            left: 10px;
          }
          #spree-notification-success {
            width: calc(100% - 40px);
            bottom: 10px;
            right: 10px;
            left: 10px;
          }
        }
      `;
      document.head.appendChild(style);
    }
  }
}

// Configuration
const CONFIG = {
  dismissalKey: 'spree_push_notification_dismissed',
  dismissalDays: 7
};

// Check if we should show the banner
function shouldShowBanner() {
  const permission = Notification.permission;

  // Always show banner if permission is denied - give user another chance
  if (permission === 'denied') {
    return true;
  }

  // Don't show if already granted
  if (permission === 'granted') {
    return false;
  }

  // For 'default' permission, check dismissal time
  const dismissed = localStorage.getItem(CONFIG.dismissalKey);
  const dismissalTime = parseInt(dismissed) || 0;
  const sevenDaysAgo = Date.now() - (CONFIG.dismissalDays * 24 * 60 * 60 * 1000);

  return !dismissed || dismissalTime < sevenDaysAgo;
}

// Show the push notification banner
function showPushNotificationBanner() {
  const banner = document.getElementById('spree-push-notification-banner');
  if (banner) {
    // Make banner visible
    banner.style.display = 'block';

    // Add event listeners to buttons
    const allowBtn = document.getElementById('spree-notification-allow');
    const denyBtn = document.getElementById('spree-notification-deny');

    if (allowBtn) {
      allowBtn.addEventListener('click', function() {
        banner.style.display = 'none';
        requestNotificationPermission();
      });
    }

    if (denyBtn) {
      denyBtn.addEventListener('click', function() {
        banner.style.display = 'none';
        localStorage.setItem(CONFIG.dismissalKey, Date.now());
      });
    }
  } else {
    console.error('Spree Push Notifications: Banner not found in the DOM');
  }
}

// Request notification permission and subscribe user
function requestNotificationPermission() {
  if ('Notification' in window) {
    Notification.requestPermission().then(function(permission) {
      if (permission === 'granted') {
        console.log('Spree Push Notifications: Permission granted!');
        navigator.serviceWorker.ready.then(function(registration) {
          subscribeUserToPush(registration);
        });
      } else {
        console.log('Spree Push Notifications: Permission denied');
      }
    });
  }
}

// Check if we have a valid subscription
function checkSubscription(registration) {
  return registration.pushManager.getSubscription()
    .then(function(subscription) {
      if (!subscription) {
        // User has granted permission but no subscription exists
        return subscribeUserToPush(registration);
      } else {
        // We have a subscription, update the server
        return updateSubscriptionOnServer(subscription);
      }
    });
}

// Subscribe user to push notifications
function subscribeUserToPush(registration) {
  // Get the server's public key
  return fetch('/spree/api/push/env')
    .then(function(response) {
      if (!response.ok) {
        throw new Error('Failed to fetch public key');
      }
      return response.json();
    })
    .then(function(data) {
      if (!data.vapidPublicKey) {
        throw new Error('VAPID public key is missing from response');
      }

      const applicationServerKey = urlB64ToUint8Array(data.vapidPublicKey);

      // Subscribe the user
      return registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: applicationServerKey
      }).catch(function(subscribeError) {
        console.warn('Spree Push Notifications: Subscription error:', subscribeError);

        // If we get a subscription error, try unsubscribing first and then resubscribing
        if (subscribeError.name === 'AbortError') {
          return registration.pushManager.getSubscription()
            .then(function(subscription) {
              if (subscription) {
                return subscription.unsubscribe().then(function() {
                  // Now try subscribing again
                  return registration.pushManager.subscribe({
                    userVisibleOnly: true,
                    applicationServerKey: applicationServerKey
                  });
                });
              }

              // If there's no subscription, the error was for another reason
              throw subscribeError;
            });
        }

        throw subscribeError;
      });
    })
    .then(function(subscription) {
      // Send the subscription to the server
      return updateSubscriptionOnServer(subscription);
    })
    .then(function(response) {
      console.log('Spree Push Notifications: User successfully subscribed');
      // Show success message if element exists
      const successMessage = document.getElementById('spree-notification-success');
      if (successMessage) {
        successMessage.style.display = 'block';
        // Hide success message after 3 seconds
        setTimeout(function() {
          successMessage.style.display = 'none';
        }, 3000);
      }

      return response;
    })
    .catch(function(error) {
      console.error('Spree Push Notifications: Failed to subscribe user:', error);

      // If the API endpoint isn't available, log clearly and try again later
      if (error.message.includes('Failed to fetch')) {
        console.log('Spree Push Notifications: API endpoints not available. Will configure later.');

        // Store in localStorage that the user wants notifications
        localStorage.setItem('spree_notification_pending', 'true');

        // Show a temporary success message to the user anyway
        const successMessage = document.getElementById('spree-notification-success');
        if (successMessage) {
          successMessage.textContent = 'Notifications will be enabled soon!';
          successMessage.style.display = 'block';
          setTimeout(function() {
            successMessage.style.display = 'none';
          }, 3000);
        }
      } else if (error.name === 'AbortError' || error.name === 'NotAllowedError') {
        // For push service errors, show a more specific message
        const successMessage = document.getElementById('spree-notification-success');
        if (successMessage) {
          successMessage.textContent = 'Notification service temporarily unavailable, please try again later.';
          successMessage.style.backgroundColor = '#FFA500';
          successMessage.style.display = 'block';
          setTimeout(function() {
            successMessage.style.display = 'none';
          }, 4000);
        }
      }
    });
}

// Send the subscription to the server
function updateSubscriptionOnServer(subscription) {
  return fetch('/spree/api/push/subscriptions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Requested-With': 'XMLHttpRequest'
    },
    body: JSON.stringify({
      subscription: {
        endpoint: subscription.endpoint,
        p256dh: arrayBufferToBase64(subscription.getKey('p256dh')),
        auth: arrayBufferToBase64(subscription.getKey('auth'))
      }
    })
  })
  .then(function(response) {
    if (!response.ok) {
      throw new Error('Failed to update subscription on server');
    }
    return response.json();
  })
  .catch(function(error) {
    console.error('Spree Push Notifications: Server update error:', error);
    // Still return the subscription object so we don't break the chain
    return { success: false, error: error.message };
  });
}

// Helper function to get CSRF token
function getCSRFToken() {
  return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
}

// Helper function to convert base64 to Uint8Array for applicationServerKey
function urlB64ToUint8Array(base64String) {
  try {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding)
      .replace(/\-/g, '+')
      .replace(/_/g, '/');

    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }

    return outputArray;
  } catch (error) {
    console.error('Spree Push Notifications: Error converting base64 string to Uint8Array:', error);
    throw new Error('Invalid VAPID key format');
  }
}

// Utility function to convert ArrayBuffer to Base64
function arrayBufferToBase64(buffer) {
  let binary = '';
  const bytes = new Uint8Array(buffer);
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return window.btoa(binary);
}

// Expose functions globally for manual use
window.SpreePushNotifications = {
  requestPermission: requestNotificationPermission,
  showBanner: showPushNotificationBanner,
  checkSubscription: checkSubscription
};
