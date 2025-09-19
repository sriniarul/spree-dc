# frozen_string_literal: true

module Spree
  module Admin
    class VendorsController < ResourceController
      include Spree::Admin::Callbacks
      
      # Following exact Spree admin patterns
      before_action :load_vendor_data, only: [:show, :edit]
      before_action :ensure_vendor_profile, only: [:show, :edit, :new]
      
      # Custom actions beyond standard CRUD
      def activate
        @vendor.activate!
        flash[:success] = Spree.t('admin.vendors.activated_successfully')
        redirect_to location_after_save
      rescue StateMachines::InvalidTransition => e
        flash[:error] = Spree.t('admin.vendors.activation_failed', error: e.message)
        redirect_to location_after_save
      end
      
      def suspend
        @vendor.suspend!
        flash[:success] = Spree.t('admin.vendors.suspended_successfully')
        redirect_to location_after_save
      rescue StateMachines::InvalidTransition => e
        flash[:error] = Spree.t('admin.vendors.suspension_failed', error: e.message)
        redirect_to location_after_save
      end
      
      def block
        @vendor.block!
        flash[:success] = Spree.t('admin.vendors.blocked_successfully')
        redirect_to location_after_save
      rescue StateMachines::InvalidTransition => e
        flash[:error] = Spree.t('admin.vendors.blocking_failed', error: e.message)
        redirect_to location_after_save
      end
      
      def reject
        @vendor.reject!
        flash[:success] = Spree.t('admin.vendors.rejected_successfully')
        redirect_to location_after_save
      rescue StateMachines::InvalidTransition => e
        flash[:error] = Spree.t('admin.vendors.rejection_failed', error: e.message)
        redirect_to location_after_save
      end
      
      # Bulk actions following Spree patterns
      def bulk_activate
        vendor_ids = params[:vendor_ids] || []
        activated_count = 0
        
        vendor_ids.each do |vendor_id|
          vendor = Spree::Vendor.find(vendor_id)
          if vendor.activate
            activated_count += 1
          end
        rescue StateMachines::InvalidTransition
          # Skip invalid transitions
        end
        
        flash[:success] = Spree.t('admin.vendors.bulk_activated', count: activated_count)
        redirect_to admin_vendors_path
      end
      
      def bulk_suspend
        vendor_ids = params[:vendor_ids] || []
        suspended_count = 0
        
        vendor_ids.each do |vendor_id|
          vendor = Spree::Vendor.find(vendor_id)
          if vendor.suspend
            suspended_count += 1
          end
        rescue StateMachines::InvalidTransition
          # Skip invalid transitions
        end
        
        flash[:success] = Spree.t('admin.vendors.bulk_suspended', count: suspended_count)
        redirect_to admin_vendors_path
      end
      
      # Analytics and reporting
      def analytics
        @vendor = Spree::Vendor.find(params[:id])
        @date_range = params[:date_range] || '30'
        @start_date = @date_range.days.ago.beginning_of_day
        @end_date = Time.current.end_of_day
        
        @analytics_data = {
          total_sales: @vendor.order_commissions.completed_orders
                             .where(created_at: @start_date..@end_date)
                             .sum(:base_amount),
          total_commission: @vendor.order_commissions.paid_out
                                  .where(created_at: @start_date..@end_date)
                                  .sum(:commission_amount),
          total_orders: @vendor.orders.complete
                              .where(completed_at: @start_date..@end_date)
                              .count,
          active_products: @vendor.products.available.count,
          pending_payout: @vendor.pending_payout_amount
        }
        
        @monthly_sales = @vendor.order_commissions.paid_out
                               .group_by_month(:created_at, last: 12)
                               .sum(:base_amount)
                               
        @top_products = @vendor.products.joins(:variants => :line_items)
                              .group('spree_products.id', 'spree_products.name')
                              .order('SUM(spree_line_items.quantity * spree_line_items.price) DESC')
                              .limit(10)
                              .sum('spree_line_items.quantity * spree_line_items.price')
      end
      
      # Export functionality
      def export
        respond_to do |format|
          format.csv do
            send_data generate_csv_export, 
                     filename: "vendors_export_#{Date.current.strftime('%Y%m%d')}.csv",
                     type: 'text/csv'
          end
          format.xlsx do
            send_data generate_xlsx_export,
                     filename: "vendors_export_#{Date.current.strftime('%Y%m%d')}.xlsx",
                     type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          end
        end
      end
      
      private
      
      # Following Spree ResourceController patterns
      def collection
        return @collection if @collection
        
        @search = Spree::Vendor.accessible_by(current_ability, :index)
                               .includes(:vendor_profile, :image, :products, :order_commissions)
                               .ransack(params[:q])
        
        @collection = @search.result
                             .page(params[:page])
                             .per(params[:per_page] || Spree::Config[:admin_vendors_per_page])
      end
      
      def permitted_resource_params
        params.require(:vendor).permit(
          :name, :contact_email, :notification_email, :phone, :about_us, :contact_us,
          :priority, :state,
          vendor_profile_attributes: [
            :id, :business_name, :tax_id, :business_license_number, :business_type,
            :commission_rate, :payout_schedule, :verification_status, :notes,
            business_address: [:street, :street2, :city, :state, :country, :zipcode, :phone],
            tax_settings: [:tax_exempt, :tax_id_type, :vat_number, :tax_classification],
            business_details: [:established_year, :employee_count, :annual_revenue, 
                             :business_description, :website_url, :social_media],
            bank_account_details: [:account_type, :routing_number, :account_number,
                                 :bank_name, :account_holder_name]
          ],
          image_attributes: [:id, :attachment, :alt, :_destroy]
        )
      end
      
      def load_vendor_data
        return unless @vendor
        
        @recent_orders = @vendor.orders.recent.limit(10)
        @commission_total = @vendor.order_commissions.sum(:commission_amount)
        @payout_total = @vendor.vendor_payouts.completed.sum(:net_amount)
        @products_count = @vendor.products.count
        @active_products_count = @vendor.products.available.count
      end
      
      def ensure_vendor_profile
        if @vendor&.vendor_profile.blank?
          @vendor.build_vendor_profile
        end
      end
      
      def location_after_save
        if action_name == 'create'
          edit_admin_vendor_path(@vendor)
        else
          admin_vendor_path(@vendor)
        end
      end
      
      def location_after_destroy
        admin_vendors_path
      end
      
      # Export methods
      def generate_csv_export
        CSV.generate(headers: true) do |csv|
          csv << [
            'ID', 'Name', 'Business Name', 'Email', 'Phone', 'State', 
            'Commission Rate', 'Total Sales', 'Products Count', 'Created At'
          ]
          
          collection.includes(:vendor_profile).each do |vendor|
            csv << [
              vendor.id,
              vendor.name,
              vendor.vendor_profile&.business_name,
              vendor.contact_email,
              vendor.phone,
              vendor.state.humanize,
              vendor.commission_rate,
              vendor.total_sales,
              vendor.products.count,
              vendor.created_at.strftime('%Y-%m-%d')
            ]
          end
        end
      end
      
      def generate_xlsx_export
        # Implementation for Excel export
        # This would require the 'roo' or 'axlsx' gem
        # Placeholder for now
        generate_csv_export
      end
      
      # Override Spree's flash messages
      def message_after_create
        Spree.t('admin.vendors.created_successfully')
      end
      
      def message_after_update
        Spree.t('admin.vendors.updated_successfully')
      end
      
      # Turbo Stream support following Spree patterns
      def update_turbo_stream_enabled?
        true
      end
      
      def create_turbo_stream_enabled?
        true
      end
      
      def destroy_turbo_stream_enabled?
        true
      end
    end
  end
end