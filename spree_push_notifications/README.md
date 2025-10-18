# Spree Push Notifications

A comprehensive push notifications extension for Spree Commerce that enables web push notifications using the Web Push API and service workers.

## Features

- 🚀 **Web Push API Integration**: Uses modern web standards for push notifications
- 📱 **Cross-Platform Support**: Works on desktop and mobile browsers
- 🔧 **Easy Integration**: Simple setup with automatic registration prompts
- 🎯 **Targeted Messaging**: Send notifications to specific users or broadcast to all
- 📊 **Analytics & Management**: Track subscription statistics and manage cleanup
- 🎨 **Customizable UI**: Styled notification banners with responsive design
- 🌐 **Internationalization**: Support for multiple languages

## Browser Support

- Chrome (desktop & mobile)
- Firefox (desktop & mobile)
- Edge
- Safari (macOS & iOS with PWA installation)
- Opera

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'spree_push_notifications'
```

And then execute:

```bash
bundle install
```

Run the generator:

```bash
rails generate spree_push_notifications:install
```

This will:
- Add required JavaScript and CSS imports
- Copy the service worker file
- Install database migrations
- Show setup instructions

## Setup

### 1. Generate VAPID Keys

VAPID keys are required for push notifications:

```bash
rails spree_push_notifications:generate_vapid_keys
```

### 2. Environment Variables

Add the generated keys to your environment:

```bash
VAPID_PUBLIC_KEY=your_generated_public_key
VAPID_PRIVATE_KEY=your_generated_private_key
VAPID_SUBJECT=mailto:your_email@domain.com
```

### 3. Run Migrations

```bash
rails db:migrate
```

### 4. Add Notification Banner

Add the notification banner to your layout file (e.g., `app/views/layouts/application.html.erb`):

```erb
<%= render 'spree/shared/push_notification_banner' %>
```

## Usage

### Basic Notification Sending

```ruby
# Send to a specific user
Spree::PushNotificationService.send_to_user(
  user,
  "Order Shipped!",
  "Your order #12345 has been shipped and is on its way.",
  { url: "/orders/12345", icon: "/shipping-icon.png" }
)

# Send to a specific subscription
subscription = Spree::PushSubscription.first
Spree::PushNotificationService.send_to_subscription(
  subscription,
  "Flash Sale!",
  "50% off everything for the next 2 hours!"
)

# Broadcast to all subscribers
Spree::PushNotificationService.broadcast(
  "New Collection Launch",
  "Check out our latest summer collection now available!",
  { url: "/collections/summer-2024" }
)
```

### Notification Options

You can customize notifications with these options:

```ruby
options = {
  icon: '/custom-icon.png',    # Custom notification icon
  badge: '/badge-icon.png',    # Badge icon (Android)
  url: '/custom-path'          # URL to open when clicked
}
```

### JavaScript API

Access push notification functions from JavaScript:

```javascript
// Request permission manually
window.SpreePushNotifications.requestPermission();

// Show the notification banner
window.SpreePushNotifications.showBanner();

// Check subscription status
navigator.serviceWorker.ready.then(function(registration) {
  window.SpreePushNotifications.checkSubscription(registration);
});
```

## Management & Maintenance

### Statistics

View subscription statistics:

```bash
rails spree_push_notifications:stats
```

### Cleanup

Remove old subscriptions (older than 6 months):

```bash
rails spree_push_notifications:cleanup
```

### Testing

Test your push notification setup:

```bash
rails spree_push_notifications:test
```

## Customization

### Styling

The notification banner can be customized via CSS:

```css
#spree-push-notification-banner {
  /* Custom styles */
  background-color: your-brand-color;
  border-radius: 12px;
}

#spree-notification-allow {
  /* Customize the allow button */
  background-color: your-accent-color;
}
```

### Internationalization

Add translations to your locale files:

```yaml
# config/locales/en.yml
en:
  spree_push_notifications:
    banner:
      title: "Stay Updated"
      message: "Get notifications about special offers and order updates"
      allow: "Allow"
      deny: "Not Now"
      success: "Notifications enabled! Thank you."
```

### Service Worker Customization

You can extend the service worker by modifying `public/service-worker.js`:

```javascript
// Add custom notification handling
self.addEventListener('push', (event) => {
  // Your custom logic here
});
```

## Database Schema

The gem adds a `spree_push_subscriptions` table:

| Column | Type | Description |
|--------|------|-------------|
| user_id | integer | Associated user (optional) |
| endpoint | text | Push service endpoint |
| p256dh | string | Encryption key |
| auth | string | Authentication secret |
| last_used_at | datetime | Last successful notification |

## API Endpoints

The gem provides these API endpoints:

- `GET /api/push/public-key` - Get VAPID public key
- `POST /api/push/subscribe` - Create/update subscription
- `GET /api/push/test-push` - Send test notification

## Security

- All communications use HTTPS
- VAPID keys provide authentication
- Subscriptions are validated before storage
- Expired/invalid subscriptions are automatically cleaned up

## Development

After checking out the repo, run:

```bash
bundle install
bundle exec rake test_app  # Creates test Rails app
bundle exec rspec         # Run tests
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

This gem is licensed under the BSD 3-Clause License.