module Spree
  module Admin
    module Vendor
      class ProductsController < Spree::Admin::ProductsController
        before_action :authorize_vendor_access

        protected

        def collection
          return Spree::Product.none unless current_vendor

          base_scope = current_vendor.products
                                    .includes(:master, :variants, :option_types, :product_properties, :taxons, vendor: :user)
                                    .order(updated_at: :desc)

          params[:q] ||= {}
          @search = base_scope.ransack(params[:q])
          @collection = @search.result(distinct: true)
                               .page(params[:page])
                               .per(params[:per_page] || 25)

          if base_scope.respond_to?(:accessible_by) &&
              !current_ability.has_block?(params[:action], Spree::Product)
            @collection = @collection.accessible_by(current_ability, action)
          end

          @collection
        end

        def find_resource
          current_vendor.products
                        .includes(:master, :variants, :option_types, :product_properties, :taxons, vendor: :user)
                        .find(params[:id])
        end

        def build_resource
          current_vendor.products.build
        end

        private

        def authorize_vendor_access
          redirect_to spree.admin_forbidden_path unless current_vendor&.approved?
        end

        def permitted_resource_params
          params.require(:product).permit(Spree::PermittedAttributes.product_attributes)
        end

        def location_after_save
          spree.edit_admin_vendor_product_path(@object)
        end

        def collection_url(options = {})
          spree.admin_vendor_products_path(options)
        end
      end
    end
  end
end