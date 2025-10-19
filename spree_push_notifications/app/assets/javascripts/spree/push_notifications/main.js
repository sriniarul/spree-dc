// Spree Push Notifications - Main JavaScript file
// Ultra lightweight version that only runs after page is completely loaded and idle

(function() {
  'use strict';

  // Configuration
  const CONFIG = {
    serviceWorkerPath: '/service-worker.js',
    apiEndpoints: {
      publicKey: '/api/push/public-key',
      subscribe: '/api/push/subscribe',
      unsubscribe: '/api/push/unsubscribe'
    },
    dismissalKey: 'spree_notification_prompt_dismissed',
    pendingKey: 'spree_notification_pending',
    dismissalDays: 7,
    retryDelay: 2000,
    idleTimeout: 10000,
    fallbackTimeout: 5000
  };

  // Initialize push notifications
  function initializePushNotifications() {
    try {
      // Only proceed if service workers and push are supported
      if (!isSupported()) {
        console.log('Spree Push Notifications: Push notifications not supported by this browser');
        return;
      }

      console.log('Spree Push Notifications: Initializing...');

      // Register service worker
      registerServiceWorker()
        .then(handleServiceWorkerRegistration)
        .catch(handleServiceWorkerError);

    } catch (error) {
      console.error('Spree Push Notifications: Initialization error:', error);
    }
  }

  // Check if push notifications are supported
  function isSupported() {
    return 'serviceWorker' in navigator &&
           'PushManager' in window &&
           'Notification' in window;
  }

  // Register service worker
  function registerServiceWorker() {
    return navigator.serviceWorker.register(CONFIG.serviceWorkerPath);
  }

  // Handle successful service worker registration
  function handleServiceWorkerRegistration(registration) {
    console.log('Spree Push Notifications: Service Worker registered:', registration.scope);

    const permission = Notification.permission;

    if (permission === 'granted') {
      // User already granted permission, check subscription
      setTimeout(() => {
        checkAndUpdateSubscription(registration);
      }, 500);
    } else if (permission !== 'denied') {
      // User hasn't decided yet, show prompt on user interaction
      setupUserInteractionHandler();
    }
  }

  // Handle service worker registration error
  function handleServiceWorkerError(error) {
    console.error('Spree Push Notifications: Service Worker registration failed:', error);
  }

  // Setup handler for user interaction
  function setupUserInteractionHandler() {
    document.addEventListener('click', function() {
      setTimeout(() => {
        ensureBannerExists();
        showBannerIfNeeded();
      }, 1000);
    }, { once: true });
  }

  // Check and update existing subscription
  function checkAndUpdateSubscription(registration) {
    return registration.pushManager.getSubscription()
      .then(subscription => {
        if (subscription) {
          return updateSubscriptionOnServer(subscription);
        } else {
          return subscribeUser(registration);
        }
      })
      .catch(error => {
        console.error('Spree Push Notifications: Subscription check failed:', error);
      });
  }

  // Subscribe user to push notifications
  function subscribeUser(registration) {
    return getVapidPublicKey()
      .then(publicKey => {
        const applicationServerKey = urlBase64ToUint8Array(publicKey);

        return registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: applicationServerKey
        });
      })
      .then(subscription => {
        return updateSubscriptionOnServer(subscription);
      })
      .then(response => {
        console.log('Spree Push Notifications: User successfully subscribed');
        showSuccessMessage();
        return response;
      })
      .catch(error => {
        handleSubscriptionError(error);
      });
  }

  // Get VAPID public key from server
  function getVapidPublicKey() {
    return fetch(CONFIG.apiEndpoints.publicKey)
      .then(response => {
        if (!response.ok) {
          throw new Error(`Failed to fetch public key: ${response.status}`);
        }
        return response.json();
      })
      .then(data => {
        if (!data.publicKey) {
          throw new Error('Public key missing from response');
        }
        return data.publicKey;
      });
  }

  // Update subscription on server
  function updateSubscriptionOnServer(subscription) {
    return fetch(CONFIG.apiEndpoints.subscribe, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': getCSRFToken()
      },
      body: JSON.stringify({
        subscription: subscription.toJSON()
      })
    })
    .then(response => {
      if (!response.ok) {
        throw new Error(`Server update failed: ${response.status}`);
      }
      return response.json();
    })
    .catch(error => {
      console.error('Spree Push Notifications: Server update error:', error);
      return { success: false, error: error.message };
    });
  }

  // Handle subscription errors
  function handleSubscriptionError(error) {
    console.error('Spree Push Notifications: Subscription failed:', error);

    const message = getErrorMessage(error);
    showErrorMessage(message);

    // Store pending status if API is unavailable
    if (error.message.includes('Failed to fetch')) {
      localStorage.setItem(CONFIG.pendingKey, 'true');
    }
  }

  // Get appropriate error message
  function getErrorMessage(error) {
    if (error.message.includes('VAPID')) {
      return 'Push notifications are being configured. Please contact support.';
    } else if (error.message.includes('Failed to fetch')) {
      return 'Notifications will be enabled soon!';
    } else if (error.name === 'AbortError' || error.name === 'NotAllowedError') {
      if (navigator.userAgent.includes('Brave') || navigator.brave) {
        return 'Push notifications may be blocked by Brave browser. Please check settings.';
      }
      return 'Notification service temporarily unavailable. Please try again later.';
    }
    return 'Unable to enable notifications. Please try again later.';
  }

  // Ensure notification banner exists in DOM
  function ensureBannerExists() {
    if (document.getElementById('spree-push-banner')) return;

    const banner = createBannerElement();
    const success = createSuccessElement();
    const styles = createStyleElement();

    document.body.appendChild(banner);
    document.body.appendChild(success);
    document.head.appendChild(styles);

    setupBannerEventListeners();
  }

  // Create banner element
  function createBannerElement() {
    const banner = document.createElement('div');
    banner.id = 'spree-push-banner';

    // Check if permission was previously denied
    const permission = Notification.permission;
    const isRetry = permission === 'denied';

    const title = isRetry ? 'Enable Notifications?' : 'Stay Updated';
    const message = isRetry
      ? 'You previously blocked notifications. Would you like to enable them now for special offers and order updates?'
      : 'Get notifications about special offers, discounts, and order updates.';
    const allowText = isRetry ? 'Enable Now' : 'Allow';

    banner.innerHTML = `
      <div class="spree-notification-content">
        <h4>${title}</h4>
        <p>${message}</p>
        <div class="spree-notification-buttons">
          <button id="spree-allow-btn" type="button">${allowText}</button>
          <button id="spree-deny-btn" type="button">Not Now</button>
        </div>
      </div>
    `;
    return banner;
  }

  // Create success message element
  function createSuccessElement() {
    const success = document.createElement('div');
    success.id = 'spree-push-success';
    success.textContent = 'Notifications enabled! Thank you.';
    return success;
  }

  // Create CSS styles
  function createStyleElement() {
    if (document.getElementById('spree-push-styles')) return null;

    const style = document.createElement('style');
    style.id = 'spree-push-styles';
    style.textContent = `
      #spree-push-banner {
        display: none;
        position: fixed;
        bottom: 20px;
        right: 20px;
        width: 320px;
        max-width: calc(100vw - 40px);
        background: #fff;
        border-radius: 12px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
        padding: 20px;
        z-index: 10000;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        border: 1px solid rgba(0, 0, 0, 0.08);
        animation: spree-slide-up 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      }

      @keyframes spree-slide-up {
        from {
          transform: translateY(100px);
          opacity: 0;
        }
        to {
          transform: translateY(0);
          opacity: 1;
        }
      }

      #spree-push-banner h4 {
        margin: 0 0 8px 0;
        font-size: 16px;
        font-weight: 600;
        color: #1a1a1a;
      }

      #spree-push-banner p {
        margin: 0 0 16px 0;
        font-size: 14px;
        line-height: 1.4;
        color: #666;
      }

      .spree-notification-buttons {
        display: flex;
        gap: 8px;
      }

      #spree-allow-btn {
        flex: 1;
        background: #2563eb;
        color: white;
        border: none;
        padding: 10px 16px;
        border-radius: 8px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: background-color 0.2s;
      }

      #spree-allow-btn:hover {
        background: #1d4ed8;
      }

      #spree-deny-btn {
        flex: 1;
        background: #f3f4f6;
        color: #374151;
        border: none;
        padding: 10px 16px;
        border-radius: 8px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: background-color 0.2s;
      }

      #spree-deny-btn:hover {
        background: #e5e7eb;
      }

      #spree-push-success {
        display: none;
        position: fixed;
        bottom: 20px;
        right: 20px;
        background: #10b981;
        color: white;
        padding: 16px 20px;
        border-radius: 8px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
        z-index: 10000;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        font-size: 14px;
        font-weight: 500;
        animation: spree-fade-in 0.3s ease;
      }

      #spree-push-success.error {
        background: #f59e0b;
      }

      @keyframes spree-fade-in {
        from { opacity: 0; }
        to { opacity: 1; }
      }

      @media (max-width: 480px) {
        #spree-push-banner {
          bottom: 10px;
          right: 10px;
          left: 10px;
          width: auto;
          max-width: none;
        }

        #spree-push-success {
          bottom: 10px;
          right: 10px;
          left: 10px;
        }
      }
    `;

    return style;
  }

  // Setup banner event listeners
  function setupBannerEventListeners() {
    const allowBtn = document.getElementById('spree-allow-btn');
    const denyBtn = document.getElementById('spree-deny-btn');

    if (allowBtn) {
      allowBtn.addEventListener('click', handleAllowClick);
    }

    if (denyBtn) {
      denyBtn.addEventListener('click', handleDenyClick);
    }
  }

  // Handle allow button click
  function handleAllowClick() {
    hideBanner();
    requestNotificationPermission();
  }

  // Handle deny button click
  function handleDenyClick() {
    hideBanner();
    localStorage.setItem(CONFIG.dismissalKey, Date.now().toString());
  }

  // Request notification permission
  function requestNotificationPermission() {
    const permission = Notification.permission;

    // If permission is denied, we can't request again - show instructions
    if (permission === 'denied') {
      showManualInstructions();
      return;
    }

    Notification.requestPermission().then(permission => {
      if (permission === 'granted') {
        console.log('Spree Push Notifications: Permission granted');
        navigator.serviceWorker.ready.then(registration => {
          subscribeUser(registration);
        });
      } else if (permission === 'denied') {
        console.log('Spree Push Notifications: Permission denied');
        showManualInstructions();
      } else {
        console.log('Spree Push Notifications: Permission default - user dismissed');
      }
    });
  }

  // Show manual instructions for enabling notifications
  function showManualInstructions() {
    const userAgent = navigator.userAgent.toLowerCase();
    let instructions = 'To enable notifications, please:';

    if (userAgent.includes('chrome')) {
      instructions += '\n1. Click the lock icon in the address bar\n2. Select "Allow" for notifications\n3. Refresh the page';
    } else if (userAgent.includes('firefox')) {
      instructions += '\n1. Click the shield icon in the address bar\n2. Select "Allow" for notifications\n3. Refresh the page';
    } else if (userAgent.includes('safari')) {
      instructions += '\n1. Go to Safari > Preferences > Websites\n2. Find Notifications and allow for this site\n3. Refresh the page';
    } else {
      instructions += '\n1. Look for the notification settings in your browser\n2. Allow notifications for this site\n3. Refresh the page';
    }

    showErrorMessage(instructions);
  }

  // Show banner if conditions are met
  function showBannerIfNeeded() {
    if (shouldShowBanner()) {
      showBanner();
    }
  }

  // Check if banner should be shown
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

  // Show banner
  function showBanner() {
    const banner = document.getElementById('spree-push-banner');
    if (banner) {
      banner.style.display = 'block';
    }
  }

  // Hide banner
  function hideBanner() {
    const banner = document.getElementById('spree-push-banner');
    if (banner) {
      banner.style.display = 'none';
    }
  }

  // Show success message
  function showSuccessMessage(message = 'Notifications enabled! Thank you.') {
    showMessage(message, false);
  }

  // Show error message
  function showErrorMessage(message) {
    showMessage(message, true);
  }

  // Show message
  function showMessage(text, isError = false) {
    const element = document.getElementById('spree-push-success');
    if (!element) return;

    // Handle multi-line messages by converting \n to <br>
    if (text.includes('\n')) {
      element.innerHTML = text.replace(/\n/g, '<br>');
    } else {
      element.textContent = text;
    }

    element.className = isError ? 'error' : '';
    element.style.display = 'block';

    setTimeout(() => {
      element.style.display = 'none';
    }, isError ? 8000 : 3000); // Longer timeout for error messages with instructions
  }

  // Get CSRF token
  function getCSRFToken() {
    const token = document.querySelector('meta[name="csrf-token"]');
    return token ? token.getAttribute('content') : '';
  }

  // Convert base64 to Uint8Array
  function urlBase64ToUint8Array(base64String) {
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
      console.error('Spree Push Notifications: Invalid VAPID key format:', error);
      throw new Error('Invalid VAPID key format');
    }
  }

  // Public API
  window.SpreePushNotifications = {
    init: initializePushNotifications,
    showBanner: showBanner,
    requestPermission: requestNotificationPermission
  };

  // Auto-initialize with proper timing
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      window.addEventListener('load', delayedInit);
    });
  } else if (document.readyState === 'interactive') {
    window.addEventListener('load', delayedInit);
  } else {
    delayedInit();
  }

  // Delayed initialization
  function delayedInit() {
    if ('requestIdleCallback' in window) {
      requestIdleCallback(() => {
        setTimeout(initializePushNotifications, CONFIG.retryDelay);
      }, { timeout: CONFIG.idleTimeout });
    } else {
      setTimeout(initializePushNotifications, CONFIG.fallbackTimeout);
    }
  }

})();