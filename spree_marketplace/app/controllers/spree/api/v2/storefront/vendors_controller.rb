# frozen_string_literal: true

module Spree
  module Api
    module V2
      module Storefront
        class VendorsController < ::Spree::Api::V2::Storefront::BaseController
          include Spree::Api::V2::Storefront::ProductListIncludes
          
          before_action :load_vendor, only: [:show, :products]
          
          # GET /api/v2/storefront/vendors
          def index
            render_serialized_payload { serialize_collection(collection) }
          end
          
          # GET /api/v2/storefront/vendors/:id
          def show
            render_serialized_payload { serialize_resource(resource) }
          end
          
          # GET /api/v2/storefront/vendors/:id/products
          def products
            @products = resource.products.available
                               .includes(master: :default_price, 
                                        variants: :default_price,
                                        product_properties: :property)
                               .ransack(params[:q]).result
                               .page(params[:page])
                               .per(params[:per_page] || Spree::Config[:products_per_page])
            
            render_serialized_payload { serialize_products(@products) }
          end
          
          private
          
          def resource
            @resource ||= scope.friendly.find(params[:id])
          end
          
          def collection
            @collection ||= scope.active
                                 .includes(:vendor_profile, :image)
                                 .ransack(collection_params).result
                                 .order(:priority, :name)
                                 .page(params[:page])
                                 .per(params[:per_page] || 20)
          end
          
          def scope
            Spree::Vendor.accessible_by(current_ability)
                         .for_store(current_store)
          end
          
          def collection_params
            params.permit(:q).fetch(:q, {}).permit(
              :name_cont, :business_name_cont, :about_us_cont,
              :state_eq, :category_list_cont, :tag_list_cont,
              :created_at_gteq, :created_at_lteq
            )
          end
          
          def serialize_collection(collection)
            Spree::V2::Storefront::VendorSerializer.new(
              collection,
              include: resource_includes,
              sparse_fields: sparse_fields,
              params: { 
                current_currency: current_currency,
                current_store: current_store
              }
            ).serializable_hash
          end
          
          def serialize_resource(resource)
            Spree::V2::Storefront::VendorSerializer.new(
              resource,
              include: resource_includes,
              sparse_fields: sparse_fields,
              params: {
                current_currency: current_currency,
                current_store: current_store
              }
            ).serializable_hash
          end
          
          def serialize_products(products)
            Spree::V2::Storefront::ProductSerializer.new(
              products,
              include: product_list_includes,
              sparse_fields: sparse_fields,
              params: {
                current_currency: current_currency,
                current_store: current_store,
                current_pricing_options: current_pricing_options,
                current_user: spree_current_user
              }
            ).serializable_hash
          end
          
          def resource_includes
            [
              :vendor_profile,
              :image,
              :products,
              categories: [],
              tags: []
            ]
          end
          
          def load_vendor
            @vendor = resource
          rescue ActiveRecord::RecordNotFound
            render_error_payload(
              { error: Spree.t('api.vendor_not_found') },
              404
            )
          end
        end
      end
    end
  end
end