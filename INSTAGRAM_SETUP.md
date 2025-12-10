# Instagram Business Integration Setup Guide

## Important: Understanding Facebook App + Instagram

When you create a Facebook App and add Instagram as a product, you **DO NOT** get separate Instagram App credentials. Here's what you actually have:

- **One Facebook App** with one App ID and one App Secret
- **Instagram as a Product** within that Facebook App (uses the same credentials)
- Instagram Business accounts must be connected to a Facebook Page

## Prerequisites

1. **Instagram Business Account**
   - Convert from personal account if needed (Instagram App → Settings → Account → Switch to Professional → Business)
   - Must be a Business account, not Creator account

2. **Facebook Page**
   - Create a Facebook Page if you don't have one
   - The Page will be used to connect your Instagram Business account

3. **Link Instagram to Facebook Page**
   - Instagram Settings → Account → Linked Accounts → Facebook
   - Connect to your Facebook Page

4. **Facebook Developer Account**
   - Sign up at https://developers.facebook.com/

## Step 1: Facebook App Setup

### 1.1 Create Facebook App

1. Visit: https://developers.facebook.com/apps/
2. Click **"Create App"**
3. Select **"Business"** as app type
4. Fill in app details:
   - App Name: "YourCompany Social Media Manager" (or similar)
   - App Contact Email: your email
   - Business Account: Select or create one
5. Click **"Create App"**
6. **Save your credentials**:
   - App ID: `1234567890` (example)
   - App Secret: Click "Show" to reveal, copy and save securely

### 1.2 Add Products to Your App

Add these products to your Facebook App:

1. **Facebook Login** ✓
   - Click "Set Up" on Facebook Login
   - No additional configuration needed initially

2. **Instagram** ✓
   - Look for the product called **"Instagram"** (not "Instagram Basic Display" - that's deprecated!)
   - Description: *"Allow creators and businesses to manage messages and comments, publish content, track insights, hashtags and mentions."*
   - This gives you access to Instagram Platform APIs
   - Allows posting, analytics, comment management, messaging

**Important Notes**:
- The product is simply called **"Instagram"** (Facebook changed the naming in 2024)
- DO NOT use "Instagram Basic Display API" (deprecated December 2024)
- You only add Instagram as a **product** within your Facebook App, not as a separate app
- Use the same Facebook App ID and Secret for Instagram integration

### 1.3 Configure OAuth Redirect URIs

1. Go to **Facebook Login → Settings**
2. Add to **Valid OAuth Redirect URIs**:
   ```
   http://localhost:3000/auth/facebook/callback
   https://yourdomain.com/auth/facebook/callback
   ```
3. Click **Save Changes**

## Step 2: Request Required Permissions

### 2.1 Add Permissions to Your App

1. Go to **App Settings → Basic → App Review → Permissions and Features**
2. Request these permissions:
   - `pages_show_list` - To list Facebook Pages
   - `pages_read_engagement` - To read Page engagement data
   - `pages_manage_posts` - To create posts on Pages
   - `instagram_basic` - Basic Instagram profile access
   - `instagram_content_publish` - To publish content to Instagram
   - `instagram_manage_comments` - To manage Instagram comments
   - `instagram_manage_insights` - To access Instagram analytics
   - `business_management` - To access business integrations

### 2.2 App Review (For Production)

**Development Mode** (immediate):
- Only developers/testers listed in the app can use it
- Limited to 25 API calls per hour per user
- Perfect for testing

**Production Mode** (requires review):
- Submit app for Facebook review
- Provide detailed use case and demo video
- Once approved, public users can connect their accounts
- Higher rate limits

## Step 3: Rails Application Configuration

You have **ONE set of credentials** (Facebook App ID and Secret). Use these for both Facebook and Instagram integration.

### Option A: Rails Credentials (Recommended)

```bash
# Edit credentials file
EDITOR="nano" bundle exec rails credentials:edit
```

Add these lines:
```yaml
facebook:
  app_id: "1234567890"  # Your Facebook App ID
  app_secret: "your_facebook_app_secret_here"

google:
  client_id: "your_google_client_id"  # For YouTube (optional)
  client_secret: "your_google_client_secret"
```

Save and close the file.

### Option B: Environment Variables

Add to your `.env` file or environment:
```bash
FACEBOOK_APP_ID="1234567890"
FACEBOOK_APP_SECRET="your_facebook_app_secret_here"

# Optional: For localhost development
APP_URL="http://localhost:3000"

# Optional: For YouTube integration
GOOGLE_CLIENT_ID="your_google_client_id"
GOOGLE_CLIENT_SECRET="your_google_client_secret"
```

## Step 4: Install and Run Migrations

```bash
# Navigate to your Rails app root
cd /path/to/your/rails/app

# Install dependencies
bundle install

# Run migrations (if not already run)
bundle exec rails db:migrate

# Restart your Rails server
bundle exec rails server
```

## Step 5: Connect Instagram Account

### 5.1 As a Vendor:

1. **Login to your admin panel**
   - Navigate to `http://localhost:3000/admin`
   - Sign in with vendor credentials

2. **Navigate to Social Media section**
   - Go to **Admin → Social Media** or **Admin → Marketing → Social Media**

3. **Connect Instagram**
   - Click **"Connect Account"** → **"Instagram"**
   - You'll be redirected to Facebook OAuth

4. **Facebook OAuth Flow**:
   - Login with your Facebook account (must be admin of the Facebook Page)
   - Grant permissions to the app
   - Select the Facebook Page that's linked to your Instagram Business account
   - Click **"Continue"**

5. **Confirmation**:
   - System will automatically detect the Instagram Business account connected to your Page
   - You'll see: "Facebook page 'Your Page Name' connected successfully!"
   - If Instagram is linked: "Instagram account @yourusername also connected!"

### 5.2 What Happens Behind the Scenes:

1. **OAuth Token Exchange**:
   - User authenticates with Facebook
   - System receives User Access Token
   - System retrieves all Facebook Pages managed by the user
   - For the selected Page, system gets the **Page Access Token**

2. **Instagram Business Account Detection**:
   - System queries the Page's linked Instagram Business account
   - Retrieves Instagram account details (ID, username, followers)
   - Stores the **Page Access Token** (this is what we use for Instagram API calls)

3. **Token Storage**:
   - Page Access Token is stored for making API calls
   - Token metadata includes Facebook Page ID, Instagram account ID
   - Both Facebook and Instagram accounts are now connected

## Step 6: Publishing Content

### 6.1 Create a Post

1. Go to **Admin → Social Media → Posts**
2. Click **"New Post"**
3. Fill in:
   - Caption
   - Upload media (image or video)
   - Select accounts (Instagram, Facebook, or both)
   - Choose to post now or schedule
4. Click **"Publish"** or **"Schedule"**

### 6.2 Supported Content Types

- **Instagram Feed Posts**: Single image/video
- **Instagram Carousel**: Multiple images (up to 10)
- **Instagram Stories**: 24-hour disappearing content
- **Instagram Reels**: Short-form video content
- **Facebook Posts**: Text, images, videos, links

## Instagram Graph API Endpoints Used

```
Base URL: https://graph.facebook.com/v22.0

# Account info
GET /{instagram-business-account-id}?fields=id,username,account_type

# Get connected Instagram account
GET /{facebook-page-id}?fields=instagram_business_account

# Create media container
POST /{instagram-business-account-id}/media

# Publish media
POST /{instagram-business-account-id}/media_publish

# Get account insights
GET /{instagram-business-account-id}/insights

# Get media list
GET /{instagram-business-account-id}/media
```

## Development vs Production

### Development Mode (Default)

**Limitations**:
- Only app developers/testers can connect accounts
- Limited to 25 API calls per hour per user
- Instagram Graph API has stricter content rules

**Add Testers**:
1. Go to **App Roles → Roles**
2. Add testers by Facebook user ID or email
3. They must accept the invitation

### Production Mode

**Requirements for App Review**:
1. **Privacy Policy URL** - Host a privacy policy
2. **Terms of Service URL** - Terms of service document
3. **App Icon** - 1024x1024px app icon
4. **Business Verification** - Verify your business
5. **Use Case Documentation**:
   - Detailed description of how you use Instagram API
   - Screen recordings showing the flow
   - Explanation of why you need each permission

**Submission**:
1. Go to **App Review → Permissions and Features**
2. Request each permission
3. Fill in use case details
4. Submit for review
5. Wait 3-7 business days for approval

## Troubleshooting

### Common Issues

**1. "No Facebook pages found"**
- **Cause**: Your Facebook account doesn't manage any Pages
- **Solution**: Create a Facebook Page first

**2. "No Instagram Business account found"**
- **Cause**: Instagram account not linked to Facebook Page, or not a Business account
- **Solution**:
  - Convert Instagram to Business account
  - Link to Facebook Page in Instagram settings

**3. "Invalid OAuth2 access token"**
- **Cause**: Token expired or invalid
- **Solution**: Reconnect the account to refresh token

**4. "Application request limit reached"**
- **Cause**: Exceeded API rate limits
- **Solution**: Wait or request higher limits in production mode

**5. "OAuth redirect URI mismatch"**
- **Cause**: Callback URL not whitelisted
- **Solution**: Add exact callback URL to Facebook App settings

### Debug Steps

1. **Check Instagram Account Type**:
   - Open Instagram app
   - Go to Settings → Account
   - Should say "Professional Account" with Business icon

2. **Verify Facebook Page Connection**:
   - Instagram Settings → Linked Accounts → Facebook
   - Should show your Page name

3. **Test Facebook App**:
   - Go to developers.facebook.com/tools/explorer/
   - Select your app
   - Get a token and test API calls

4. **Check Rails Logs**:
   ```bash
   tail -f log/development.log
   ```
   Look for OAuth flow logs and error messages

5. **Test OAuth Flow**:
   - Visit: `http://localhost:3000/auth/facebook`
   - Should redirect to Facebook
   - Check for any error messages

## Security Best Practices

1. **Never commit credentials** to version control
2. **Use Rails credentials** or environment variables
3. **Enable HTTPS** in production
4. **Implement CSRF protection** (already configured in OmniAuth)
5. **Regularly refresh tokens** (implement token refresh job)
6. **Validate webhook signatures** (if using webhooks)

## Need Help?

- **Facebook Developer Community**: https://developers.facebook.com/community/
- **Instagram Platform Documentation**: https://developers.facebook.com/docs/instagram-api
- **Graph API Explorer**: https://developers.facebook.com/tools/explorer/
- **App Review Documentation**: https://developers.facebook.com/docs/app-review