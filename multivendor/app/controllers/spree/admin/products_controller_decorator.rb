module Spree
  module Admin
    module ProductsControllerDecorator
      protected

      def find_resource
        return super unless current_vendor&.approved?

        Rails.logger.info "MULTIVENDOR DEBUG: ProductsController#find_resource called for vendor #{current_vendor.id}"

        # Ensure vendors can only access their own products with eager loading
        base_scope = current_vendor.products
                                  .includes(:master, :variants, :option_types,
                                           :product_properties, :taxons, vendor: :user)

        # In Spree, params[:id] can be either numeric ID or slug
        if params[:id].match?(/\A\d+\z/)
          # Numeric ID
          base_scope.find(params[:id])
        else
          # Slug
          base_scope.find_by!(slug: params[:id])
        end
      end

      def build_resource
        return super unless current_vendor&.approved?

        Rails.logger.info "MULTIVENDOR DEBUG: ProductsController#build_resource called for vendor #{current_vendor.id}"

        # When vendors create new products, assign them to their vendor
        product = current_vendor.products.build
        product
      end
    end

    ProductsController.prepend(ProductsControllerDecorator)
  end
end