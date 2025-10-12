module Spree
  class VendorRegistrationsController < Spree::StoreController
    before_action :check_vendor_registration_enabled
    before_action :load_countries, only: [:new, :create]

    def new
      @vendor = Spree::Vendor.new
      @user = Spree.user_class.new
    end

    def create
      @vendor = Spree::Vendor.new(vendor_params)
      @user = Spree.user_class.new(user_params)

      # Check consent checkbox
      unless params[:vendor][:consent].to_i == 1
        flash[:error] = I18n.t('spree.vendor_consent_required')
        render :new and return
      end

      # Validate both models before transaction
      if @user.valid? && @vendor.valid?
        ActiveRecord::Base.transaction do
          @user.save!
          @vendor.user = @user
          @vendor.save!

          # Send confirmation emails
          send_confirmation_emails

          flash[:success] = I18n.t('spree.vendor_registration_success')
          redirect_to vendor_registration_success_path and return
        end
      else
        # Debug: Log validation errors
        Rails.logger.error "User errors: #{@user.errors.full_messages}" if @user.errors.any?
        Rails.logger.error "Vendor errors: #{@vendor.errors.full_messages}" if @vendor.errors.any?

        flash[:error] = I18n.t('spree.vendor_registration_failed')
        render :new and return
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      Rails.error.report(e)
      Rails.logger.error "Registration failed: #{e.message}"
      flash[:error] = I18n.t('spree.vendor_registration_failed')
      render :new
    end

    def success
      # Success page after registration
    end

    private

    def vendor_params
      params.require(:vendor).permit(
        :legal_name, :business_type, :trade_name, :registration_number,
        :incorporation_date, :country_code, :state_province, :city,
        :postal_code, :address_line1, :address_line2, :phone_number,
        :website_url, :name
      )
    end

    def user_params
      params.require(:user).permit(
        :email, :first_name, :last_name, :password, :password_confirmation
      )
    end

    def check_vendor_registration_enabled
      unless SpreeMultivendor::Config.vendor_registration_enabled
        flash[:error] = I18n.t('spree.vendor_registration_disabled')
        redirect_to spree.root_path
      end
    end

    def load_countries
      @countries = Spree::Country.all.order(:name)
    end

    def send_confirmation_emails
      return unless SpreeMultivendor::Config.admin_email_on_vendor_registration

      # Send email to vendor
      VendorRegistrationMailer.confirmation_email(@vendor).deliver_later

      # Send email to admin
      VendorRegistrationMailer.admin_notification_email(@vendor).deliver_later
    end
  end
end