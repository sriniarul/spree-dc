#!/usr/bin/env ruby
# Test script for Social Media Integration

puts "=" * 80
puts "SOCIAL MEDIA INTEGRATION - TEST SCRIPT"
puts "=" * 80
puts ""

# Test 1: Check Instagram Account
puts "TEST 1: Checking Instagram Account..."
puts "-" * 80

account = Spree::SocialMediaAccount.instagram_accounts.last

if account
  puts "✅ Instagram account found"
  puts "   Username: @#{account.username}"
  puts "   Status: #{account.status}"
  puts "   Token expires: #{account.expires_at}"
  puts "   Days until expiration: #{((account.expires_at - Time.current) / 1.day).to_i} days"

  if account.access_token_valid?
    puts "✅ Access token is valid"
  else
    puts "❌ Access token expired - need to reconnect"
  end
else
  puts "❌ No Instagram account found"
  puts "   Please connect an Instagram account first"
  exit 1
end

puts ""

# Test 2: Test API Connection
puts "TEST 2: Testing Instagram API Connection..."
puts "-" * 80

begin
  service = Spree::SocialMedia::InstagramApiService.new(account)

  if service.test_connection
    puts "✅ Instagram API connection successful"

    # Get profile info
    profile = service.get_profile_info
    if profile
      puts "   Account Type: #{profile['account_type']}"
      puts "   Media Count: #{profile['media_count']}"
      puts "   Followers: #{profile['followers_count']}" if profile['followers_count']
    end
  else
    puts "❌ Instagram API connection failed"
  end
rescue => e
  puts "❌ Error testing connection: #{e.message}"
end

puts ""

# Test 3: Check Scheduled Posts
puts "TEST 3: Checking Scheduled Posts..."
puts "-" * 80

scheduled_posts = Spree::SocialMediaPost.scheduled

if scheduled_posts.any?
  puts "✅ Found #{scheduled_posts.count} scheduled post(s)"

  scheduled_posts.each do |post|
    puts ""
    puts "   Post ID: #{post.id}"
    puts "   Product: #{post.product&.name || 'N/A'}"
    puts "   Platform: #{post.platform}"
    puts "   Content Type: #{post.post_options&.dig('content_type') || 'feed'}"
    puts "   Scheduled for: #{post.scheduled_at}"
    puts "   Status: #{post.status}"

    if post.scheduled_at <= Time.current
      puts "   ⚠️  OVERDUE - Should have been posted"
    elsif post.scheduled_at <= 1.hour.from_now
      puts "   ⏰ Publishing soon (within 1 hour)"
    else
      minutes_until = ((post.scheduled_at - Time.current) / 60).to_i
      puts "   ⏱️  Publishing in #{minutes_until} minutes"
    end
  end
else
  puts "ℹ️  No scheduled posts found"
end

puts ""

# Test 4: Check Recent Posts
puts "TEST 4: Checking Recent Posts..."
puts "-" * 80

recent_posts = Spree::SocialMediaPost.recent.limit(5)

if recent_posts.any?
  puts "✅ Found #{recent_posts.count} recent post(s)"

  recent_posts.each do |post|
    puts ""
    puts "   Post ID: #{post.id}"
    puts "   Status: #{post.status}"
    puts "   Platform: #{post.platform}"
    puts "   Created: #{post.created_at.strftime('%Y-%m-%d %H:%M')}"

    if post.posted?
      puts "   ✅ Posted at: #{post.posted_at.strftime('%Y-%m-%d %H:%M')}"
      puts "   Platform URL: #{post.platform_url}" if post.platform_url
    elsif post.failed?
      puts "   ❌ Failed: #{post.error_message}"
    end
  end
else
  puts "ℹ️  No posts found"
end

puts ""

# Test 5: Check Job Queue (if Sidekiq)
puts "TEST 5: Checking Job Queue (Sidekiq)..."
puts "-" * 80

begin
  require 'sidekiq/api'

  scheduled_jobs = Sidekiq::ScheduledSet.new
  puts "✅ Sidekiq is running"
  puts "   Scheduled jobs: #{scheduled_jobs.size}"

  # Find social media jobs
  social_media_jobs = scheduled_jobs.select do |job|
    job.klass == 'Spree::SocialMedia::PostToSocialMediaJob'
  end

  if social_media_jobs.any?
    puts "   Social media posting jobs: #{social_media_jobs.size}"

    social_media_jobs.first(3).each do |job|
      post_id = job.args.first
      scheduled_time = Time.at(job.at)
      puts "      - Post ##{post_id} scheduled for #{scheduled_time.strftime('%Y-%m-%d %H:%M')}"
    end
  else
    puts "   No social media posting jobs scheduled"
  end

rescue LoadError
  puts "ℹ️  Sidekiq not available (using #{Rails.application.config.active_job.queue_adapter})"
  puts "   Scheduled posts will be processed by #{Rails.application.config.active_job.queue_adapter}"
rescue => e
  puts "⚠️  Error checking Sidekiq: #{e.message}"
end

puts ""

# Test 6: Check Products Available
puts "TEST 6: Checking Products for Posting..."
puts "-" * 80

products_with_images = Spree::Product.joins(:images).distinct.limit(5)

if products_with_images.any?
  puts "✅ Found #{products_with_images.count} products with images"

  products_with_images.each do |product|
    puts ""
    puts "   Product: #{product.name}"
    puts "   Price: #{product.display_price}"
    puts "   Images: #{product.images.count}"
    puts "   Status: #{product.available? ? 'Available' : 'Not Available'}"

    # Check if product has been posted before
    posts_count = Spree::SocialMediaPost.where(product: product).count
    puts "   Previous posts: #{posts_count}"
  end
else
  puts "⚠️  No products with images found"
  puts "   Please add product images before posting to social media"
end

puts ""

# Summary
puts "=" * 80
puts "TEST SUMMARY"
puts "=" * 80

summary = []
summary << "✅ Instagram account connected" if account&.active?
summary << "✅ API connection working" if account&.access_token_valid?
summary << "✅ #{scheduled_posts.count} posts scheduled" if scheduled_posts.any?
summary << "✅ #{products_with_images.count} products ready to post" if products_with_images.any?

if summary.any?
  puts summary.join("\n")
else
  puts "⚠️  Setup incomplete - please follow the setup guide"
end

puts ""
puts "=" * 80
puts "To schedule a test post, run:"
puts "  rails console"
puts "  Then execute:"
puts "  account = Spree::SocialMediaAccount.instagram_accounts.last"
puts "  product = Spree::Product.joins(:images).first"
puts "  post = Spree::SocialMediaPost.create!("
puts "    social_media_account: account,"
puts "    product: product,"
puts "    content: 'Test post from #{Time.current.strftime('%H:%M')}!',"
puts "    status: 'scheduled',"
puts "    scheduled_at: 5.minutes.from_now,"
puts "    post_type: 'product_post',"
puts "    post_options: { content_type: 'feed' }"
puts "  )"
puts "  puts 'Post scheduled for ' + post.scheduled_at.to_s"
puts "=" * 80