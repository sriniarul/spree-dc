# frozen_string_literal: true

module Spree
  module V2
    module Storefront
      class VendorSerializer
        include JSONAPI::Serializer
        
        set_type :vendor
        set_id :slug
        
        # Basic attributes for storefront
        attributes :name, :about_us, :contact_us, :slug, :priority, :state
        
        # Computed attributes
        attribute :display_name do |vendor|
          vendor.display_name
        end
        
        attribute :logo_url do |vendor, params|
          return nil unless vendor.image&.attachment&.attached?
          
          # Use Rails URL helpers to generate absolute URLs
          Rails.application.routes.url_helpers.url_for(vendor.image.attachment)
        end
        
        attribute :products_count do |vendor|
          vendor.products.available.count
        end
        
        attribute :categories do |vendor|
          vendor.categories.pluck(:name)
        end
        
        attribute :tags do |vendor|
          vendor.tags.pluck(:name)
        end
        
        # Business information (limited for storefront)
        attribute :business_name do |vendor|
          vendor.vendor_profile&.business_name
        end
        
        attribute :business_type do |vendor|
          vendor.vendor_profile&.business_type
        end
        
        attribute :contact_info do |vendor|
          {
            email: vendor.contact_email,
            phone: vendor.phone
          }.compact
        end
        
        # SEO and metadata
        attribute :meta_description do |vendor|
          vendor.meta_description.presence || vendor.about_us&.truncate(160)
        end
        
        attribute :meta_title do |vendor|
          vendor.meta_title.presence || vendor.name
        end
        
        # Relationships
        has_one :vendor_profile, serializer: VendorProfileSerializer, if: proc { |record|
          record.vendor_profile.present?
        }
        
        has_one :image, serializer: ImageSerializer, if: proc { |record|
          record.image&.attachment&.attached?
        }
        
        has_many :products, serializer: ProductSerializer, if: proc { |record, params|
          params && params[:include_products]
        } do |vendor|
          vendor.products.available.limit(10)
        end
        
        # Conditional attributes based on user permissions
        attribute :verification_status, if: proc { |record, params|
          params && params[:current_user]&.has_spree_role?(:admin)
        } do |vendor|
          vendor.vendor_profile&.verification_status
        end
        
        # Store-specific attributes
        attribute :available_in_store, if: proc { |record, params|
          params && params[:current_store]
        } do |vendor, params|
          if params[:current_store].vendors.exists?(vendor.id)
            true
          else
            vendor.vendor_profile&.vendors_shared_across_stores?
          end
        end
        
        # Links for JSONAPI compliance
        attribute :links do |vendor, params|
          base_url = params&.dig(:base_url) || ''
          
          {
            self: "#{base_url}/api/v2/storefront/vendors/#{vendor.slug}",
            products: "#{base_url}/api/v2/storefront/vendors/#{vendor.slug}/products"
          }
        end
        
        # Cache key for performance
        cache_options store: Rails.cache, namespace: 'spree_marketplace', expires_in: 1.hour
        
        # Custom cache key based on vendor and related models
        def cache_key(record, params)
          [
            record.cache_key_with_version,
            record.vendor_profile&.cache_key_with_version,
            record.image&.cache_key_with_version,
            record.products.available.maximum(:updated_at),
            params&.dig(:current_store)&.cache_key_with_version
          ].compact.join('/')
        end
      end
    end
  end
end