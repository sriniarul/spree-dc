module Spree
  module Admin
    module VendorsHelper
      def vendor_status_class(status)
        case status.to_s
        when 'pending'
          'warning'
        when 'approved'
          'success'
        when 'rejected'
          'danger'
        when 'suspended'
          'secondary'
        else
          'light'
        end
      end
    end
  end
end