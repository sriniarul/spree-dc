module Spree
  module Admin
    class VendorsController < ResourceController
      before_action :load_vendor, only: [:show, :edit, :update, :approve, :reject, :suspend, :activate]

      def index
        params[:q] ||= {}
        @search = Spree::Vendor.ransack(params[:q])
        @vendors = @search.result
                         .includes(:user, :country)
                         .page(params[:page])
                         .per(params[:per_page] || 25)

        # For the filters
        @countries = Spree::Country.order(:name)
      end

      def show
        @vendor = Spree::Vendor.includes(:user, :country, :products).find(params[:id])
      end

      def new
        @vendor = Spree::Vendor.new
      end

      def create
        @vendor = Spree::Vendor.new(vendor_params)

        if @vendor.save
          flash[:success] = Spree.t('admin.vendors.create.success')
          redirect_to admin_vendor_path(@vendor)
        else
          flash[:error] = Spree.t('admin.vendors.create.error')
          render :new
        end
      end

      def edit
      end

      def update
        if @vendor.update(vendor_params)
          flash[:success] = Spree.t('admin.vendors.update.success')
          redirect_to admin_vendor_path(@vendor)
        else
          flash[:error] = Spree.t('admin.vendors.update.error')
          render :edit
        end
      end

      def approve
        if @vendor.approve!
          flash[:success] = Spree.t('admin.vendors.approve.success', vendor_name: @vendor.display_name)
          send_approval_notification
        else
          flash[:error] = Spree.t('admin.vendors.approve.error')
        end
        redirect_to "/admin/vendors/#{@vendor.id}"
      end

      def reject
        if @vendor.reject!
          flash[:success] = Spree.t('admin.vendors.reject.success', vendor_name: @vendor.display_name)
          send_rejection_notification
        else
          flash[:error] = Spree.t('admin.vendors.reject.error')
        end
        redirect_to "/admin/vendors/#{@vendor.id}"
      end

      def suspend
        if @vendor.suspend!
          flash[:success] = Spree.t('admin.vendors.suspend.success', vendor_name: @vendor.display_name)
        else
          flash[:error] = Spree.t('admin.vendors.suspend.error')
        end
        redirect_to "/admin/vendors/#{@vendor.id}"
      end

      def activate
        if @vendor.activate!
          flash[:success] = Spree.t('admin.vendors.activate.success', vendor_name: @vendor.display_name)
        else
          flash[:error] = Spree.t('admin.vendors.activate.error')
        end
        redirect_to "/admin/vendors/#{@vendor.id}"
      end

      def destroy
        if @vendor.destroy
          flash[:success] = Spree.t('admin.vendors.destroy.success')
        else
          flash[:error] = Spree.t('admin.vendors.destroy.error')
        end
        redirect_to admin_vendors_path
      end

      private

      def load_vendor
        @vendor = Spree::Vendor.find(params[:id])
      end

      def vendor_params
        params.require(:vendor).permit(
          :name, :legal_name, :business_type, :trade_name, :registration_number,
          :incorporation_date, :country_code, :state_province, :city,
          :postal_code, :address_line1, :address_line2, :phone_number,
          :website_url, :user_id, :state
        )
      end

      def send_approval_notification
        # Skip email sending for now - can be enabled later
        # Spree::VendorRegistrationMailer.approval_notification(@vendor).deliver_later
      end

      def send_rejection_notification
        # Skip email sending for now - can be enabled later
        # Spree::VendorRegistrationMailer.rejection_notification(@vendor).deliver_later
      end
    end
  end
end