class CreateSpreePushNotificationDeliveries < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_push_notification_deliveries do |t|
      t.references :push_notification_campaign, null: false, index: { name: 'index_deliveries_on_campaign_id' }
      t.references :push_subscription, null: false, index: { name: 'index_deliveries_on_subscription_id' }
      t.string :status, null: false, default: 'pending'
      t.datetime :delivered_at, null: false
      t.datetime :clicked_at
      t.datetime :dismissed_at
      t.text :error_message
      t.text :metadata

      t.timestamps
    end

    add_index :spree_push_notification_deliveries, [:status, :delivered_at]
    add_index :spree_push_notification_deliveries, [:push_notification_campaign_id, :status], name: 'index_deliveries_on_campaign_and_status'
  end
end