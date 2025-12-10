class CreateSpreeSocialMediaTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :spree_social_media_templates do |t|
      t.string :name, null: false
      t.text :description
      t.string :template_type, null: false
      t.string :content_category, null: false
      t.text :caption_template
      t.text :hashtags_template
      t.text :instructions
      t.text :media_requirements_data
      t.references :vendor, null: false, foreign_key: { to_table: :spree_vendors }
      t.references :social_media_account, null: true, foreign_key: { to_table: :spree_social_media_accounts }
      t.boolean :active, default: true
      t.integer :usage_count, default: 0
      t.datetime :last_used_at
      t.text :template_variables_data
      t.text :preview_text
      t.text :metadata
      t.timestamps
    end

    add_index :spree_social_media_templates, [:vendor_id, :template_type]
    add_index :spree_social_media_templates, [:vendor_id, :content_category]
    add_index :spree_social_media_templates, [:vendor_id, :active]
    add_index :spree_social_media_templates, :usage_count
    add_index :spree_social_media_templates, :last_used_at
    add_index :spree_social_media_templates, [:template_type, :active]
  end
end