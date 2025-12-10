# Spree Social Media Integration

A comprehensive social media management system for Spree Commerce, enabling multivendor marketplaces to manage Instagram content, analytics, and engagement at scale.

## 🚀 Features

### Content Management
- **Instagram Post Publishing**: Create, schedule, and publish posts, carousels, stories, and reels
- **Advanced Scheduling**: Optimal timing recommendations based on audience behavior
- **Content Templates**: Reusable templates with variable substitution
- **Media Processing**: Automatic image/video optimization and validation
- **Bulk Operations**: Schedule and manage multiple posts simultaneously

### Analytics & Insights
- **Real-time Dashboard**: Interactive charts showing performance metrics
- **Post Analytics**: Detailed insights for likes, comments, shares, reach, and impressions
- **Hashtag Analysis**: Performance tracking and trending hashtag discovery
- **Milestone Tracking**: Automatic celebration of achievement milestones
- **Audience Demographics**: Follower insights and engagement patterns

### Engagement Management
- **Real-time Webhooks**: Instant processing of comments, mentions, and messages
- **Auto-moderation**: AI-powered content filtering and spam detection
- **Response Management**: Automated and manual comment/message responses
- **Influencer Detection**: Identify high-value user interactions

### Compliance & Moderation
- **Content Moderation**: Brand safety and Instagram policy compliance
- **Automated Filtering**: Inappropriate content and spam detection
- **Compliance Dashboard**: Risk assessment and violation tracking
- **Brand Guidelines**: Enforce consistent voice and messaging

## 🏗️ System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Admin Panel   │    │   Background     │    │   Instagram     │
│                 │◄──►│   Jobs Queue     │◄──►│   Graph API     │
│   (Web UI)      │    │   (Sidekiq)      │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Controllers   │    │   Services       │    │   Webhook       │
│   - Content     │◄──►│   - API Client   │◄──►│   Handlers      │
│   - Analytics   │    │   - Moderation   │    │   (Real-time)   │
│   - Accounts    │    │   - Scheduler    │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌──────────────────┐
│   Models &      │    │   Database       │
│   Associations  │◄──►│   - PostgreSQL   │
│                 │    │   - Indexes      │
└─────────────────┘    └──────────────────┘
```

## 📦 Installation

### 1. Add to Gemfile

```ruby
gem 'spree_social_media', path: 'social_media'
```

### 2. Install Bundle

```bash
bundle install
```

### 3. Install Migrations

```bash
bundle exec rails generate spree_social_media:install
bundle exec rails db:migrate
```

### 4. Add Required Gems

```ruby
# Add to your Gemfile
gem 'omniauth'
gem 'omniauth-facebook'
gem 'omniauth-rails_csrf_protection'
gem 'httparty'
gem 'sidekiq'
gem 'mini_magick'
```

## ⚙️ Configuration

### 1. Facebook Developer App Setup

1. Create a Facebook App at [developers.facebook.com](https://developers.facebook.com)
2. Add Instagram Basic Display product
3. Configure OAuth redirect URIs:
   ```
   https://yourdomain.com/auth/facebook/callback
   ```
4. Add Instagram permissions:
   - `instagram_basic`
   - `instagram_content_publish`
   - `instagram_manage_comments`
   - `instagram_manage_insights`

### 2. Rails Credentials

```bash
# Edit credentials
rails credentials:edit

# Add Facebook/Instagram credentials
facebook:
  app_id: "your_app_id"
  app_secret: "your_app_secret"
  webhook_verify_token: "your_webhook_token"
```

### 3. Environment Variables (Alternative)

```bash
# .env file
FACEBOOK_APP_ID=your_app_id
FACEBOOK_APP_SECRET=your_app_secret
FACEBOOK_WEBHOOK_VERIFY_TOKEN=your_webhook_token
```

### 4. Webhook Configuration

Set up webhook endpoints in your Facebook App:
```
POST https://yourdomain.com/social_media/webhooks/instagram
```

Webhook verification token should match your configured token.

## 🎯 Usage

### Connecting Instagram Account

1. Navigate to Admin → Social Media → Accounts
2. Click "Connect Instagram Account"
3. Complete OAuth flow
4. Account will be synced automatically

### Publishing Content

```ruby
# Create a post
post = current_vendor.social_media_posts.build(
  platform: 'instagram',
  content_type: 'post',
  caption: 'Check out our new product! #newlaunch',
  media_urls: ['https://example.com/image.jpg'],
  scheduled_for: 1.hour.from_now
)

# Validate content
service = Spree::SocialMedia::ContentModerationService.new(account)
validation = service.moderate_content(post.attributes)

if validation[:passed]
  post.save!
  # Will be automatically published at scheduled time
end
```

### Analytics Access

```ruby
# Get account analytics
analytics = Spree::SocialMedia::InstagramAnalyticsService.new(account)
dashboard_data = analytics.get_dashboard_data(period: 30.days)

# Post performance
post_analytics = analytics.get_post_analytics(post_id, detailed: true)
```

## 📊 Database Schema

### Core Tables

- `spree_social_media_accounts` - Connected social media accounts
- `spree_social_media_posts` - Content posts and scheduling
- `spree_social_media_analytics` - Performance metrics
- `spree_social_media_templates` - Reusable content templates
- `spree_hashtag_sets` - Hashtag collections and performance

### Engagement Tables

- `spree_social_media_comments` - Instagram comments
- `spree_social_media_mentions` - Brand mentions
- `spree_social_media_messages` - Direct messages
- `spree_social_media_engagement_events` - User interactions

### System Tables

- `spree_social_media_webhook_events` - Webhook event log
- `spree_social_media_milestones` - Achievement tracking

## 🔄 Background Jobs

The system uses Sidekiq for background processing:

### Content Jobs
- `PublishPostJob` - Publishes scheduled content
- `PublishStoryJob` - Publishes Instagram stories
- `PublishReelJob` - Publishes Instagram reels

### Sync Jobs
- `SyncInstagramAccountJob` - Syncs account data
- `SyncPostAnalyticsJob` - Updates post metrics
- `ScheduleAccountSyncJob` - Manages sync scheduling

### Event Processing
- `ProcessCommentJob` - Handles comment events
- `ProcessMentionJob` - Processes brand mentions
- `SendNotificationJob` - Manages notifications

## 🛡️ Security & Compliance

### Content Moderation
- Automatic spam detection
- Inappropriate content filtering
- Brand guideline enforcement
- Instagram policy compliance checking

### Data Protection
- Secure token storage
- Webhook signature verification
- Rate limiting protection
- Audit logging

## 📈 Monitoring & Health Checks

### Built-in Monitoring
```ruby
# Check system health
health_check = Spree::SocialMediaWebhookEvent.webhook_health_check
puts health_check[:status] # 'healthy', 'warning', or 'unhealthy'

# Account sync status
account.last_synced_at
account.last_sync_error
```

### Recommended Monitoring Setup
- Monitor Sidekiq queue sizes
- Track webhook processing success rates
- Alert on API rate limit approaches
- Monitor content moderation metrics

## 🚀 Production Deployment

### 1. SSL Configuration
Ensure SSL is properly configured for webhook endpoints.

### 2. Background Job Processing
```bash
# Start Sidekiq
bundle exec sidekiq -C config/sidekiq.yml
```

### 3. Scheduled Jobs
Add to cron or use a job scheduler:
```bash
# Every 4 hours - sync all accounts
0 */4 * * * cd /path/to/app && bundle exec rails runner "Spree::SocialMedia::ScheduleAccountSyncJob.perform_now"
```

### 4. Webhook Endpoints
Configure your production domain in Facebook App settings.

## 🔧 Troubleshooting

### Common Issues

**OAuth Connection Failed**
- Verify App ID and Secret are correct
- Check redirect URI configuration
- Ensure SSL is properly configured

**Webhook Not Receiving Events**
- Verify webhook URL is accessible
- Check webhook verification token
- Ensure proper SSL certificate

**Posts Not Publishing**
- Check Instagram API permissions
- Verify content passes moderation
- Check Sidekiq job processing

**Analytics Not Syncing**
- Verify account has analytics permissions
- Check for API rate limits
- Review sync job logs

### Debug Commands

```bash
# Check webhook events
rails console
Spree::SocialMediaWebhookEvent.recent.limit(10)

# Test API connection
account = Spree::SocialMediaAccount.first
service = Spree::SocialMedia::InstagramApiService.new(account.access_token)
result = service.get_account_info(account.platform_account_id)

# Check job status
require 'sidekiq/api'
Sidekiq::Queue.new('social_media').size
```

## 📚 API Documentation

### REST Endpoints

**Accounts**
- `GET /admin/social_media/accounts` - List accounts
- `POST /admin/social_media/accounts` - Connect new account
- `DELETE /admin/social_media/accounts/:id` - Disconnect account

**Content**
- `POST /admin/social_media/content/create_post` - Create post
- `POST /admin/social_media/posts/:id/schedule` - Schedule post
- `GET /admin/social_media/analytics/dashboard` - Analytics data

### Webhook Events

The system processes these Instagram webhook events:
- `comments` - New comments on posts
- `likes` - Like/unlike events
- `mentions` - Brand mentions
- `story_insights` - Story performance data

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:
- Create an issue on GitHub
- Check the troubleshooting section
- Review the API documentation

---

**Built with ❤️ for Spree Commerce multivendor marketplaces**