module SpreeMultivendor
  class Configuration < Spree::Preferences::Configuration
    preference :vendor_approval_required, :boolean, default: true
    preference :vendor_can_edit_products, :boolean, default: true
    preference :vendor_can_manage_orders, :boolean, default: true
    preference :vendor_registration_enabled, :boolean, default: true
    preference :admin_email_on_vendor_registration, :boolean, default: true
    preference :vendor_auto_approve_products, :boolean, default: false
    preference :send_vendor_emails, :boolean, default: true
  end
end