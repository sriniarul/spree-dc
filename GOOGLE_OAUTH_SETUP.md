# Google OAuth Setup for Spree Commerce

This guide explains how to set up Google OAuth authentication for your Spree storefront.

## Features Added

✅ **Core OAuth Support**
- OAuth fields added to User model (provider, uid, first_name, last_name, image_url)
- `Spree::UserOauth` concern with OAuth logic
- Database migration for OAuth fields

✅ **Storefront Integration**
- OAuth callback controller
- Helper methods for Google login buttons
- Route configuration
- Error handling and user feedback

✅ **Dependencies**
- Added omniauth gems to spree_core.gemspec
- Devise configuration for OAuth

## Setup Instructions

### 1. Google Cloud Console Setup

1. **Create Google Cloud Project:**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Click "Select a project" → "New Project"
   - Name it "DimeCart OAuth" (or your app name)

2. **Enable APIs:**
   - Go to "APIs & Services" → "Library"
   - Search and enable "Google+ API"
   - Search and enable "Google Identity API"

3. **Create OAuth Credentials:**
   - Go to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "OAuth 2.0 Client IDs"
   - Choose "Web application"
   - Name: "DimeCart Storefront"

4. **Configure Redirect URIs:**
   ```
   Development: http://localhost:3000/users/auth/google_oauth2/callback
   Production: https://yourdomain.com/users/auth/google_oauth2/callback
   ```

5. **Save Credentials:**
   - Note down Client ID and Client Secret

### 2. Rails Credentials Setup

Add your Google OAuth credentials to Rails credentials:

```bash
# Edit credentials
EDITOR="code --wait" rails credentials:edit

# Add this structure:
google:
  client_id: your_google_client_id_here
  client_secret: your_google_client_secret_here
```

### 3. Database Migration

Run the migration to add OAuth fields:

```bash
rails db:migrate
```

This adds the following fields to `spree_users`:
- `provider` (string)
- `uid` (string)
- `first_name` (string)
- `last_name` (string)
- `image_url` (string)

### 4. Install Devise Controllers (Optional)

If you want to customize the authentication flow:

```bash
rails generate spree:storefront:devise
```

### 5. Add Google Login Button to Views

Use the helper methods in your login forms:

```erb
<!-- Full button with Google styling -->
<%= google_oauth_login_button %>

<!-- Custom styled button -->
<%= google_oauth_login_button(
  class: "btn btn-google",
  text: "Continue with Google"
) %>

<!-- Simple text link -->
<%= google_oauth_text_link("Login with Google") %>
```

### 6. Environment Variables (Alternative)

If you prefer environment variables over Rails credentials:

```bash
# .env
GOOGLE_OAUTH_CLIENT_ID=your_client_id
GOOGLE_OAUTH_CLIENT_SECRET=your_client_secret
```

Then update `config/initializers/devise_oauth.rb`:

```ruby
if Rails.application.credentials.google&.client_id || ENV['GOOGLE_OAUTH_CLIENT_ID']
  config.omniauth :google_oauth2,
                  Rails.application.credentials.google&.client_id || ENV['GOOGLE_OAUTH_CLIENT_ID'],
                  Rails.application.credentials.google&.client_secret || ENV['GOOGLE_OAUTH_CLIENT_SECRET']
end
```

## How It Works

### User Flow
1. User clicks "Sign in with Google"
2. Redirected to Google OAuth consent screen
3. After approval, Google redirects back to your app
4. `OmniauthCallbacksController` processes the response
5. User is either created or linked to existing account
6. User is signed in automatically

### Account Linking
- If email exists: Links OAuth to existing account
- If new email: Creates new account with OAuth data
- OAuth users are auto-confirmed (no email verification needed)

### Error Handling
- Failed OAuth attempts show user-friendly messages
- Detailed logging for debugging
- Graceful fallback to regular login

## Helper Methods

### In Controllers
```ruby
# Check if user signed in via OAuth
current_user.oauth_user?

# Get display name
current_user.oauth_display_name

# Check if user has password
current_user.has_password?
```

### In Views
```ruby
# Check if OAuth is configured
oauth_enabled?

# Google login button
google_oauth_login_button

# Text link version
google_oauth_text_link
```

## Troubleshooting

### Common Issues

1. **"Invalid redirect URI"**
   - Check redirect URIs in Google Cloud Console
   - Ensure exact match with your domain

2. **"OAuth not working"**
   - Verify credentials are set correctly
   - Check Rails logs for detailed errors
   - Ensure APIs are enabled in Google Cloud

3. **"Missing routes"**
   - Run `rails generate spree:storefront:devise` if using custom controllers
   - Check that devise routes are properly configured

### Debug Commands

```bash
# Check if OAuth is configured
rails console
> Spree.user_class.omniauth_providers
> Rails.application.credentials.google

# Check routes
rails routes | grep oauth

# Test OAuth flow
# Visit: /users/auth/google_oauth2
```

## Security Notes

- OAuth users are auto-confirmed (no email verification)
- Store secrets securely in Rails credentials or environment variables
- Use HTTPS in production
- Regularly rotate OAuth credentials
- Monitor OAuth usage in Google Cloud Console

## Customization

### Custom OAuth Controller

Override the callback controller:

```ruby
class CustomOmniauthController < Spree::Users::OmniauthCallbacksController
  def google_oauth2
    # Your custom logic
    super
  end
end
```

### Custom User Matching

Override the `from_omniauth` method:

```ruby
class Spree::User
  def self.from_omniauth(auth)
    # Your custom matching logic
  end
end
```

## Testing

The OAuth functionality has been implemented and is ready for testing. After completing the Google Cloud setup and adding credentials, you can test by:

1. Starting your Rails server
2. Navigating to the login page
3. Looking for the "Sign in with Google" button
4. Testing the OAuth flow

Remember to update your redirect URIs when deploying to production!