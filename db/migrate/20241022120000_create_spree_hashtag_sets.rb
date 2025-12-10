class CreateSpreeHashtagSets < ActiveRecord::Migration[7.2]
  def change
    create_table :spree_hashtag_sets do |t|
      t.string :name, null: false
      t.text :hashtags, null: false
      t.text :description
      t.references :vendor, null: false, foreign_key: { to_table: :spree_vendors }
      t.references :social_media_account, null: true, foreign_key: { to_table: :spree_social_media_accounts }
      t.integer :usage_count, default: 0
      t.integer :hashtag_count_cache, default: 0
      t.datetime :last_used_at
      t.text :metadata
      t.timestamps
    end

    add_index :spree_hashtag_sets, [:vendor_id, :name], unique: true
    add_index :spree_hashtag_sets, [:vendor_id, :social_media_account_id]
    add_index :spree_hashtag_sets, :usage_count
    add_index :spree_hashtag_sets, :last_used_at
    add_index :spree_hashtag_sets, :hashtag_count_cache
  end
end