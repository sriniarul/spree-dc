# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Spree::Vendor, type: :model do
  subject(:vendor) { build(:vendor) }
  
  describe 'associations' do
    it { is_expected.to have_one(:vendor_profile).dependent(:destroy) }
    it { is_expected.to have_one(:image).dependent(:destroy) }
    it { is_expected.to have_many(:vendor_users).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:vendor_users) }
    it { is_expected.to have_many(:products).dependent(:restrict_with_exception) }
    it { is_expected.to have_many(:variants).through(:products) }
    it { is_expected.to have_many(:stock_locations).dependent(:destroy) }
    it { is_expected.to have_many(:order_commissions).dependent(:destroy) }
    it { is_expected.to have_many(:vendor_payouts).dependent(:destroy) }
  end
  
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:contact_email) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:deleted_at) }
    it { is_expected.to validate_uniqueness_of(:contact_email).scoped_to(:deleted_at) }
    it { is_expected.to validate_uniqueness_of(:slug).scoped_to(:deleted_at) }
    
    it 'validates email format' do
      vendor.contact_email = 'invalid-email'
      expect(vendor).not_to be_valid
      expect(vendor.errors[:contact_email]).to include('is invalid')
    end
    
    it 'validates phone format' do
      vendor.phone = 'abc123'
      expect(vendor).not_to be_valid
      expect(vendor.errors[:phone]).to include('is invalid')
    end
  end
  
  describe 'scopes' do
    let!(:active_vendor) { create(:vendor, :active) }
    let!(:pending_vendor) { create(:vendor, :pending) }
    let!(:suspended_vendor) { create(:vendor, :suspended) }
    let!(:blocked_vendor) { create(:vendor, :blocked) }
    
    describe '.active' do
      it 'returns only active vendors' do
        expect(described_class.active).to contain_exactly(active_vendor)
      end
    end
    
    describe '.pending' do
      it 'returns only pending vendors' do
        expect(described_class.pending).to contain_exactly(pending_vendor)
      end
    end
    
    describe '.suspended' do
      it 'returns only suspended vendors' do
        expect(described_class.suspended).to contain_exactly(suspended_vendor)
      end
    end
    
    describe '.blocked' do
      it 'returns only blocked vendors' do
        expect(described_class.blocked).to contain_exactly(blocked_vendor)
      end
    end
    
    describe '.by_priority' do
      let!(:high_priority_vendor) { create(:vendor, priority: 10) }
      let!(:low_priority_vendor) { create(:vendor, priority: 1) }
      
      it 'orders vendors by priority and name' do
        expect(described_class.by_priority.first).to eq(low_priority_vendor)
      end
    end
  end
  
  describe 'state machine' do
    context 'when pending' do
      subject(:vendor) { create(:vendor, state: 'pending') }
      
      it 'can be activated' do
        expect(vendor.can_activate?).to be true
        expect { vendor.activate! }.to change(vendor, :state).from('pending').to('active')
      end
      
      it 'can be rejected' do
        expect(vendor.can_reject?).to be true
        expect { vendor.reject! }.to change(vendor, :state).from('pending').to('rejected')
      end
      
      it 'can be blocked' do
        expect(vendor.can_block?).to be true
        expect { vendor.block! }.to change(vendor, :state).from('pending').to('blocked')
      end
    end
    
    context 'when active' do
      subject(:vendor) { create(:vendor, :active) }
      
      it 'can be suspended' do
        expect(vendor.can_suspend?).to be true
        expect { vendor.suspend! }.to change(vendor, :state).from('active').to('suspended')
      end
      
      it 'can be blocked' do
        expect(vendor.can_block?).to be true
        expect { vendor.block! }.to change(vendor, :state).from('active').to('blocked')
      end
      
      it 'cannot be activated again' do
        expect(vendor.can_activate?).to be false
      end
    end
    
    context 'when suspended' do
      subject(:vendor) { create(:vendor, :suspended) }
      
      it 'can be activated' do
        expect(vendor.can_activate?).to be true
        expect { vendor.activate! }.to change(vendor, :state).from('suspended').to('active')
      end
      
      it 'can be blocked' do
        expect(vendor.can_block?).to be true
        expect { vendor.block! }.to change(vendor, :state).from('suspended').to('blocked')
      end
    end
  end
  
  describe 'callbacks' do
    context 'when activated' do
      subject(:vendor) { create(:vendor, :pending) }
      
      it 'creates default stock location' do
        expect { vendor.activate! }.to change(vendor.stock_locations, :count).by(1)
      end
      
      it 'sends activation email' do
        expect(VendorMailer).to receive(:activation_notification).with(vendor).and_call_original
        expect_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_later)
        vendor.activate!
      end
    end
    
    context 'when suspended' do
      subject(:vendor) { create(:vendor, :active, :with_products) }
      
      it 'deactivates products' do
        vendor.suspend!
        expect(vendor.products.reload.all? { |p| p.status == 'archived' }).to be true
      end
      
      it 'sends suspension email' do
        expect(VendorMailer).to receive(:suspension_notification).with(vendor).and_call_original
        expect_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_later)
        vendor.suspend!
      end
    end
  end
  
  describe 'business logic methods' do
    describe '#can_be_deleted?' do
      context 'without associated records' do
        it 'returns true' do
          expect(vendor.can_be_deleted?).to be true
        end
      end
      
      context 'with products' do
        subject(:vendor) { create(:vendor, :with_products) }
        
        it 'returns false' do
          expect(vendor.can_be_deleted?).to be false
        end
      end
      
      context 'with order commissions' do
        subject(:vendor) { create(:vendor, :with_orders) }
        
        it 'returns false' do
          expect(vendor.can_be_deleted?).to be false
        end
      end
    end
    
    describe '#total_sales' do
      subject(:vendor) { create(:vendor, :active) }
      
      it 'calculates total sales from paid commissions' do
        create(:order_commission, vendor: vendor, base_amount: 100.0, status: 'paid')
        create(:order_commission, vendor: vendor, base_amount: 200.0, status: 'paid')
        create(:order_commission, vendor: vendor, base_amount: 50.0, status: 'pending')
        
        expect(vendor.total_sales).to eq(300.0)
      end
    end
    
    describe '#commission_rate' do
      context 'with vendor profile' do
        subject(:vendor) { create(:vendor, :high_commission) }
        
        it 'returns profile commission rate' do
          expect(vendor.commission_rate).to eq(0.25)
        end
      end
      
      context 'without vendor profile' do
        subject(:vendor) { build(:vendor) }
        
        before { vendor.vendor_profile = nil }
        
        it 'returns default commission rate' do
          expect(vendor.commission_rate).to eq(SpreeMarketplace.configuration.default_commission_rate)
        end
      end
    end
    
    describe '#display_name' do
      context 'with business name' do
        subject(:vendor) { create(:vendor) }
        
        it 'returns business name' do
          expect(vendor.display_name).to eq(vendor.vendor_profile.business_name)
        end
      end
      
      context 'without business name' do
        subject(:vendor) { build(:vendor) }
        
        before { vendor.vendor_profile.business_name = nil }
        
        it 'returns vendor name' do
          expect(vendor.display_name).to eq(vendor.name)
        end
      end
    end
  end
  
  describe 'slug generation' do
    it 'generates slug from name' do
      vendor = create(:vendor, name: 'Test Vendor Name')
      expect(vendor.slug).to eq('test-vendor-name')
    end
    
    it 'handles duplicate names' do
      create(:vendor, name: 'Duplicate Name')
      vendor2 = create(:vendor, name: 'Duplicate Name')
      expect(vendor2.slug).to match(/duplicate-name-\w+/)
    end
    
    it 'regenerates slug when name changes' do
      vendor = create(:vendor, name: 'Original Name')
      original_slug = vendor.slug
      
      vendor.update!(name: 'New Name')
      expect(vendor.slug).not_to eq(original_slug)
      expect(vendor.slug).to eq('new-name')
    end
  end
  
  describe 'friendly finder' do
    let!(:vendor) { create(:vendor, name: 'Test Vendor') }
    
    it 'finds by slug' do
      expect(described_class.friendly.find(vendor.slug)).to eq(vendor)
    end
    
    it 'finds by id as fallback' do
      expect(described_class.friendly.find(vendor.id)).to eq(vendor)
    end
  end
  
  describe 'soft deletion' do
    let!(:vendor) { create(:vendor) }
    
    it 'soft deletes vendor' do
      expect { vendor.destroy }.to change(vendor, :deleted_at).from(nil)
      expect(vendor.persisted?).to be true
    end
    
    it 'excludes deleted vendors from default scope' do
      vendor.destroy
      expect(described_class.all).not_to include(vendor)
    end
    
    it 'includes deleted vendors in with_deleted scope' do
      vendor.destroy
      expect(described_class.with_deleted).to include(vendor)
    end
  end
  
  describe 'translatable fields' do
    it 'includes expected translatable fields' do
      expect(described_class::TRANSLATABLE_FIELDS).to include(:name, :about_us, :contact_us)
    end
  end
end