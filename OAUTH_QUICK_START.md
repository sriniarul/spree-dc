# OAuth Quick Start Guide

## TL;DR - What You Need to Know

### The Key Facts:

1. **You have ONE Facebook App** with ONE App ID and ONE App Secret
2. **Instagram is a PRODUCT** within that Facebook App (not a separate app)
3. **Use the Facebook App credentials** for both Facebook and Instagram integration
4. **Instagram Business accounts MUST be linked to a Facebook Page**
5. **We use Page Access Tokens** (not User Access Tokens) for API calls

---

## 5-Minute Setup

### 1. Facebook App (2 minutes)

```
1. Visit: https://developers.facebook.com/apps/
2. Create App → Business Type
3. Save your App ID and App Secret
4. Add Products:
   - Facebook Login ✓
   - Instagram ✓ (NOT "Instagram Basic Display" - that's deprecated!)
5. Facebook Login Settings:
   - Add OAuth Redirect: http://localhost:3000/auth/facebook/callback
```

**Important**: Look for the product called **"Instagram"** with description:
> "Allow creators and businesses to manage messages and comments, publish content, track insights, hashtags and mentions."

### 2. Instagram Business Account (2 minutes)

```
1. Instagram App → Settings → Account
2. Switch to Professional → Business
3. Settings → Linked Accounts → Facebook
4. Link to your Facebook Page
```

### 3. Rails Configuration (1 minute)

**Option A - Rails Credentials:**
```bash
EDITOR="nano" bundle exec rails credentials:edit
```

Add:
```yaml
facebook:
  app_id: "YOUR_FACEBOOK_APP_ID"
  app_secret: "YOUR_FACEBOOK_APP_SECRET"
```

**Option B - Environment Variables:**
```bash
export FACEBOOK_APP_ID="your_app_id"
export FACEBOOK_APP_SECRET="your_app_secret"
```

Restart server:
```bash
bundle exec rails server
```

### 4. Connect Account

1. Go to `http://localhost:3000/admin`
2. Navigate to **Social Media** section
3. Click **Connect Account → Instagram**
4. Login with Facebook (must be Page admin)
5. Done! ✓

---

## Understanding the OAuth Flow

### What Happens When You Connect:

```
1. User clicks "Connect Instagram"
   ↓
2. Redirect to Facebook OAuth
   ↓
3. User logs in and grants permissions
   ↓
4. Facebook returns User Access Token
   ↓
5. System fetches user's Facebook Pages
   ↓
6. For selected Page, get Page Access Token
   ↓
7. Query Page for connected Instagram Business account
   ↓
8. Store Page Access Token (this is what we use for Instagram API)
   ↓
9. Both Facebook Page and Instagram account now connected!
```

### The Token Flow:

```
User Access Token (temporary, from OAuth)
  ↓
Page Access Token (long-lived, from Facebook Page)
  ↓
Instagram API calls (using Page Access Token)
```

---

## Credentials Cheat Sheet

### What You Have:

| Item | What It Is | Where to Find It | What It's Used For |
|------|-----------|------------------|-------------------|
| **Facebook App ID** | Public identifier | Facebook App → Settings → Basic | OAuth configuration, public |
| **Facebook App Secret** | Private key | Facebook App → Settings → Basic (click "Show") | OAuth token exchange, keep secret |
| **Page Access Token** | API token | Auto-generated during OAuth | Making Instagram/Facebook API calls |
| **Instagram Business Account ID** | Platform user ID | Auto-detected via API | Identifying Instagram account |

### What You DON'T Have:

- ❌ Separate Instagram App ID
- ❌ Separate Instagram App Secret
- ❌ Instagram-specific OAuth credentials

---

## Common Mistakes

### ❌ Mistake 1: Looking for Instagram App Credentials
**Wrong**: "Where do I find my Instagram App ID?"
**Right**: Use your Facebook App ID. Instagram is a product, not a separate app.

### ❌ Mistake 2: Using User Access Token for API Calls
**Wrong**: Store and use the OAuth User Access Token
**Right**: Exchange it for Page Access Token and use that

### ❌ Mistake 3: Personal Instagram Account
**Wrong**: Try to connect personal Instagram
**Right**: Must be Instagram Business account linked to Facebook Page

### ❌ Mistake 4: Separate Credentials for Each Platform
**Wrong**: Different credentials for Facebook vs Instagram
**Right**: Same Facebook App credentials for both

---

## Testing Your Setup

### 1. Check Credentials are Loaded:

```bash
bundle exec rails console
```

```ruby
# Should return your App ID
Rails.application.credentials.dig(:facebook, :app_id)
# OR
ENV['FACEBOOK_APP_ID']

# Should return your App Secret (be careful with this in production!)
Rails.application.credentials.dig(:facebook, :app_secret)
# OR
ENV['FACEBOOK_APP_SECRET']
```

### 2. Test OAuth Initiation:

Visit: `http://localhost:3000/auth/facebook`

- Should redirect to Facebook
- Should show permissions screen
- Should callback to your app

### 3. Test Instagram Connection:

After connecting account:

```ruby
bundle exec rails console

# Get the Instagram account
account = Spree::SocialMediaAccount.instagram_accounts.last

# Check it has required data
account.access_token.present?          # Should be true
account.platform_user_id.present?      # Should be true
account.username.present?              # Should be true

# Test API connection
service = Spree::SocialMedia::InstagramApiService.new(account)
service.test_connection                # Should return true
```

---

## File Structure

### Files We Created/Updated:

```
social_media/
├── config/
│   └── initializers/
│       └── omniauth.rb                          # NEW - OAuth configuration
├── app/
│   ├── controllers/
│   │   └── spree/social_media/
│   │       ├── oauth_initiation_controller.rb   # UPDATED - Simplified
│   │       └── oauth_callbacks_controller.rb    # UPDATED - Proper tokens
│   └── services/
│       └── spree/social_media/
│           ├── facebook_api_service.rb          # EXISTS - Gets Instagram
│           └── instagram_api_service.rb         # EXISTS - Uses Page Token

INSTAGRAM_SETUP.md                                # UPDATED - Full guide
OAUTH_QUICK_START.md                             # NEW - This file
```

---

## Development vs Production

### Development (Now):
- ✓ Only you and testers can use it
- ✓ 25 API calls/hour (enough for testing)
- ✓ No app review needed
- ✓ Can test immediately

### Production (Later):
- Requires Facebook App Review
- Need privacy policy, terms of service
- Need to explain use case with video
- Higher rate limits after approval
- 3-7 days approval time

**Start with development, move to production when ready!**

---

## Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| "OAuth not configured" error | Check credentials are set in Rails credentials or ENV |
| "No Facebook pages found" | Create a Facebook Page first |
| "No Instagram account found" | 1. Convert to Business 2. Link to Page |
| "Invalid redirect URI" | Add exact URL to Facebook App settings |
| "Can't connect account" | Check Rails logs: `tail -f log/development.log` |

---

## Next Steps

1. ✅ Follow 5-Minute Setup above
2. ✅ Connect your first account
3. ✅ Test posting content
4. 📖 Read full [INSTAGRAM_SETUP.md](./INSTAGRAM_SETUP.md) for details
5. 🚀 Build amazing features!

---

## Need Help?

- **Detailed Setup**: See [INSTAGRAM_SETUP.md](./INSTAGRAM_SETUP.md)
- **Facebook Docs**: https://developers.facebook.com/docs/instagram-api
- **Graph API Explorer**: https://developers.facebook.com/tools/explorer/
- **Project Knowledge**: See [PROJECT_KNOWLEDGE.md](./PROJECT_KNOWLEDGE.md)
