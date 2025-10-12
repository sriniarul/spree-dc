// Mobile Bottom Navigation JavaScript
document.addEventListener('DOMContentLoaded', function() {
  const mobileNav = document.getElementById('mobile-bottom-nav');
  const navLinks = mobileNav?.querySelectorAll('a');

  if (!mobileNav || !navLinks.length) return;

  // Add click event listeners for smooth transitions
  navLinks.forEach(link => {
    link.addEventListener('click', function(e) {
      // Add visual feedback
      this.style.transform = 'scale(0.95)';
      setTimeout(() => {
        this.style.transform = '';
      }, 150);
    });
  });

  // Update cart count when cart is updated via Turbo/AJAX
  document.addEventListener('turbo:render', function() {
    updateCartBadge();
  });

  // Listen for cart update events
  document.addEventListener('cart:updated', function(event) {
    updateCartBadge();
  });

  function updateCartBadge() {
    // This function can be called when cart is updated via AJAX
    // The badge will be automatically updated on next page load
    // but this provides immediate feedback
    const cartLink = mobileNav.querySelector('a[href*="cart"]');
    const cartBadge = cartLink?.querySelector('.cart-badge');

    if (cartBadge && event.detail && event.detail.itemCount !== undefined) {
      const count = event.detail.itemCount;
      if (count > 0) {
        cartBadge.textContent = count > 9 ? '9+' : count.toString();
        cartBadge.style.display = 'flex';
      } else {
        cartBadge.style.display = 'none';
      }
    }
  }

  // Keep navigation always visible (static) - disabled auto-hide functionality
  // The navigation will remain fixed at the bottom at all times on mobile

  // Ensure navigation is always visible on mobile
  if (window.innerWidth < 768) {
    mobileNav.style.transform = 'translateY(0)';
    mobileNav.style.position = 'fixed';
    mobileNav.style.bottom = '0';
  }

  // Show navigation when window is resized
  window.addEventListener('resize', function() {
    if (window.innerWidth >= 768) {
      mobileNav.style.transform = '';
    } else {
      mobileNav.style.transform = 'translateY(0)';
      mobileNav.style.position = 'fixed';
      mobileNav.style.bottom = '0';
    }
  });
});

// Custom event for cart updates (can be triggered from other parts of the app)
function triggerCartUpdate(itemCount) {
  const event = new CustomEvent('cart:updated', {
    detail: { itemCount: itemCount }
  });
  document.dispatchEvent(event);
}