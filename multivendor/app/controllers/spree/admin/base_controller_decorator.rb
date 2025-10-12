module Spree
  module Admin
    module BaseControllerDecorator
      extend ActiveSupport::Concern

      def current_vendor
        return nil unless try_spree_current_user

        @current_vendor ||= Spree::Vendor.find_by(user_id: try_spree_current_user.id)
      end

      included do
        # Make current_vendor available to views
        helper_method :current_vendor
      end
    end

    BaseController.prepend(BaseControllerDecorator)
  end
end