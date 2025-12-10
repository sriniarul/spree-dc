#!/usr/bin/env ruby
# Script to restore and fix Instagram account

# Find the deleted account (including soft-deleted)
account = Spree::SocialMediaAccount.with_deleted.find_by(platform: 'instagram')

if account
  puts "Found account: #{account.username} (ID: #{account.id})"
  puts "Current status: #{account.status}"
  puts "Deleted at: #{account.deleted_at}"

  # Restore the account
  account.deleted_at = nil

  # Clear the error and set status to active
  account.status = 'active'
  account.last_error = nil
  account.last_error_at = nil

  if account.save
    puts "\n✓ Account restored successfully!"
    puts "Status: #{account.status}"
    puts "Deleted: #{account.deleted_at.nil? ? 'No' : 'Yes'}"

    # Trigger sync job
    puts "\nTriggering sync job..."
    Spree::SocialMedia::SyncAccountDetailsJob.perform_later(account.id)
    puts "✓ Sync job queued"
  else
    puts "\n✗ Failed to restore account"
    puts "Errors: #{account.errors.full_messages.join(', ')}"
  end
else
  puts "No Instagram account found"
end
