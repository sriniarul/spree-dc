class CreateSpreePushNotificationCampaigns < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_push_notification_campaigns do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.string :url
      t.string :icon
      t.string :badge
      t.datetime :sent_at, null: false
      t.integer :total_sent, default: 0
      t.integer :total_delivered, default: 0
      t.integer :total_failed, default: 0
      t.integer :total_clicked, default: 0
      t.text :metadata

      t.timestamps
    end

    add_index :spree_push_notification_campaigns, :sent_at
    add_index :spree_push_notification_campaigns, [:sent_at, :total_sent], name: 'index_campaigns_on_sent_at_and_total_sent'
  end
end