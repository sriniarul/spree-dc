module Spree
  module Admin
    module DashboardControllerDecorator
      extend ActiveSupport::Concern

      included do
        before_action :redirect_vendors_from_admin_dashboard, only: [:show]
        skip_before_action :authorize_admin, if: :vendor_user?
      end

      private

      def redirect_vendors_from_admin_dashboard
        if vendor_user?
          # Redirect vendors to their orders page instead of admin dashboard
          redirect_to spree.admin_orders_path and return
        end
      end

      def vendor_user?
        try_spree_current_user&.vendor&.approved?
      end
    end
  end
end

Spree::Admin::DashboardController.include(Spree::Admin::DashboardControllerDecorator)