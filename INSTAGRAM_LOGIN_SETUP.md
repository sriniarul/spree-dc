# Instagram API with Instagram Login - Complete Setup Guide

## 🎯 What Changed?

As of January 2025, we've migrated from the **Facebook-based Instagram integration** to the **Instagram API with Instagram Login**. This is simpler, more direct, and doesn't require Facebook Pages.

### Key Differences:

| Old (Facebook Login) | New (Instagram Login) |
|---------------------|----------------------|
| Required Facebook Page | ❌ No Facebook Page needed |
| Only Business accounts | ✅ Business OR Creator accounts |
| Complex token flow | ✅ Direct Instagram OAuth |
| Page Access Tokens | ✅ Instagram User Access Tokens |
| Facebook Graph API | ✅ Instagram Graph API |

---

## 📋 Prerequisites

### 1. Instagram Account Setup

**Convert to Professional Account**:
1. Open Instagram app
2. Go to Settings → Account
3. Tap "Switch to Professional Account"
4. Choose "Business" or "Creator"

**Verify Account Type**:
- Settings should show "Professional Account"
- Either Business or Creator type works

### 2. Facebook Developer Account

1. Visit: https://developers.facebook.com/
2. Sign up or log in
3. Complete account setup

---

## 🚀 Step 1: Create Facebook App

### 1.1 Create New App

1. Go to: https://developers.facebook.com/apps/
2. Click **"Create App"**
3. Select **"Business"** as app type
4. Fill in details:
   - **App Name**: "YourCompany Social Media Manager"
   - **App Contact Email**: your.email@example.com
   - **Business Account**: Select or create one
5. Click **"Create App"**

### 1.2 Save Your Credentials

After creating the app, you'll see:

**Instagram App ID**: `1152513693112724` (example - yours will be different)
**Instagram App Secret**: Click "Show" to reveal

⚠️ **IMPORTANT**: Save both of these securely. You'll need them for configuration.

---

## 🔌 Step 2: Add Instagram Product

### 2.1 Add Product

1. In your app dashboard, click **"Add Product"**
2. Find **"Instagram"** product
   - Description: *"Allow creators and businesses to manage messages and comments, publish content, track insights, hashtags and mentions."*
3. Click **"Set Up"**

**Note**: Look for simply **"Instagram"**, NOT:
- ❌ "Instagram Basic Display" (deprecated)
- ❌ "Instagram Graph API" (old name)

### 2.2 Configure Business Login

1. Go to **Instagram → API setup with Instagram business login**
2. You'll see three sections:
   - Generate access tokens
   - Configure webhooks (optional)
   - Set up Instagram business login

### 2.3 Add OAuth Redirect URI

1. Scroll to **"3. Set up Instagram business login"**
2. Click **"Business login settings"**
3. Under **"OAuth redirect URIs"**, add:
   ```
   http://localhost:3000/social_media/oauth/instagram/callback
   https://yourdomain.com/social_media/oauth/instagram/callback
   ```
4. Click **"Save Changes"**

---

## 🔐 Step 3: Configure Rails Application

You need to add your Instagram App credentials to your Rails app.

### Option A: Rails Credentials (Recommended)

```bash
# Edit credentials file
EDITOR="nano" bundle exec rails credentials:edit
```

Add these lines:
```yaml
instagram:
  app_id: "1152513693112724"  # Your Instagram App ID
  app_secret: "your_instagram_app_secret_here"
```

Save and exit (Ctrl+X, then Y, then Enter in nano).

### Option B: Environment Variables

Add to your `.env` file:
```bash
INSTAGRAM_APP_ID="1152513693112724"
INSTAGRAM_APP_SECRET="your_instagram_app_secret_here"
```

Or export directly:
```bash
export INSTAGRAM_APP_ID="1152513693112724"
export INSTAGRAM_APP_SECRET="your_instagram_app_secret_here"
```

---

## ✅ Step 4: Test the Integration

### 4.1 Restart Your Server

```bash
# Kill existing server (Ctrl+C)
# Start fresh
bundle exec rails server
```

### 4.2 Add Instagram Tester Role

**Important for Development Mode**:

1. Go to your Facebook App → **Roles** → **Instagram Testers**
2. Add your Instagram account username
3. On Instagram, go to Settings → Apps and Websites → Tester Invites
4. Accept the invitation

Without this, you'll get authorization errors in development mode.

### 4.3 Connect Instagram Account

1. **Navigate to Admin**:
   - Go to `http://localhost:3000/admin`
   - Sign in as vendor

2. **Go to Social Media**:
   - Click **Admin → Social Media** or **Marketing → Social Media**

3. **Connect Instagram**:
   - Click **"Connect Account"** or **"+ Add Account"**
   - Select **"Instagram"**

4. **Instagram Authorization**:
   - You'll be redirected to Instagram
   - Login with your Instagram credentials
   - Review permissions:
     - `instagram_business_basic` - Basic profile info
     - `instagram_business_content_publish` - Publish content
     - `instagram_business_manage_messages` - Manage messages
     - `instagram_business_manage_comments` - Manage comments
   - Click **"Allow"**

5. **Confirmation**:
   - You'll be redirected back to your app
   - Should see: "Instagram account @yourusername connected successfully!"

---

## 🧪 Step 5: Verify Connection

### 5.1 Check in Admin Panel

- Go to **Admin → Social Media → Accounts**
- You should see your Instagram account listed
- Status should be **"Active"**
- Check that username and account details are correct

### 5.2 Test in Rails Console

```ruby
bundle exec rails console

# Get the Instagram account
account = Spree::SocialMediaAccount.instagram_accounts.last

# Check account details
account.username           # Should show your Instagram username
account.platform_user_id   # Should show Instagram user ID
account.access_token.present?  # Should be true
account.expires_at         # Should be ~60 days from now
account.status             # Should be "active"

# Check token metadata
account.token_metadata['auth_type']  # Should be "instagram_login"
account.token_metadata['account_type']  # Should be "BUSINESS" or "CREATOR"

# Test API connection
service = Spree::SocialMedia::InstagramApiService.new(account)
service.test_connection    # Should return true
```

---

## 📝 Step 6: Publish Test Content

### 6.1 Create a Test Post

1. Go to **Admin → Social Media → Posts**
2. Click **"New Post"** or **"Create Post"**
3. Fill in:
   - **Caption**: "Test post from my social media manager! 🚀"
   - **Media**: Upload an image (JPG/PNG, max 8MB)
   - **Account**: Select your Instagram account
4. Choose **"Post Now"** or **"Schedule"**
5. Click **"Publish"**

### 6.2 Verify on Instagram

- Open Instagram app
- Check your profile
- The post should appear within a few seconds

---

## 🔄 Token Refresh (Automatic)

### How Tokens Work:

- **Short-lived tokens**: Valid for ~1 hour (auto-converted to long-lived)
- **Long-lived tokens**: Valid for 60 days
- **Refresh**: Can be refreshed for another 60 days (must be >24 hours old)

### Automatic Refresh:

The system automatically refreshes tokens that are within 7 days of expiration. A background job runs daily to check all accounts.

### Manual Refresh (if needed):

```ruby
bundle exec rails console

account = Spree::SocialMediaAccount.instagram_accounts.last
service = Spree::SocialMedia::InstagramTokenRefreshService.new(account)

# Check if needs refresh
service.needs_refresh?     # true if within 7 days of expiration
service.can_refresh?       # true if token is >24 hours old

# Refresh token
result = service.refresh_token
result[:success]           # Should be true
result[:expires_at]        # New expiration date
```

---

## 🚨 Troubleshooting

### Issue 1: "OAuth not configured"

**Cause**: Instagram App credentials not set

**Solution**:
```bash
# Check if credentials are set
bundle exec rails console
Rails.application.credentials.dig(:instagram, :app_id)
# Should return your App ID, not nil
```

If nil, add credentials as shown in Step 3.

### Issue 2: "Invalid OAuth Redirect URI"

**Cause**: Redirect URI not whitelisted in Facebook App

**Solution**:
1. Go to Facebook App → Instagram → Business login settings
2. Add exact callback URL:
   - Development: `http://localhost:3000/social_media/oauth/instagram/callback`
   - Production: `https://yourdomain.com/social_media/oauth/instagram/callback`
3. Make sure there's no trailing slash mismatch

### Issue 3: "Authorization Denied"

**Cause**: Not added as Instagram Tester in development mode

**Solution**:
1. Facebook App → Roles → Instagram Testers
2. Add your Instagram username
3. Accept invitation in Instagram app (Settings → Apps and Websites → Tester Invites)

### Issue 4: "Account not Business type"

**Cause**: Instagram account is still Personal

**Solution**:
1. Instagram app → Settings → Account
2. "Switch to Professional Account"
3. Choose "Business" or "Creator"

### Issue 5: "Failed to exchange token"

**Cause**: Incorrect App Secret or expired authorization code

**Solution**:
- Verify App Secret is correct (check for spaces/typos)
- Authorization code expires in 1 hour - try the flow again
- Check Rails logs: `tail -f log/development.log`

### Issue 6: "Token expired"

**Cause**: Long-lived token expired (60 days passed without refresh)

**Solution**:
- Reconnect the account (revoke and reconnect)
- Set up automatic token refresh job
- Monitor token expiration dates

---

## 📊 Step 7: Analytics and Insights

### Available Metrics:

With `instagram_business_basic` scope:
- Profile views
- Reach
- Impressions

With `instagram_business_manage_insights` scope (requires App Review):
- Detailed post insights
- Follower demographics
- Website clicks
- Story metrics

### Access Analytics:

```ruby
account = Spree::SocialMediaAccount.instagram_accounts.last
service = Spree::SocialMedia::InstagramApiService.new(account)

# Get insights for date range
insights = service.get_account_insights(7.days.ago..Date.current)
```

---

## 🔒 Security Best Practices

1. **Never commit credentials** to version control
   - Use Rails credentials or environment variables
   - Add `.env` to `.gitignore`

2. **Use HTTPS in production**
   - Instagram requires HTTPS for OAuth callbacks
   - Configure SSL certificate

3. **Validate webhook signatures** (if using webhooks)
   - Verify requests come from Instagram
   - Check HMAC signature

4. **Implement rate limiting**
   - Respect Instagram API rate limits
   - Monitor API usage

5. **Refresh tokens regularly**
   - Set up automated refresh job
   - Monitor expiration dates

---

## 🚀 Production Deployment

### Before Going Live:

1. **Switch App to Live Mode**:
   - Facebook App Dashboard → Settings → Basic
   - Toggle "App Mode" from "Development" to "Live"

2. **Submit for App Review** (if needed for advanced permissions):
   - Go to App Review → Permissions and Features
   - Request additional permissions (if needed):
     - `instagram_business_manage_insights` (for full analytics)
   - Provide:
     - Privacy Policy URL
     - Terms of Service URL
     - App icon (1024x1024px)
     - Screen recording of OAuth flow
     - Detailed use case explanation

3. **Update Redirect URIs**:
   - Add production callback URL
   - Remove development URLs (or keep for testing)

4. **Update Rails Credentials**:
   - Ensure production credentials are set
   - Verify APP_URL environment variable

5. **Set up Monitoring**:
   - Monitor token expiration
   - Track API errors
   - Set up alerts for failed authentications

---

## 📚 API Endpoints Reference

### Authorization:
```
GET https://www.instagram.com/oauth/authorize
  ?client_id={app-id}
  &redirect_uri={callback-url}
  &scope=instagram_business_basic,instagram_business_content_publish
  &response_type=code
```

### Token Exchange:
```
POST https://api.instagram.com/oauth/access_token
  client_id={app-id}
  client_secret={app-secret}
  code={authorization-code}
  grant_type=authorization_code
  redirect_uri={callback-url}
```

### Long-Lived Token:
```
GET https://graph.instagram.com/access_token
  ?grant_type=ig_exchange_token
  &client_secret={app-secret}
  &access_token={short-lived-token}
```

### Refresh Token:
```
GET https://graph.instagram.com/refresh_access_token
  ?grant_type=ig_refresh_token
  &access_token={long-lived-token}
```

### Account Info:
```
GET https://graph.instagram.com/me
  ?fields=id,username,account_type,media_count
  &access_token={token}
```

### Publish Content:
```
# Step 1: Create container
POST https://graph.instagram.com/me/media
  ?image_url={media-url}
  &caption={caption}
  &access_token={token}

# Step 2: Publish
POST https://graph.instagram.com/me/media_publish
  ?creation_id={container-id}
  &access_token={token}
```

---

## 🆘 Need Help?

- **Official Documentation**: https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/
- **Graph API Explorer**: https://developers.facebook.com/tools/explorer/
- **Developer Community**: https://developers.facebook.com/community/
- **App Review Documentation**: https://developers.facebook.com/docs/app-review

---

## ✨ What's Next?

After successful setup, you can:

1. **Publish Content**:
   - Feed posts (single image/video)
   - Carousel posts (multiple images)
   - Stories (24-hour content)
   - Reels (short videos)

2. **Manage Engagement**:
   - Reply to comments
   - Manage direct messages
   - Track mentions

3. **Analyze Performance**:
   - View insights and analytics
   - Track engagement rates
   - Monitor follower growth

4. **Automate Posting**:
   - Schedule posts in advance
   - Use templates for consistent branding
   - Bulk schedule campaigns

5. **Scale Up**:
   - Connect multiple Instagram accounts (per vendor)
   - Set up webhook notifications
   - Implement advanced analytics

---

## 📝 Summary Checklist

- [ ] Instagram account converted to Business/Creator
- [ ] Facebook Developer account created
- [ ] Facebook App created with Instagram product
- [ ] Instagram App ID and Secret saved
- [ ] OAuth redirect URI configured
- [ ] Rails credentials/environment variables set
- [ ] Instagram Tester role assigned (development)
- [ ] Server restarted
- [ ] Instagram account connected successfully
- [ ] Test post published successfully
- [ ] Token refresh job configured (optional but recommended)

**Congratulations! Your Instagram integration is ready! 🎉**
