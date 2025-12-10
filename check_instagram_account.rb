#!/usr/bin/env ruby
# Script to check Instagram account status

puts "Checking Instagram accounts..."

accounts = Spree::SocialMediaAccount.where(platform: 'instagram')

if accounts.any?
  accounts.each do |account|
    puts "\n" + "="*60
    puts "Account ID: #{account.id}"
    puts "Username: #{account.username}"
    puts "Platform User ID: #{account.platform_user_id}"
    puts "Status: #{account.status}"
    puts "Vendor ID: #{account.vendor_id}"
    puts "Posts Count: #{account.posts_count}"
    puts "Expires At: #{account.expires_at}"
    puts "Created At: #{account.created_at}"
    puts "Deleted At: #{account.deleted_at || 'Not deleted'}"
    puts "Last Error: #{account.last_error || 'None'}"
    puts "="*60
  end

  puts "\n✓ Found #{accounts.count} Instagram account(s)"
else
  puts "\n✗ No Instagram accounts found"

  # Check for soft-deleted accounts
  deleted_accounts = Spree::SocialMediaAccount.with_deleted.where(platform: 'instagram', deleted_at: nil)
  if deleted_accounts.any?
    puts "⚠️  Found #{deleted_accounts.count} soft-deleted Instagram account(s)"
  end
end
