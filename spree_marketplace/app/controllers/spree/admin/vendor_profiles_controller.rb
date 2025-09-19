# frozen_string_literal: true

module Spree
  module Admin
    class VendorProfilesController < ResourceController
      include Spree::Admin::Callbacks
      
      # Nested resource - always belongs to a vendor
      before_action :load_vendor
      before_action :ensure_vendor_profile, only: [:show, :edit, :new]
      before_action :check_vendor_permissions
      
      # Verification workflow actions
      def approve_verification
        if @vendor_profile.approve_verification!(try_spree_current_user)
          flash[:success] = Spree.t('admin.vendor_profiles.verification_approved')
        else
          flash[:error] = Spree.t('admin.vendor_profiles.verification_approval_failed')
        end
        
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.reload('verification_status') }
          format.html { redirect_to location_after_save }
        end
      end
      
      def reject_verification
        rejection_reason = params[:rejection_reason]
        
        if rejection_reason.blank?
          flash[:error] = Spree.t('admin.vendor_profiles.rejection_reason_required')
          redirect_to location_after_save
          return
        end
        
        if @vendor_profile.reject_verification!(rejection_reason, try_spree_current_user)
          flash[:success] = Spree.t('admin.vendor_profiles.verification_rejected')
        else
          flash[:error] = Spree.t('admin.vendor_profiles.verification_rejection_failed')
        end
        
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.reload('verification_status') }
          format.html { redirect_to location_after_save }
        end
      end
      
      def request_update
        @vendor_profile.update!(verification_status: :requires_update)
        
        flash[:success] = Spree.t('admin.vendor_profiles.update_requested')
        VendorMailer.verification_update_required(@vendor, params[:update_message]).deliver_later
        
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.reload('verification_status') }
          format.html { redirect_to location_after_save }
        end
      end
      
      # Document management
      def download_document
        document_type = params[:document_type] # business_documents, tax_documents, etc.
        document_id = params[:document_id]
        
        documents = @vendor_profile.send(document_type)
        document = documents.find(document_id)
        
        if document.present?
          redirect_to rails_blob_path(document, disposition: 'attachment')
        else
          flash[:error] = Spree.t('admin.vendor_profiles.document_not_found')
          redirect_to location_after_save
        end
      rescue ActiveStorage::FileNotFoundError
        flash[:error] = Spree.t('admin.vendor_profiles.document_not_available')
        redirect_to location_after_save
      end
      
      def remove_document
        document_type = params[:document_type]
        document_id = params[:document_id]
        
        documents = @vendor_profile.send(document_type)
        document = documents.find(document_id)
        
        if document&.purge
          flash[:success] = Spree.t('admin.vendor_profiles.document_removed')
        else
          flash[:error] = Spree.t('admin.vendor_profiles.document_removal_failed')
        end
        
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.remove("document_#{document_id}")
          end
          format.html { redirect_to location_after_save }
        end
      end
      
      # Commission rate management
      def update_commission_rate
        new_rate = params[:commission_rate].to_f
        
        if new_rate >= 0.05 && new_rate <= 0.50
          @vendor_profile.update!(commission_rate: new_rate)
          
          # Log commission rate change
          @vendor_profile.metadata['commission_rate_history'] ||= []
          @vendor_profile.metadata['commission_rate_history'] << {
            rate: new_rate,
            changed_by: try_spree_current_user&.email,
            changed_at: Time.current.iso8601
          }
          @vendor_profile.save!
          
          flash[:success] = Spree.t('admin.vendor_profiles.commission_rate_updated')
        else
          flash[:error] = Spree.t('admin.vendor_profiles.invalid_commission_rate')
        end
        
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.reload('commission_settings') }
          format.html { redirect_to location_after_save }
        end
      end
      
      # Payout schedule management
      def update_payout_schedule
        new_schedule = params[:payout_schedule]
        valid_schedules = Spree::VendorProfile.payout_schedules.keys
        
        if valid_schedules.include?(new_schedule)
          @vendor_profile.update!(payout_schedule: new_schedule)
          flash[:success] = Spree.t('admin.vendor_profiles.payout_schedule_updated')
        else
          flash[:error] = Spree.t('admin.vendor_profiles.invalid_payout_schedule')
        end
        
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.reload('payout_settings') }
          format.html { redirect_to location_after_save }
        end
      end
      
      # Analytics for this vendor profile
      def analytics
        @date_range = params[:date_range] || '30'
        @start_date = @date_range.days.ago.beginning_of_day
        @end_date = Time.current.end_of_day
        
        @profile_analytics = {
          verification_duration: verification_processing_time,
          documents_count: total_documents_count,
          commission_changes: commission_rate_changes_count,
          business_age: @vendor_profile.business_age_years,
          next_payout_date: @vendor_profile.next_payout_date
        }
        
        render 'analytics'
      end
      
      private
      
      def load_vendor
        @vendor = Spree::Vendor.friendly.find(params[:vendor_id])
      rescue ActiveRecord::RecordNotFound
        flash[:error] = Spree.t('admin.vendors.not_found')
        redirect_to admin_vendors_path
      end
      
      def ensure_vendor_profile
        @vendor_profile = @vendor.vendor_profile || @vendor.build_vendor_profile
        @object = @vendor_profile # For ResourceController compatibility
      end
      
      def check_vendor_permissions
        authorize! action_name.to_sym, @vendor_profile
      end
      
      def collection
        # Not used for nested resource, but required by ResourceController
        Spree::VendorProfile.none
      end
      
      def permitted_resource_params
        params.require(:vendor_profile).permit(
          :business_name, :tax_id, :business_license_number, :business_type,
          :commission_rate, :payout_schedule, :verification_status, :notes,
          business_address: [
            :street, :street2, :city, :state, :country, :zipcode, :phone
          ],
          tax_settings: [
            :tax_exempt, :tax_id_type, :vat_number, :tax_classification
          ],
          business_details: [
            :established_year, :employee_count, :annual_revenue,
            :business_description, :website_url, :social_media
          ],
          bank_account_details: [
            :account_type, :routing_number, :account_number,
            :bank_name, :account_holder_name
          ],
          business_documents: [],
          tax_documents: [],
          identity_documents: [],
          bank_documents: []
        )
      end
      
      def location_after_save
        admin_vendor_vendor_profile_path(@vendor, @vendor_profile)
      end
      
      def location_after_destroy
        admin_vendor_path(@vendor)
      end
      
      # Helper methods for analytics
      def verification_processing_time
        return nil unless @vendor_profile.verification_submitted_at
        
        end_time = @vendor_profile.verification_approved_at || 
                  @vendor_profile.verification_rejected_at || 
                  Time.current
                  
        ((end_time - @vendor_profile.verification_submitted_at) / 1.day).round(1)
      end
      
      def total_documents_count
        @vendor_profile.business_documents.count +
        @vendor_profile.tax_documents.count +
        @vendor_profile.identity_documents.count +
        @vendor_profile.bank_documents.count
      end
      
      def commission_rate_changes_count
        @vendor_profile.metadata['commission_rate_history']&.length || 0
      end
      
      # Override ResourceController methods
      def model_class
        Spree::VendorProfile
      end
      
      def object_name
        'vendor_profile'
      end
      
      def load_resource
        @vendor_profile = @vendor.vendor_profile || @vendor.build_vendor_profile
        @object = @vendor_profile
        
        if member_action?
          @vendor_profile = @vendor.vendor_profile
          unless @vendor_profile
            flash[:error] = Spree.t('admin.vendor_profiles.not_found')
            redirect_to admin_vendor_path(@vendor)
            return
          end
        end
      end
      
      def member_action?
        %w[show edit update destroy].include?(action_name)
      end
      
      # Flash messages
      def flash_message_for(object, event_sym)
        resource_desc = Spree.t('admin.vendor_profiles.vendor_profile')
        Spree.t("admin.#{event_sym}", resource: resource_desc)
      end
      
      # Turbo Stream support
      def update_turbo_stream_enabled?
        true
      end
      
      def create_turbo_stream_enabled?
        true
      end
    end
  end
end