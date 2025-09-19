# frozen_string_literal: true

module Spree
  class VendorUser < Spree.base_class
    # Core Spree patterns
    include Spree::Metadata
    
    # Associations following Spree patterns  
    belongs_to :vendor, inverse_of: :vendor_users
    belongs_to :user, class_name: Spree.user_class.to_s
    
    # Role enumeration for vendor team management
    enum role: {
      owner: 0,      # Full access, can manage team, settings, payouts
      manager: 1,    # Can manage products, orders, inventory, view analytics
      staff: 2,      # Can manage assigned products and orders
      accountant: 3, # Can view financial data, analytics, payouts
      viewer: 4      # Read-only access to vendor dashboard
    }, _prefix: true
    
    # Invitation status
    enum invitation_status: {
      pending: 0,
      accepted: 1,
      declined: 2,
      expired: 3,
      revoked: 4
    }, _prefix: true
    
    # Validations following Spree patterns
    validates :vendor_id, uniqueness: { scope: :user_id }, 
                          presence: true
    validates :user_id, presence: true
    validates :role, presence: true
    validates :invitation_status, presence: true
    
    # Ensure only one owner per vendor
    validates :role, uniqueness: { scope: :vendor_id }, 
              if: :role_owner?, 
              message: 'Only one owner allowed per vendor'
    
    # JSON store accessors for permissions
    store_accessor :permissions,
                   :can_manage_products, :can_edit_products, :can_delete_products,
                   :can_manage_inventory, :can_view_inventory,
                   :can_manage_orders, :can_view_orders, :can_fulfill_orders,
                   :can_view_analytics, :can_export_data,
                   :can_manage_settings, :can_view_payouts,
                   :can_invite_users, :can_manage_team
    
    # Scopes for admin and vendor management
    scope :active, -> { joins(:user).where(users: { deleted_at: nil }) }
    scope :owners, -> { where(role: :owner) }
    scope :managers, -> { where(role: :manager) }
    scope :pending_invitations, -> { where(invitation_status: :pending) }
    scope :accepted, -> { where(invitation_status: :accepted) }
    scope :by_role, ->(role) { where(role: role) }
    scope :recent, -> { order(created_at: :desc) }
    
    # Callbacks
    before_validation :set_default_permissions
    before_validation :set_invitation_token, if: :new_record?
    after_create :send_invitation_email, if: :should_send_invitation?
    after_update :send_role_changed_email, if: :saved_change_to_role?
    
    # Ransack configuration
    def self.ransackable_attributes(auth_object = nil)
      %w[role invitation_status created_at updated_at invited_at accepted_at]
    end
    
    def self.ransackable_associations(auth_object = nil)
      %w[vendor user]
    end
    
    # Business logic methods
    def name
      user&.full_name || user&.email || 'Unknown User'
    end
    
    def email
      user&.email
    end
    
    def active?
      user.present? && !user.deleted? && invitation_status_accepted?
    end
    
    def pending_invitation?
      invitation_status_pending? && invitation_token.present?
    end
    
    def invitation_expired?
      invitation_status_expired? || 
      (invited_at.present? && invited_at < 7.days.ago)
    end
    
    def can_be_deleted?
      !role_owner? || vendor.vendor_users.role_owner.count > 1
    end
    
    # Permission checks
    def can_manage_products?
      role_owner? || role_manager? || permissions['can_manage_products'] == true
    end
    
    def can_edit_products?
      can_manage_products? || permissions['can_edit_products'] == true
    end
    
    def can_delete_products?
      role_owner? || permissions['can_delete_products'] == true
    end
    
    def can_manage_inventory?
      role_owner? || role_manager? || permissions['can_manage_inventory'] == true
    end
    
    def can_view_inventory?
      can_manage_inventory? || permissions['can_view_inventory'] == true
    end
    
    def can_manage_orders?
      role_owner? || role_manager? || permissions['can_manage_orders'] == true
    end
    
    def can_view_orders?
      can_manage_orders? || permissions['can_view_orders'] == true
    end
    
    def can_fulfill_orders?
      can_manage_orders? || permissions['can_fulfill_orders'] == true
    end
    
    def can_view_analytics?
      role_owner? || role_manager? || role_accountant? || 
      permissions['can_view_analytics'] == true
    end
    
    def can_export_data?
      role_owner? || permissions['can_export_data'] == true
    end
    
    def can_manage_settings?
      role_owner? || permissions['can_manage_settings'] == true
    end
    
    def can_view_payouts?
      role_owner? || role_accountant? || permissions['can_view_payouts'] == true
    end
    
    def can_invite_users?
      role_owner? || permissions['can_invite_users'] == true
    end
    
    def can_manage_team?
      role_owner? || permissions['can_manage_team'] == true
    end
    
    # Invitation workflow methods
    def send_invitation!
      return false if invitation_status_accepted?
      
      self.invitation_token = generate_invitation_token
      self.invited_at = Time.current
      self.invitation_status = :pending
      
      if save
        VendorMailer.team_invitation(self).deliver_later
        true
      else
        false
      end
    end
    
    def resend_invitation!
      return false unless invitation_status_pending? || invitation_status_expired?
      
      send_invitation!
    end
    
    def accept_invitation!(accepting_user)
      return false unless invitation_status_pending?
      return false unless accepting_user == user
      return false if invitation_expired?
      
      update!(
        invitation_status: :accepted,
        accepted_at: Time.current,
        invitation_token: nil
      )
    end
    
    def decline_invitation!
      return false unless invitation_status_pending?
      
      update!(
        invitation_status: :declined,
        declined_at: Time.current,
        invitation_token: nil
      )
    end
    
    def revoke_invitation!
      return false unless invitation_status_pending?
      
      update!(
        invitation_status: :revoked,
        revoked_at: Time.current,
        invitation_token: nil
      )
    end
    
    def expire_invitation!
      return false unless invitation_status_pending?
      
      update!(
        invitation_status: :expired,
        expired_at: Time.current,
        invitation_token: nil
      )
    end
    
    # Role management methods
    def promote_to_manager!
      return false if role_owner?
      
      update!(role: :manager)
    end
    
    def demote_to_staff!
      return false if role_owner?
      
      update!(role: :staff)
    end
    
    def transfer_ownership_to!(new_owner_user)
      return false unless role_owner?
      return false unless new_owner_user.is_a?(VendorUser)
      return false unless new_owner_user.vendor == vendor
      
      transaction do
        # Demote current owner to manager
        update!(role: :manager)
        # Promote new user to owner
        new_owner_user.update!(role: :owner)
      end
      
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
    
    private
    
    def set_default_permissions
      self.permissions ||= {}
      
      case role&.to_sym
      when :owner
        set_owner_permissions
      when :manager  
        set_manager_permissions
      when :staff
        set_staff_permissions
      when :accountant
        set_accountant_permissions
      when :viewer
        set_viewer_permissions
      end
    end
    
    def set_owner_permissions
      self.permissions = {
        can_manage_products: true,
        can_edit_products: true,
        can_delete_products: true,
        can_manage_inventory: true,
        can_view_inventory: true,
        can_manage_orders: true,
        can_view_orders: true,
        can_fulfill_orders: true,
        can_view_analytics: true,
        can_export_data: true,
        can_manage_settings: true,
        can_view_payouts: true,
        can_invite_users: true,
        can_manage_team: true
      }
    end
    
    def set_manager_permissions
      self.permissions = {
        can_manage_products: true,
        can_edit_products: true,
        can_delete_products: false,
        can_manage_inventory: true,
        can_view_inventory: true,
        can_manage_orders: true,
        can_view_orders: true,
        can_fulfill_orders: true,
        can_view_analytics: true,
        can_export_data: false,
        can_manage_settings: false,
        can_view_payouts: false,
        can_invite_users: true,
        can_manage_team: false
      }
    end
    
    def set_staff_permissions
      self.permissions = {
        can_manage_products: false,
        can_edit_products: true,
        can_delete_products: false,
        can_manage_inventory: false,
        can_view_inventory: true,
        can_manage_orders: false,
        can_view_orders: true,
        can_fulfill_orders: true,
        can_view_analytics: false,
        can_export_data: false,
        can_manage_settings: false,
        can_view_payouts: false,
        can_invite_users: false,
        can_manage_team: false
      }
    end
    
    def set_accountant_permissions
      self.permissions = {
        can_manage_products: false,
        can_edit_products: false,
        can_delete_products: false,
        can_manage_inventory: false,
        can_view_inventory: true,
        can_manage_orders: false,
        can_view_orders: true,
        can_fulfill_orders: false,
        can_view_analytics: true,
        can_export_data: true,
        can_manage_settings: false,
        can_view_payouts: true,
        can_invite_users: false,
        can_manage_team: false
      }
    end
    
    def set_viewer_permissions
      self.permissions = {
        can_manage_products: false,
        can_edit_products: false,
        can_delete_products: false,
        can_manage_inventory: false,
        can_view_inventory: true,
        can_manage_orders: false,
        can_view_orders: true,
        can_fulfill_orders: false,
        can_view_analytics: false,
        can_export_data: false,
        can_manage_settings: false,
        can_view_payouts: false,
        can_invite_users: false,
        can_manage_team: false
      }
    end
    
    def set_invitation_token
      return if invitation_token.present?
      
      self.invitation_token = generate_invitation_token
    end
    
    def generate_invitation_token
      loop do
        token = SecureRandom.urlsafe_base64(32)
        break token unless self.class.exists?(invitation_token: token)
      end
    end
    
    def should_send_invitation?
      invitation_status_pending? && user.present?
    end
    
    def send_invitation_email
      VendorMailer.team_invitation(self).deliver_later
    end
    
    def send_role_changed_email
      VendorMailer.role_changed_notification(self).deliver_later
    end
  end
end