class CreateSpreePushSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :spree_push_subscriptions do |t|
      t.references :user, null: true, foreign_key: false, index: true
      t.text :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.datetime :last_used_at, null: true
      t.timestamps
    end

    add_index :spree_push_subscriptions, :endpoint, unique: true
    add_index :spree_push_subscriptions, :last_used_at
  end
end