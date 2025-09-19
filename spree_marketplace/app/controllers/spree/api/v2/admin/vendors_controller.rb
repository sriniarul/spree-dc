# frozen_string_literal: true

module Spree
  module Api
    module V2
      module Admin
        class VendorsController < ::Spree::Api::V2::Admin::BaseController
          include Spree::Api::V2::CollectionOptionsHelpers
          
          before_action :load_vendor, only: [:show, :update, :destroy, :activate, :suspend, :block, :reject]
          
          # GET /api/v2/admin/vendors
          def index
            render_serialized_payload { serialize_collection(collection) }
          end
          
          # GET /api/v2/admin/vendors/:id
          def show
            render_serialized_payload { serialize_resource(resource) }
          end
          
          # POST /api/v2/admin/vendors
          def create
            spree_authorize! :create, Spree::Vendor
            
            @vendor = Spree::Vendor.new(vendor_params)
            
            if @vendor.save
              render_serialized_payload { serialize_resource(@vendor) }, 201
            else
              render_error_payload(@vendor.errors.full_messages)
            end
          end
          
          # PATCH/PUT /api/v2/admin/vendors/:id
          def update
            spree_authorize! :update, resource
            
            if resource.update(vendor_params)
              render_serialized_payload { serialize_resource(resource) }
            else
              render_error_payload(resource.errors.full_messages)
            end
          end
          
          # DELETE /api/v2/admin/vendors/:id
          def destroy
            spree_authorize! :destroy, resource
            
            if resource.can_be_deleted?
              resource.destroy
              head :no_content
            else
              render_error_payload([Spree.t('api.admin.vendors.cannot_be_deleted')], 422)
            end
          end
          
          # PATCH /api/v2/admin/vendors/:id/activate
          def activate
            spree_authorize! :update, resource
            
            if resource.activate!
              render_serialized_payload { serialize_resource(resource) }
            else
              render_error_payload([Spree.t('api.admin.vendors.activation_failed')], 422)
            end
          rescue StateMachines::InvalidTransition => e
            render_error_payload([e.message], 422)
          end
          
          # PATCH /api/v2/admin/vendors/:id/suspend
          def suspend
            spree_authorize! :update, resource
            
            if resource.suspend!
              render_serialized_payload { serialize_resource(resource) }
            else
              render_error_payload([Spree.t('api.admin.vendors.suspension_failed')], 422)
            end
          rescue StateMachines::InvalidTransition => e
            render_error_payload([e.message], 422)
          end
          
          # PATCH /api/v2/admin/vendors/:id/block
          def block
            spree_authorize! :update, resource
            
            if resource.block!
              render_serialized_payload { serialize_resource(resource) }
            else
              render_error_payload([Spree.t('api.admin.vendors.blocking_failed')], 422)
            end
          rescue StateMachines::InvalidTransition => e
            render_error_payload([e.message], 422)
          end
          
          # PATCH /api/v2/admin/vendors/:id/reject
          def reject
            spree_authorize! :update, resource
            
            if resource.reject!
              render_serialized_payload { serialize_resource(resource) }
            else
              render_error_payload([Spree.t('api.admin.vendors.rejection_failed')], 422)
            end
          rescue StateMachines::InvalidTransition => e
            render_error_payload([e.message], 422)
          end
          
          # POST /api/v2/admin/vendors/bulk_activate
          def bulk_activate
            spree_authorize! :update, Spree::Vendor
            
            vendor_ids = params[:vendor_ids] || []
            activated_vendors = []
            failed_vendors = []
            
            vendor_ids.each do |vendor_id|
              vendor = Spree::Vendor.find(vendor_id)
              spree_authorize! :update, vendor
              
              if vendor.activate!
                activated_vendors << vendor
              else
                failed_vendors << vendor
              end
            rescue ActiveRecord::RecordNotFound, StateMachines::InvalidTransition
              failed_vendors << { id: vendor_id, error: 'Invalid vendor or transition' }
            end
            
            render json: {
              data: {
                activated: activated_vendors.size,
                failed: failed_vendors.size,
                activated_vendors: serialize_collection(activated_vendors)[:data],
                failed_vendors: failed_vendors
              }
            }
          end
          
          # GET /api/v2/admin/vendors/:id/analytics
          def analytics
            spree_authorize! :read, resource
            
            date_range = params[:date_range] || '30'
            start_date = date_range.days.ago.beginning_of_day
            end_date = Time.current.end_of_day
            
            analytics_data = {
              total_sales: resource.order_commissions.completed_orders
                                  .where(created_at: start_date..end_date)
                                  .sum(:base_amount),
              total_commission: resource.order_commissions.paid_out
                                       .where(created_at: start_date..end_date)
                                       .sum(:commission_amount),
              total_orders: resource.orders.complete
                                   .where(completed_at: start_date..end_date)
                                   .count,
              active_products: resource.products.available.count,
              pending_payout: resource.pending_payout_amount,
              monthly_sales: resource.order_commissions.paid_out
                                    .group_by_month(:created_at, last: 12)
                                    .sum(:base_amount)
            }
            
            render json: { data: analytics_data }
          end
          
          private
          
          def resource
            @resource ||= Spree::Vendor.accessible_by(current_ability, :show)
                                      .friendly.find(params[:id])
          end
          
          def collection
            @collection ||= Spree::Vendor.accessible_by(current_ability, :index)
                                        .includes(:vendor_profile, :image, :products, :order_commissions)
                                        .ransack(collection_params).result
                                        .order(:priority, :name)
                                        .page(params[:page])
                                        .per(params[:per_page])
          end
          
          def collection_params
            return {} unless params[:filter]
            
            params[:filter].permit(
              :name_cont, :business_name_cont, :contact_email_cont,
              :state_eq, :priority_eq, :category_list_cont,
              :created_at_gteq, :created_at_lteq,
              :vendor_profile_verification_status_eq,
              :vendor_profile_business_type_eq
            )
          end
          
          def vendor_params
            params.require(:vendor).permit(
              :name, :contact_email, :notification_email, :phone, 
              :about_us, :contact_us, :priority, :state,
              :category_list, :tag_list,
              vendor_profile_attributes: [
                :id, :business_name, :tax_id, :business_license_number, 
                :business_type, :commission_rate, :payout_schedule, 
                :verification_status, :notes,
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
                ]
              ],
              image_attributes: [:id, :attachment, :alt, :_destroy]
            )
          end
          
          def serialize_collection(collection)
            Spree::V2::Admin::VendorSerializer.new(
              collection,
              include: resource_includes,
              sparse_fields: sparse_fields[:vendor],
              params: serialization_params
            ).serializable_hash
          end
          
          def serialize_resource(resource)
            Spree::V2::Admin::VendorSerializer.new(
              resource,
              include: resource_includes,
              sparse_fields: sparse_fields[:vendor],
              params: serialization_params
            ).serializable_hash
          end
          
          def resource_includes
            [
              :vendor_profile,
              :image,
              :products,
              :order_commissions,
              :vendor_payouts,
              categories: [],
              tags: []
            ]
          end
          
          def serialization_params
            {
              current_currency: current_currency,
              current_store: current_store,
              current_user: spree_current_user
            }
          end
          
          def load_vendor
            @vendor = resource
          rescue ActiveRecord::RecordNotFound
            render_error_payload([Spree.t('api.admin.vendor_not_found')], 404)
          end
        end
      end
    end
  end
end