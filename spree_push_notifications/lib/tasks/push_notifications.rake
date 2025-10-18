namespace :spree_push_notifications do
  desc 'Test push notifications by sending a test message to all subscriptions'
  task test: :environment do
    puts 'Testing push notifications...'

    subscription_count = Spree::PushSubscription.count

    if subscription_count == 0
      puts 'No push subscriptions found. Cannot send test notification.'
      next
    end

    puts "Found #{subscription_count} push subscriptions."

    result = Spree::PushNotificationService.broadcast(
      'Spree Commerce Test',
      'This is a test push notification from your Spree store!',
      { url: '/' }
    )

    puts "Test notification sent!"
    puts "Success: #{result[:success]}"
    puts "Failures: #{result[:failure]}"

    if result[:errors].any?
      puts "Errors:"
      result[:errors].each do |error|
        puts "  Subscription #{error[:subscription_id]}: #{error[:error]}"
      end
    end
  end

  desc 'Clean up old push subscriptions (older than 6 months)'
  task cleanup: :environment do
    puts 'Cleaning up old push subscriptions...'

    old_subscriptions = Spree::PushSubscription.where('last_used_at < ?', 6.months.ago)
    count = old_subscriptions.count

    if count == 0
      puts 'No old subscriptions found to clean up.'
    else
      old_subscriptions.delete_all
      puts "Cleaned up #{count} old push subscriptions."
    end
  end

  desc 'Show push notification statistics'
  task stats: :environment do
    puts 'Push Notification Statistics:'
    puts "Total subscriptions: #{Spree::PushSubscription.count}"
    puts "Active subscriptions (used within 6 months): #{Spree::PushSubscription.active.count}"
    puts "Inactive subscriptions (not used in 6 months): #{Spree::PushSubscription.inactive.count}"

    if Spree.user_class.respond_to?(:joins)
      user_count = Spree::PushSubscription.joins(:user).distinct.count(:user_id)
      puts "Users with subscriptions: #{user_count}"
    end

    puts "Most recent subscription: #{Spree::PushSubscription.maximum(:created_at) || 'None'}"
    puts "Most recent usage: #{Spree::PushSubscription.maximum(:last_used_at) || 'None'}"
  end

  desc 'Generate VAPID keys for push notifications'
  task generate_vapid_keys: :environment do
    require 'webpush'

    puts 'Generating VAPID keys for push notifications...'

    vapid_key = Webpush.generate_key

    puts ''
    puts 'Add these environment variables to your application:'
    puts ''
    puts "VAPID_PUBLIC_KEY=#{vapid_key.public_key}"
    puts "VAPID_PRIVATE_KEY=#{vapid_key.private_key}"
    puts "VAPID_SUBJECT=mailto:webmaster@yourdomain.com"
    puts ''
    puts 'Make sure to replace yourdomain.com with your actual domain.'
    puts ''
    puts 'For development, add these to your .env file.'
    puts 'For production, add them to your deployment environment.'
  end
end