# Google OAuth Button Usage Guide

## 🎨 Available Button Styles

### 1. **Full Google OAuth Button** (Recommended)
```erb
<%= google_oauth_login_button %>
```
**Features:**
- ✅ Full-width button with Google branding
- ✅ Official Google "G" logo with authentic colors
- ✅ Professional hover and focus states
- ✅ CSRF protection built-in
- ✅ Loading state with "Signing in..." text

**Custom options:**
```erb
<%= google_oauth_login_button(
  text: "Continue with Google",
  class: "custom-css-class"
) %>
```

### 2. **Compact Google Button**
```erb
<%= google_oauth_compact_button %>
```
**Features:**
- ✅ Smaller inline button for navigation bars
- ✅ Same Google branding in compact form
- ✅ Perfect for header/navigation areas

### 3. **Text Link Style**
```erb
<%= google_oauth_text_link %>
<%= google_oauth_text_link("Login with Google") %>
```
**Features:**
- ✅ Simple underlined text appearance
- ✅ Still maintains CSRF security
- ✅ Good for minimal designs

### 4. **Ready-to-Use Partial**
```erb
<%= render 'spree/shared/oauth_login_buttons' %>
```
**Features:**
- ✅ Includes divider with "Or continue with"
- ✅ Properly styled for login/signup forms
- ✅ Only renders if OAuth is enabled

## 🔧 Implementation Examples

### In Login Form:
```erb
<!-- app/views/devise/sessions/new.html.erb -->
<div class="max-w-md mx-auto">
  <h2 class="text-2xl font-bold mb-6">Sign In</h2>

  <!-- Regular login form -->
  <%= form_with(model: resource, as: resource_name, url: session_path(resource_name), local: true) do |f| %>
    <!-- Email and password fields -->
    <div class="mb-4">
      <%= f.email_field :email, class: "w-full px-3 py-2 border border-gray-300 rounded-md" %>
    </div>
    <div class="mb-6">
      <%= f.password_field :password, class: "w-full px-3 py-2 border border-gray-300 rounded-md" %>
    </div>
    <div class="mb-6">
      <%= f.submit "Sign In", class: "w-full bg-blue-600 text-white py-2 rounded-md" %>
    </div>
  <% end %>

  <!-- OAuth buttons -->
  <%= render 'spree/shared/oauth_login_buttons' %>
</div>
```

### In Registration Form:
```erb
<!-- app/views/devise/registrations/new.html.erb -->
<div class="max-w-md mx-auto">
  <h2 class="text-2xl font-bold mb-6">Create Account</h2>

  <!-- Google OAuth first -->
  <%= google_oauth_login_button(text: "Sign up with Google") %>

  <!-- Divider -->
  <div class="relative my-6">
    <div class="absolute inset-0 flex items-center">
      <div class="w-full border-t border-gray-300"></div>
    </div>
    <div class="relative flex justify-center text-sm">
      <span class="px-2 bg-white text-gray-500">Or</span>
    </div>
  </div>

  <!-- Regular signup form -->
  <%= form_with(model: resource, as: resource_name, url: registration_path(resource_name), local: true) do |f| %>
    <!-- Form fields -->
  <% end %>
</div>
```

### In Navigation/Header:
```erb
<!-- For logged out users -->
<% unless user_signed_in? %>
  <div class="flex space-x-2">
    <%= link_to "Login", spree.login_path, class: "text-gray-600" %>
    <%= google_oauth_compact_button %>
  </div>
<% end %>
```

## 🎯 Button Appearance

The buttons will look like this:

**Full Button:**
```
┌─────────────────────────────────────┐
│  [G]  Sign in with Google           │
└─────────────────────────────────────┘
```

**Compact Button:**
```
┌──────────────┐
│  [G] Google  │
└──────────────┘
```

**Text Link:**
```
Sign in with Google  (underlined, blue)
```

## 🔒 Security Features

- ✅ **CSRF Protection:** All buttons use `form_with` for proper token handling
- ✅ **Secure OAuth Flow:** Follows OAuth 2.0 security standards
- ✅ **No Manual Token Handling:** Rails handles CSRF automatically
- ✅ **Safe HTML:** SVG icons are properly sanitized

## 🎨 Styling

The buttons use Tailwind CSS classes that match Google's design guidelines:

- **Colors:** Authentic Google brand colors (#4285F4, #34A853, #FBBC05, #EA4335)
- **Typography:** Clean, readable fonts with proper weight
- **Spacing:** Consistent padding and margins
- **States:** Hover, focus, and active states included
- **Responsive:** Works on all screen sizes

## 🚀 Customization

### Custom Styling:
```erb
<%= google_oauth_login_button(
  class: "my-custom-class bg-red-500 hover:bg-red-600",
  text: "Custom Text Here"
) %>
```

### Custom Icons:
Override the `google_icon_svg` method in your helper:
```ruby
# In your application helper
def google_icon_svg
  # Your custom SVG here
end
```

## ✅ Testing

After implementation, test these scenarios:

1. **Click Button:** Should redirect to Google OAuth consent screen
2. **CSRF Protection:** No more "Authenticity error" messages
3. **Responsive:** Button works on mobile and desktop
4. **Loading State:** Button shows "Signing in..." when clicked
5. **Accessibility:** Button is keyboard navigable

## 🔧 Troubleshooting

**Button doesn't appear?**
- Check that `oauth_enabled?` returns `true`
- Verify Google credentials are set
- Ensure OAuth gems are installed

**Still getting CSRF errors?**
- Verify you're using the updated helper methods
- Check that `form_with` is being used, not `link_to`
- Ensure Rails CSRF protection is enabled

**Button styling issues?**
- Confirm Tailwind CSS is available
- Check for CSS conflicts
- Use custom classes if needed

The Google OAuth integration is now complete with beautiful, secure, and user-friendly buttons! 🎉