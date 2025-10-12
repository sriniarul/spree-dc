module Spree
  class VendorRegistrationMailer < Spree::BaseMailer
    def confirmation_email(vendor)
      @vendor = vendor
      @user = vendor.user
      @store = current_store

      mail(
        to: @user.email,
        from: from_address(@store),
        subject: I18n.t('spree.vendor_registration_confirmation_subject', store: @store.name)
      )
    end

    def admin_notification_email(vendor)
      @vendor = vendor
      @user = vendor.user
      @store = current_store

      admin_emails = Spree::Config.admin_notification_emails.split(',').map(&:strip)
      return if admin_emails.empty?

      mail(
        to: admin_emails,
        from: from_address(@store),
        subject: I18n.t('spree.vendor_registration_admin_notification_subject',
                       vendor_name: @vendor.display_name, store: @store.name)
      )
    end

    def approval_notification(vendor)
      @vendor = vendor
      @user = vendor.user
      @store = current_store

      mail(
        to: @user.email,
        from: from_address(@store),
        subject: I18n.t('spree.vendor_approval_notification_subject', store: @store.name)
      )
    end

    def rejection_notification(vendor, reason = nil)
      @vendor = vendor
      @user = vendor.user
      @store = current_store
      @rejection_reason = reason

      mail(
        to: @user.email,
        from: from_address(@store),
        subject: I18n.t('spree.vendor_rejection_notification_subject', store: @store.name)
      )
    end

    private

    def current_store
      @current_store ||= Spree::Store.default
    end
  end
end