class CreateSpreeVendorsIfNotExists < ActiveRecord::Migration[7.0]
  def up
    # Only create the table if it doesn't exist
    unless table_exists?(:spree_vendors)
      create_table :spree_vendors do |t|
        t.string :name, null: false
        t.string :state, default: 'pending'
        t.references :user, foreign_key: { to_table: Spree.user_class.table_name }, null: true
        t.datetime :deleted_at
        t.json :public_metadata
        t.json :private_metadata

        t.timestamps null: false
      end
    end

    # Add columns that might be missing first
    add_column :spree_vendors, :name, :string, null: false unless column_exists?(:spree_vendors, :name)
    add_column :spree_vendors, :state, :string, default: 'pending' unless column_exists?(:spree_vendors, :state)
    add_column :spree_vendors, :user_id, :bigint unless column_exists?(:spree_vendors, :user_id)
    add_column :spree_vendors, :deleted_at, :datetime unless column_exists?(:spree_vendors, :deleted_at)
    add_column :spree_vendors, :public_metadata, :json unless column_exists?(:spree_vendors, :public_metadata)
    add_column :spree_vendors, :private_metadata, :json unless column_exists?(:spree_vendors, :private_metadata)

    # Add indexes only if they don't exist and columns exist
    add_index :spree_vendors, :name unless index_exists?(:spree_vendors, :name)
    add_index :spree_vendors, :state unless index_exists?(:spree_vendors, :state)
    add_index :spree_vendors, :deleted_at if column_exists?(:spree_vendors, :deleted_at) && !index_exists?(:spree_vendors, :deleted_at)
    add_index :spree_vendors, :user_id unless index_exists?(:spree_vendors, :user_id)
  end

  def down
    # Only drop if we created it
    drop_table :spree_vendors if table_exists?(:spree_vendors)
  end
end