# Instagram Platform Integration Guide (2024/2025)

## 🎯 Important: Two Authentication Options

As of 2024, Facebook/Meta offers **TWO different ways** to integrate Instagram for business:

### Option 1: Instagram API with Instagram Login (NEW - Recommended)
**Released**: July 2024
- ✅ Direct Instagram authentication (no Facebook Page needed)
- ✅ Works with Instagram Business OR Creator accounts
- ✅ Simpler setup process
- ✅ Better user experience (Instagram-native login)
- ⚠️ Requires Instagram Platform product (not "Instagram Graph API")

### Option 2: Instagram API with Facebook Login (Legacy)
**Released**: Earlier (still supported)
- Requires Facebook Page linked to Instagram Business account
- More complex setup (Facebook Page + Instagram linkage)
- Works only with Instagram Business accounts (not Creator)
- Uses Facebook OAuth + Page Access Tokens

---

## 📱 What You See in Facebook Developer Console

When you go to **Add Products** in your Facebook App, you'll see:

### ✅ "Instagram" Product
**This is what you want!** Description:
> "Allow creators and businesses to manage messages and comments, publish content, track insights, hashtags and mentions."

This gives you access to:
- Instagram API with Instagram Login ✓
- Instagram API with Facebook Login ✓
- Instagram Messaging API ✓

### ❌ ~~"Instagram Graph API"~~ (Old Name)
This was the old name. It's now just called **"Instagram"**.

### ❌ ~~"Instagram Basic Display API"~~ (Deprecated)
**DO NOT USE** - Deprecated on December 4, 2024. This was for consumer apps, not business features.

---

## 🏆 Recommendation: Which Option to Use?

### Use **Instagram Login** (Option 1) if:
- ✅ You want a simpler setup
- ✅ You want Instagram-native authentication
- ✅ You support Creator accounts (not just Business)
- ✅ You don't want to require Facebook Page setup

### Use **Facebook Login** (Option 2) if:
- You already have Facebook Page integration
- You need Facebook + Instagram cross-posting
- You want unified Page + Instagram management
- Your vendors already manage Facebook Pages

**For your use case (multivendor social media management), I recommend Option 1 (Instagram Login) as it's simpler and more direct.**

---

## Option 1: Instagram API with Instagram Login Setup

### Step 1: Facebook App Setup

1. **Create Facebook App**
   - Visit: https://developers.facebook.com/apps/
   - Click **"Create App"** → **"Business"** type
   - Enter app name: "YourCompany Social Media Manager"
   - Save your **App ID** and **App Secret**

2. **Add Instagram Product**
   - In your app dashboard, go to **"Add Products"**
   - Find **"Instagram"** (NOT "Instagram Basic Display")
   - Click **"Set Up"**
   - This gives you access to Instagram Platform APIs

3. **Configure Redirect URIs**
   - Go to **Instagram → Basic Display** (or Instagram Settings)
   - Add **Valid OAuth Redirect URIs**:
     ```
     http://localhost:3000/auth/instagram/callback
     https://yourdomain.com/auth/instagram/callback
     ```

### Step 2: Required Permissions

Request these scopes in your OAuth flow:

**Core Scopes** (available immediately in Development):
- `instagram_business_basic` - Basic profile information
- `instagram_business_content_publish` - Publish content

**Additional Scopes** (may require App Review):
- `instagram_business_manage_messages` - Manage messages
- `instagram_business_manage_comments` - Manage comments
- `instagram_business_manage_insights` - Access analytics

### Step 3: OAuth Flow Implementation

**Authorization URL**:
```
https://www.instagram.com/oauth/authorize
  ?client_id={your-app-id}
  &redirect_uri={your-redirect-uri}
  &scope=instagram_business_basic,instagram_business_content_publish
  &response_type=code
  &state={your-state-token}
```

**Token Exchange**:
```bash
POST https://api.instagram.com/oauth/access_token

Parameters:
  client_id: YOUR_APP_ID
  client_secret: YOUR_APP_SECRET
  code: {authorization_code_from_callback}
  grant_type: authorization_code
  redirect_uri: YOUR_REDIRECT_URI
```

**Response**:
```json
{
  "access_token": "short_lived_token",
  "user_id": "instagram_user_id"
}
```

**Exchange for Long-Lived Token**:
```bash
GET https://graph.instagram.com/access_token
  ?grant_type=ig_exchange_token
  &client_secret={your-app-secret}
  &access_token={short-lived-token}
```

**Response**:
```json
{
  "access_token": "long_lived_token",
  "token_type": "bearer",
  "expires_in": 5184000  // 60 days
}
```

### Step 4: API Endpoints

**Get Account Info**:
```
GET https://graph.instagram.com/me
  ?fields=id,username,account_type,media_count
  &access_token={access-token}
```

**Publish Content**:
```
# Step 1: Create container
POST https://graph.instagram.com/{ig-user-id}/media
  ?image_url={media-url}
  &caption={caption}
  &access_token={access-token}

# Step 2: Publish
POST https://graph.instagram.com/{ig-user-id}/media_publish
  ?creation_id={container-id}
  &access_token={access-token}
```

---

## Option 2: Instagram API with Facebook Login Setup

### Step 1: Prerequisites

1. **Facebook Page** (must exist)
2. **Instagram Business Account** (not Creator)
3. **Link Instagram to Facebook Page**:
   - Instagram → Settings → Account → Linked Accounts → Facebook
   - Connect to your Facebook Page

### Step 2: Facebook App Setup

1. **Create Facebook App** (same as Option 1)
2. **Add Instagram Product** (same as Option 1)
3. **Configure Facebook Login**:
   - Add **Facebook Login** product
   - Settings → Valid OAuth Redirect URIs:
     ```
     http://localhost:3000/auth/facebook/callback
     https://yourdomain.com/auth/facebook/callback
     ```

### Step 3: Required Permissions

**Facebook Scopes**:
- `pages_show_list` - List Facebook Pages
- `pages_read_engagement` - Read Page engagement
- `pages_manage_posts` - Create posts on Pages
- `instagram_basic` - Basic Instagram access
- `instagram_content_publish` - Publish to Instagram
- `instagram_manage_comments` - Manage comments
- `instagram_manage_insights` - Access insights

### Step 4: OAuth Flow (Facebook)

**Authorization URL**:
```
https://www.facebook.com/v22.0/dialog/oauth
  ?client_id={app-id}
  &redirect_uri={redirect-uri}
  &scope=pages_show_list,pages_manage_posts,instagram_basic,instagram_content_publish
  &response_type=code
  &state={state-token}
```

**Token Exchange → Get Page Token → Get Instagram Account**:
```bash
# 1. Exchange code for User Access Token
POST https://graph.facebook.com/v22.0/oauth/access_token

# 2. Get User's Pages
GET https://graph.facebook.com/v22.0/me/accounts
  ?access_token={user-access-token}

# 3. Get Instagram Business Account from Page
GET https://graph.facebook.com/v22.0/{page-id}
  ?fields=instagram_business_account
  &access_token={page-access-token}

# 4. Use Page Access Token for Instagram API calls
```

---

## Comparison Table

| Feature | Instagram Login | Facebook Login |
|---------|----------------|----------------|
| **Setup Complexity** | Simple ⭐⭐⭐ | Complex ⭐ |
| **Facebook Page Required** | ❌ No | ✅ Yes |
| **Account Types** | Business + Creator | Business only |
| **Authentication** | Instagram native | Facebook OAuth |
| **Token Type** | Instagram token | Page Access Token |
| **User Experience** | Better (1-click) | More steps |
| **Cross-posting** | Instagram only | Facebook + Instagram |
| **Released** | July 2024 (new) | Legacy (older) |

---

## Current Implementation Status

### What We Have Implemented (Option 2 - Facebook Login)

✅ Facebook OAuth with OmniAuth
✅ Page Access Token retrieval
✅ Instagram Business Account detection
✅ Content publishing to Instagram
✅ Analytics and insights

### What Needs to be Added (Option 1 - Instagram Login)

We can add Instagram Login as an alternative authentication method. This would give vendors two choices:

1. **"Connect with Instagram"** → Direct Instagram auth (simpler)
2. **"Connect with Facebook"** → Facebook Page + Instagram (current)

---

## Recommendation for Your Platform

### Implement Both Options:

```
┌─────────────────────────────────────┐
│  Connect Social Media Account       │
├─────────────────────────────────────┤
│                                     │
│  [Instagram] Direct Login           │
│  ✓ Simpler setup                    │
│  ✓ Business or Creator accounts     │
│                                     │
│  [Facebook] Page + Instagram        │
│  ✓ Cross-post to Facebook           │
│  ✓ Unified Page management          │
│                                     │
└─────────────────────────────────────┘
```

### Implementation Priority:

1. **Keep Facebook Login** (already works) ✅
2. **Add Instagram Login** (simpler alternative) ⬅️ Recommended next
3. Let vendors choose their preferred method

---

## Next Steps

### If you want to add Instagram Login (Option 1):

1. **Update OmniAuth configuration** to add Instagram provider
2. **Create Instagram OAuth controller** (separate from Facebook)
3. **Implement token exchange** (short → long-lived)
4. **Update account model** to support both auth types
5. **Add UI option** for vendors to choose

### If you want to stay with Facebook Login (Option 2):

1. **Verify your Facebook App** has "Instagram" product added ✓
2. **Configure credentials** (same App ID & Secret) ✓
3. **Test the flow** with your Instagram Business account
4. **No code changes needed** - current implementation is correct!

---

## What Product to Add in Facebook App

### ✅ Correct: Add "Instagram" Product

When you go to your Facebook App → Add Products, look for:

**Instagram**
> Allow creators and businesses to manage messages and comments, publish content, track insights, hashtags and mentions.

This single product gives you access to:
- Instagram API with Instagram Login
- Instagram API with Facebook Login
- Instagram Messaging API

### ❌ Don't look for:

- ~~"Instagram Graph API"~~ (old name, doesn't exist anymore)
- ~~"Instagram Basic Display"~~ (deprecated, for consumer apps)

---

## Testing Your Setup

### Option 1 (Instagram Login):
```ruby
# After implementing Instagram Login
account = Spree::SocialMediaAccount.instagram_accounts.last
account.token_metadata['auth_type'] # => 'instagram_login'
service = Spree::SocialMedia::InstagramApiService.new(account)
service.test_connection # => true
```

### Option 2 (Facebook Login):
```ruby
# Current implementation
account = Spree::SocialMediaAccount.instagram_accounts.last
account.token_metadata['auth_type'] # => 'facebook_login'
account.token_metadata['facebook_page_id'] # => "123456789"
service = Spree::SocialMedia::InstagramApiService.new(account)
service.test_connection # => true
```

---

## FAQs

**Q: I don't see "Instagram Graph API" in my app. Where is it?**
A: It's now just called "Instagram" product. Add that.

**Q: Do I need separate Instagram App credentials?**
A: No! Use your Facebook App ID and App Secret for both options.

**Q: Which option is easier?**
A: Instagram Login (Option 1) is simpler - no Facebook Page needed.

**Q: Can I support both?**
A: Yes! You can offer both authentication methods to your vendors.

**Q: Will my current implementation still work?**
A: Yes! Facebook Login (Option 2) is still fully supported and working.

---

## Resources

- **Instagram Platform Docs**: https://developers.facebook.com/docs/instagram-platform
- **Instagram Login Guide**: https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login
- **Facebook Login Guide**: https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login
- **API Reference**: https://developers.facebook.com/docs/instagram-api
- **App Review Process**: https://developers.facebook.com/docs/app-review
