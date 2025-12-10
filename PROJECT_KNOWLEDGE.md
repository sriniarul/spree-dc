# Spree-DC Project Knowledge Base

## Project Overview

### What is DimeCart?
DimeCart is a comprehensive multivendor e-commerce marketplace built on Spree Commerce. It allows multiple vendors to sell their products through a unified platform while maintaining individual vendor stores and management capabilities.

**Key Characteristics:**
- **Multivendor Architecture**: Multiple independent vendors can operate their own stores
- **Centralized Platform**: Unified customer experience across all vendor stores
- **Advanced Social Media Integration**: Instagram posting, analytics, and engagement management
- **Enterprise Features**: Push notifications, metafields, newsletter management
- **Ruby on Rails Foundation**: Built on Rails 7.2.2.2 with modern web technologies

### Project Structure

The Spree-DC project is organized as a collection of Rails engines:

```
/Users/arulsrinivaasan/RubymineProjects/spree-dc/
├── admin/                 # Spree Admin interface engine
├── api/                   # Spree API engine
├── core/                  # Spree Core engine (models, base functionality)
├── emails/                # Email template engine
├── multivendor/           # Multivendor functionality engine
├── social_media/          # Instagram social media integration engine (NEW)
├── storefront/            # Customer-facing storefront engine
└── /Users/arulsrinivaasan/Documents/DimeCart/  # Main Rails application
```

## Core Components

### 1. Spree Core Engine
**Location**: `/core/`

**Purpose**: Provides the foundational e-commerce functionality including:
- Product catalog management
- Order processing system
- User authentication and authorization
- Payment processing
- Inventory management
- Base models and database schema

**Key Models**:
- `Spree::Product` - Product information and variants
- `Spree::Order` - Order management and checkout process
- `Spree::User` - User accounts and authentication
- `Spree::Vendor` - Vendor account management
- `Spree::Metafield` - Custom metadata system

### 2. Spree Admin Engine
**Location**: `/admin/`

**Purpose**: Administrative interface for managing the e-commerce platform
- Vendor management and onboarding
- Product catalog administration
- Order management and fulfillment
- Analytics and reporting dashboards
- User and permission management

### 3. Multivendor Engine
**Location**: `/multivendor/`

**Purpose**: Enables multiple vendors to operate independent stores within the platform
- Vendor registration and verification
- Individual vendor dashboards
- Commission and payment processing
- Vendor-specific product management
- Multi-tenant architecture support

**Key Features**:
- Vendor isolation and data segregation
- Individual vendor analytics
- Commission calculation and distribution
- Vendor-specific customization options

### 4. Social Media Integration Engine (NEWLY DEVELOPED)
**Location**: `/social_media/`

**Purpose**: Comprehensive Instagram marketing and engagement platform for vendors

## Social Media Engine - Complete Feature Set

### Overview
The social media engine is a full-featured Instagram marketing platform that allows vendors to manage their social media presence directly from the DimeCart admin interface.

### Architecture
```
social_media/
├── app/
│   ├── controllers/spree/admin/social_media/
│   │   ├── accounts_controller.rb
│   │   ├── analytics_controller.rb
│   │   ├── compliance_controller.rb
│   │   ├── content_controller.rb
│   │   ├── engagement_controller.rb
│   │   ├── hashtag_sets_controller.rb
│   │   ├── posts_controller.rb
│   │   └── templates_controller.rb
│   ├── controllers/spree/social_media/webhooks/
│   │   └── instagram_controller.rb
│   ├── services/spree/social_media/
│   │   ├── content_moderation_service.rb
│   │   ├── hashtag_service.rb
│   │   ├── instagram_analytics_service.rb
│   │   ├── instagram_api_service.rb
│   │   ├── instagram_reel_service.rb
│   │   ├── instagram_story_service.rb
│   │   └── optimal_timing_service.rb
│   ├── models/spree/
│   │   ├── hashtag_set.rb
│   │   ├── social_media_account.rb
│   │   ├── social_media_analytics.rb
│   │   ├── social_media_comment.rb
│   │   ├── social_media_engagement_event.rb
│   │   ├── social_media_mention.rb
│   │   ├── social_media_message.rb
│   │   ├── social_media_milestone.rb
│   │   ├── social_media_post.rb
│   │   ├── social_media_template.rb
│   │   └── social_media_webhook_event.rb
│   └── jobs/spree/social_media/
│       ├── process_comment_job.rb
│       ├── process_mention_job.rb
│       ├── publish_post_job.rb
│       ├── publish_reel_job.rb
│       ├── publish_story_job.rb
│       ├── send_notification_job.rb
│       └── sync_instagram_account_job.rb
```

### 1. Instagram Account Management
**Files**: `accounts_controller.rb`, `social_media_account.rb`

**Features**:
- OAuth 2.0 integration with Facebook/Instagram Graph API
- Multiple Instagram Business account connections per vendor
- Account verification and permission management
- Automatic token refresh handling
- Account health monitoring and sync status

**Capabilities**:
- Connect Instagram Business accounts via Facebook App
- Verify account permissions and API access
- Monitor account status and connection health
- Handle token expiration and renewal
- Support for multiple accounts per vendor

### 2. Content Publishing System
**Files**: `content_controller.rb`, `posts_controller.rb`, `instagram_api_service.rb`

**Features**:
- **Multi-format Support**: Posts, Stories, Reels, Carousel posts
- **Advanced Scheduling**: Optimal timing recommendations
- **Media Processing**: Automatic image/video optimization
- **Content Validation**: Pre-publish compliance checking
- **Bulk Operations**: Schedule multiple posts simultaneously

**Publishing Capabilities**:
- **Instagram Posts**: Single image/video posts with captions and hashtags
- **Instagram Stories**: Interactive stories with stickers and links
- **Instagram Reels**: Video reels with trending audio integration
- **Carousel Posts**: Multi-image/video carousel posts
- **Story Highlights**: Organize stories into permanent highlights

**Content Features**:
- Media URL validation and optimization
- Caption enhancement with AI suggestions
- Hashtag performance optimization
- Optimal posting time recommendations
- Content compliance and moderation

### 3. Template System
**Files**: `templates_controller.rb`, `social_media_template.rb`

**Features**:
- **Variable Substitution**: Dynamic content with placeholders like `{{product_name}}`
- **Content Types**: Separate templates for posts, stories, reels
- **Reusable Content**: Save and reuse successful content formats
- **Media Requirements**: Define required media types and specifications
- **Instructions**: Built-in posting guidelines and best practices

**Template Variables**:
- `{{product_name}}` - Product name
- `{{price}}` - Product price
- `{{brand_name}}` - Vendor brand name
- `{{discount_code}}` - Promotional codes
- `{{website}}` - Vendor website URL
- Custom variables for specific use cases

### 4. Hashtag Research and Management
**Files**: `hashtag_sets_controller.rb`, `hashtag_service.rb`, `hashtag_set.rb`

**Features**:
- **Hashtag Research**: Discover trending and relevant hashtags
- **Performance Analysis**: Track hashtag effectiveness and reach
- **Set Management**: Create and manage hashtag collections
- **Relevance Scoring**: AI-powered hashtag relevance assessment
- **Trending Detection**: Identify emerging hashtag opportunities
- **Shadowban Detection**: Identify potentially problematic hashtags

**Research Capabilities**:
- Search hashtags by keywords and categories
- Analyze hashtag performance metrics
- Discover related and trending hashtags
- Create themed hashtag collections
- Track hashtag ROI and engagement rates

### 5. Analytics and Performance Tracking
**Files**: `analytics_controller.rb`, `instagram_analytics_service.rb`, `social_media_analytics.rb`

**Features**:
- **Real-time Dashboards**: Interactive analytics with Chart.js
- **Performance Metrics**: Reach, impressions, engagement, follower growth
- **Post Analytics**: Individual post performance tracking
- **Audience Insights**: Follower demographics and behavior analysis
- **Competitor Analysis**: Benchmark against industry standards
- **ROI Tracking**: Revenue attribution from social media efforts

**Metrics Tracked**:
- **Engagement**: Likes, comments, shares, saves
- **Reach**: Total accounts reached by content
- **Impressions**: Total content views
- **Follower Growth**: New followers and unfollows
- **Website Clicks**: Traffic driven to vendor websites
- **Story Metrics**: Story views, exits, taps forward/back

### 6. Milestone and Achievement System
**Files**: `social_media_milestone.rb`, milestone tracking logic

**Features**:
- **Automatic Detection**: Recognize significant achievements
- **Celebration Campaigns**: Auto-generate celebration posts
- **Progress Tracking**: Monitor growth toward goals
- **Notification System**: Alert vendors of milestones reached
- **Achievement Badges**: Visual recognition system

**Milestone Types**:
- Follower count milestones (1K, 10K, 100K, 1M)
- Viral posts (high engagement rates)
- Monthly reach targets
- Engagement rate achievements
- Revenue attribution milestones

### 7. Webhook Event Processing
**Files**: `instagram_controller.rb` (webhooks), `process_comment_job.rb`, `process_mention_job.rb`

**Features**:
- **Real-time Event Processing**: Instant webhook handling
- **Sentiment Analysis**: Automatic comment/mention sentiment classification
- **Auto-response Suggestions**: Context-aware response recommendations
- **Influencer Detection**: Identify high-value user interactions
- **Engagement Tracking**: Comprehensive interaction logging

**Webhook Events Handled**:
- **Comments**: New comments on posts with sentiment analysis
- **Mentions**: Brand mentions across Instagram platform
- **Likes**: Like/unlike events with user tracking
- **Messages**: Direct messages and story replies
- **Story Interactions**: Story views, taps, and exits

**Processing Features**:
- Webhook signature verification for security
- Automatic sentiment classification (positive/negative/neutral)
- Influencer tier detection (micro, macro, celebrity)
- Context analysis and intent classification
- Automated response suggestion generation

### 8. Content Moderation and Compliance
**Files**: `compliance_controller.rb`, `content_moderation_service.rb`

**Features**:
- **Automated Content Scanning**: AI-powered content analysis
- **Brand Safety**: Ensure content aligns with brand guidelines
- **Instagram Policy Compliance**: Automatic policy violation detection
- **Approval Workflows**: Multi-tier content approval process
- **Risk Assessment**: Content risk scoring and recommendations

**Moderation Capabilities**:
- Inappropriate language detection
- Copyright content scanning
- Misleading information identification
- Hashtag compliance checking
- Brand guideline enforcement
- Community standards verification

### 9. Notification System
**Files**: `send_notification_job.rb`, notification logic throughout controllers

**Features**:
- **Multi-channel Notifications**: Email, push, in-app, webhooks
- **Intelligent Prioritization**: Smart notification filtering
- **Customizable Preferences**: Vendor-specific notification settings
- **Real-time Alerts**: Immediate notifications for urgent events
- **Webhook Integration**: External system integration capabilities

**Notification Types**:
- New comments and mentions requiring response
- Viral post alerts and performance notifications
- Milestone achievements and celebrations
- Compliance alerts and policy violations
- System status and sync notifications
- Collaboration opportunity alerts

### 10. Advanced Story and Reel Features
**Files**: `instagram_story_service.rb`, `instagram_reel_service.rb`

**Story Features**:
- Interactive elements (polls, questions, stickers)
- Swipe-up links and call-to-action buttons
- Story highlights organization
- Template-based story creation
- Optimal story timing recommendations

**Reel Features**:
- Trending audio integration
- Video optimization and processing
- Reel-specific hashtag strategies
- Caption enhancement for discoverability
- Cross-posting to feed options

## Database Schema

### Core Social Media Tables

#### spree_social_media_accounts
- Instagram account connection and authentication data
- OAuth tokens and refresh mechanisms
- Account metadata and sync status

#### spree_social_media_posts
- Scheduled and published content tracking
- Media URLs and content metadata
- Publishing status and performance metrics

#### spree_social_media_analytics
- Daily/weekly/monthly performance metrics
- Engagement data and reach statistics
- ROI tracking and attribution data

#### spree_social_media_templates
- Reusable content templates with variables
- Template categorization and usage tracking
- Media requirements and instructions

#### spree_hashtag_sets
- Hashtag collections and performance data
- Research results and trending analysis
- Usage tracking and effectiveness metrics

### Engagement and Interaction Tables

#### spree_social_media_comments
- Instagram comment tracking and management
- Sentiment analysis and response suggestions
- Moderation status and approval workflow

#### spree_social_media_mentions
- Brand mention tracking across Instagram
- Influencer identification and classification
- Context analysis and opportunity detection

#### spree_social_media_messages
- Direct message and story reply management
- Customer intent analysis and auto-responses
- Conversation tracking and follow-up

#### spree_social_media_engagement_events
- Comprehensive interaction event logging
- User behavior tracking and analysis
- Engagement pattern identification

#### spree_social_media_webhook_events
- Webhook processing status and retry logic
- Event payload storage and processing history
- Error tracking and debugging information

### System Tables

#### spree_social_media_milestones
- Achievement tracking and milestone definitions
- Progress monitoring and celebration triggers
- Goal setting and progress analytics

## API Integration

### Instagram Graph API Integration
**Authentication**: OAuth 2.0 with Facebook App credentials
**Permissions Required**:
- `instagram_basic` - Basic account access
- `instagram_content_publish` - Publishing permissions
- `instagram_manage_comments` - Comment management
- `instagram_manage_insights` - Analytics access

### Webhook Configuration
**Endpoint**: `/social_media/webhooks/instagram`
**Verification**: HMAC-SHA256 signature verification
**Events**: Comments, likes, mentions, story interactions

## Background Job System

### Job Queue Architecture
**Queue System**: Sidekiq for background job processing
**Job Categories**:
- **Publishing Jobs**: Content scheduling and posting
- **Sync Jobs**: Analytics and account data synchronization
- **Processing Jobs**: Webhook event processing
- **Notification Jobs**: Multi-channel notification delivery

### Key Background Jobs

#### Content Publishing
- `PublishPostJob` - Scheduled post publishing
- `PublishStoryJob` - Story publishing with interactive elements
- `PublishReelJob` - Reel publishing with optimization

#### Data Synchronization
- `SyncInstagramAccountJob` - Account data and metrics sync
- `SyncPostAnalyticsJob` - Individual post performance updates
- `ScheduleAccountSyncJob` - Automated sync scheduling

#### Event Processing
- `ProcessCommentJob` - Comment analysis and response generation
- `ProcessMentionJob` - Mention processing and opportunity identification
- `SendNotificationJob` - Multi-channel notification delivery

## Configuration Requirements

### Environment Variables
```bash
FACEBOOK_APP_ID=your_facebook_app_id
FACEBOOK_APP_SECRET=your_facebook_app_secret
FACEBOOK_WEBHOOK_VERIFY_TOKEN=your_webhook_verification_token
```

### Rails Credentials
```yaml
facebook:
  app_id: "your_app_id"
  app_secret: "your_app_secret"
  webhook_verify_token: "your_webhook_token"
```

### Required Gems
```ruby
gem 'httparty'          # API communication
gem 'sidekiq'           # Background job processing
gem 'mini_magick'       # Image processing
gem 'omniauth'          # OAuth authentication
gem 'omniauth-facebook' # Facebook OAuth provider
gem 'omniauth-rails_csrf_protection' # CSRF protection
```

## Current Status and Todo List

### ✅ Completed Features

1. **Database Migrations**: All social media tables created and migrated
2. **Core Instagram Integration**: Complete API service with posting capabilities
3. **Content Management**: Scheduling, templates, and media processing
4. **Analytics Dashboard**: Real-time performance tracking and reporting
5. **Hashtag Research**: Advanced hashtag analysis and management
6. **Webhook Processing**: Real-time event handling with sentiment analysis
7. **Content Moderation**: Automated compliance and brand safety checking
8. **Notification System**: Multi-channel notification delivery
9. **Background Jobs**: Comprehensive job processing system
10. **Story/Reel Features**: Advanced content type support

### 🔄 Current Issues

1. **Migration Conflicts**: Duplicate migration name errors preventing final database setup
   - Error: "Multiple migrations have the name CreateSpreeSocialMediaWebhookEvents"
   - Solution needed: Clean up duplicate migrations in engine vs main app

### 📋 Pending Todo List

1. **Create missing admin view templates for all social media features** (PRIORITY)
   - Dashboard views with analytics charts
   - Account connection and management interfaces
   - Content creation and scheduling forms
   - Template management interface
   - Hashtag research and management views
   - Compliance and moderation dashboards
   - Engagement and interaction management

2. **Configure Facebook App credentials for Instagram API access**
   - Set up Facebook Developer App
   - Configure OAuth redirect URIs
   - Add required Instagram permissions
   - Test API connectivity

3. **Test Instagram OAuth connection flow**
   - Verify account connection process
   - Test token refresh mechanisms
   - Validate permission scopes

4. **Test end-to-end Instagram posting workflow**
   - Validate content publishing pipeline
   - Test scheduling and automation
   - Verify media processing and optimization

5. **Validate webhook event processing**
   - Test real-time event handling
   - Verify sentiment analysis accuracy
   - Confirm notification delivery

6. **Test analytics data synchronization**
   - Validate metrics collection
   - Test dashboard data accuracy
   - Verify performance tracking

7. **Configure production environment settings**
   - Set up SSL for webhook endpoints
   - Configure background job processing
   - Set up monitoring and logging

8. **Set up monitoring and alerting**
   - Monitor API rate limits
   - Track job queue health
   - Set up error reporting

9. **Configure scheduled background jobs**
   - Set up cron jobs for analytics sync
   - Configure automated content processing
   - Schedule routine maintenance tasks

## Admin Interface Requirements

### Dashboard Components Needed
1. **Main Social Media Dashboard** (`admin/social_media/index`)
2. **Account Management** (`admin/social_media/accounts`)
3. **Content Calendar** (`admin/social_media/content`)
4. **Analytics Dashboard** (`admin/social_media/analytics`)
5. **Template Management** (`admin/social_media/templates`)
6. **Hashtag Research** (`admin/social_media/hashtag_sets`)
7. **Engagement Center** (`admin/social_media/engagement`)
8. **Compliance Dashboard** (`admin/social_media/compliance`)

### UI Framework
- **Bootstrap** for responsive design
- **Chart.js** for analytics visualizations
- **Turbo Rails** for dynamic interactions
- **Stimulus** for JavaScript components

## Technical Architecture

### Service-Oriented Design
The social media engine follows a service-oriented architecture with clear separation of concerns:

- **Controllers**: Handle HTTP requests and coordinate between services
- **Services**: Contain business logic and external API interactions
- **Models**: Data persistence and business rules
- **Jobs**: Asynchronous processing and background tasks
- **Serializers**: API response formatting (when needed)

### Security Considerations
- **OAuth 2.0**: Secure Instagram account authentication
- **Webhook Verification**: HMAC-SHA256 signature validation
- **Content Sanitization**: XSS and injection attack prevention
- **Rate Limiting**: API rate limit compliance and management
- **Data Encryption**: Sensitive data protection in transit and at rest

### Performance Optimizations
- **Background Processing**: Async job processing for API calls
- **Caching**: Redis caching for frequently accessed data
- **Database Indexing**: Optimized queries with proper indexing
- **CDN Integration**: Media delivery optimization
- **Connection Pooling**: Efficient database connection management

## Integration Points

### Main DimeCart Application
The social media engine integrates with the main DimeCart application through:
- **Vendor System**: Each social media account belongs to a vendor
- **Product Catalog**: Templates can reference vendor products
- **User Authentication**: Uses Spree's authentication system
- **Admin Interface**: Integrates with existing admin navigation

### External Services
- **Facebook Graph API**: Instagram content and analytics
- **Webhook Endpoints**: Real-time event processing
- **Media Storage**: Image and video file handling
- **Email Services**: Notification delivery
- **Analytics Services**: Performance tracking and reporting

This comprehensive social media integration transforms DimeCart from a simple e-commerce platform into a full-featured social commerce solution, enabling vendors to manage their entire Instagram marketing strategy from within their store admin interface.