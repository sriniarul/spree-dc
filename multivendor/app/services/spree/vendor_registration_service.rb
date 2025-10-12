module Spree
  class VendorRegistrationService
    prepend ::Spree::ServiceModule::Base

    def call(user_params:, vendor_params:)
      ActiveRecord::Base.transaction do
        user = create_user(user_params)
        return failure(user.errors) unless user.valid?

        vendor = create_vendor(vendor_params, user)
        return failure(vendor.errors) unless vendor.valid?

        send_notifications(vendor) if SpreeMultivendor::Config.admin_email_on_vendor_registration

        success(vendor: vendor, user: user)
      end
    rescue => e
      Rails.error.report(e)
      failure(I18n.t('spree.vendor_registration_failed'))
    end

    private

    def create_user(user_params)
      user = Spree.user_class.new(user_params)

      # Generate a temporary password if none provided
      if user_params[:password].blank?
        temp_password = generate_temporary_password
        user.password = user.password_confirmation = temp_password
      end

      user.save
      user
    end

    def create_vendor(vendor_params, user)
      vendor = Spree::Vendor.new(vendor_params)
      vendor.user = user
      vendor.state = 'pending' # Always start in pending state
      vendor.save
      vendor
    end

    def send_notifications(vendor)
      # Send confirmation email to vendor
      VendorRegistrationMailer.confirmation_email(vendor).deliver_later

      # Send notification to admin
      VendorRegistrationMailer.admin_notification_email(vendor).deliver_later
    end

    def generate_temporary_password
      SecureRandom.alphanumeric(12)
    end
  end
end