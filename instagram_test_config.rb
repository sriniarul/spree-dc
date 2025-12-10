# Quick Instagram OAuth Test Configuration
# This script tests if Facebook App credentials are configured for Instagram integration

puts "Instagram OAuth Configuration Test"
puts "=================================="

# Test if credentials are configured
facebook_app_id = ENV['FACEBOOK_APP_ID']
facebook_app_secret = ENV['FACEBOOK_APP_SECRET']

if facebook_app_id && facebook_app_secret
  puts "✅ Facebook App ID: #{facebook_app_id[0..8]}..."
  puts "✅ Facebook App Secret: [CONFIGURED]"
  puts ""
  puts "Ready to test Instagram connection!"
  puts "Go to: http://localhost:3000/admin/social_media/accounts"
  puts "Click 'Connect Instagram'"
else
  puts "❌ Facebook credentials not configured"
  puts ""
  puts "To configure:"
  puts "1. Run: bundle exec rails credentials:edit"
  puts "2. Add:"
  puts "   facebook:"
  puts "     app_id: 'YOUR_FACEBOOK_APP_ID'"
  puts "     app_secret: 'YOUR_FACEBOOK_APP_SECRET'"
  puts ""
  puts "OR set environment variables:"
  puts "export FACEBOOK_APP_ID='your_app_id'"
  puts "export FACEBOOK_APP_SECRET='your_app_secret'"
end

puts ""
puts "Instagram Requirements Checklist:"
puts "□ Facebook App created at developers.facebook.com"
puts "□ Instagram Graph API product added to app"
puts "□ OAuth redirect URI: http://localhost:3000/auth/facebook/callback"
puts "□ Instagram Business account (not personal)"
puts "□ Instagram connected to Facebook Page"
puts "□ Facebook App credentials configured in Rails"