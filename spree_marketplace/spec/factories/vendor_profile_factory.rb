# frozen_string_literal: true

FactoryBot.define do
  factory :vendor_profile, class: 'Spree::VendorProfile' do
    association :vendor
    
    business_name { 'Test Business LLC' }
    sequence(:tax_id) { |n| "12-345678#{n % 10}" }
    business_license_number { 'BL123456789' }
    business_type { 'llc' }
    commission_rate { 0.15 }
    payout_schedule { 'monthly' }
    verification_status { 'unverified' }
    
    # Business address
    business_address do
      {
        'street' => '123 Business St',
        'street2' => 'Suite 100',
        'city' => 'Business City',
        'state' => 'CA',
        'country' => 'US',
        'zipcode' => '90210',
        'phone' => '+1-555-0124'
      }
    end
    
    # Tax settings
    tax_settings do
      {
        'tax_exempt' => false,
        'tax_id_type' => 'EIN',
        'vat_number' => nil,
        'tax_classification' => 'C Corporation'
      }
    end
    
    # Business details
    business_details do
      {
        'established_year' => 2020,
        'employee_count' => '10-50',
        'annual_revenue' => '1M-5M',
        'business_description' => 'We provide quality products and services.',
        'website_url' => 'https://testbusiness.example.com',
        'social_media' => {
          'facebook' => 'testbusiness',
          'twitter' => '@testbusiness'
        }
      }
    end
    
    trait :verified do
      verification_status { 'verified' }
      verification_submitted_at { 1.week.ago }
      verification_approved_at { 1.day.ago }
    end
    
    trait :pending_verification do
      verification_status { 'pending_verification' }
      verification_submitted_at { 3.days.ago }
    end
    
    trait :rejected do
      verification_status { 'rejected' }
      verification_submitted_at { 1.week.ago }
      verification_rejected_at { 3.days.ago }
      verification_rejection_reason { 'Documents are not clear enough.' }
    end
    
    trait :requires_update do
      verification_status { 'requires_update' }
      verification_submitted_at { 1.week.ago }
    end
    
    trait :individual do
      business_type { 'individual' }
      business_name { 'John Doe' }
    end
    
    trait :corporation do
      business_type { 'corporation' }
      business_name { 'Test Corporation Inc.' }
    end
    
    trait :high_commission do
      commission_rate { 0.25 }
    end
    
    trait :weekly_payout do
      payout_schedule { 'weekly' }
    end
    
    trait :quarterly_payout do
      payout_schedule { 'quarterly' }
    end
    
    trait :with_bank_details do
      bank_account_details do
        {
          'account_type' => 'business_checking',
          'routing_number' => '123456789',
          'account_number' => '987654321',
          'bank_name' => 'Test Bank',
          'account_holder_name' => 'Test Business LLC'
        }
      end
    end
    
    trait :tax_exempt do
      tax_settings do
        {
          'tax_exempt' => true,
          'tax_id_type' => 'EIN',
          'vat_number' => nil,
          'tax_classification' => 'Non-Profit'
        }
      end
    end
    
    trait :with_documents do
      after(:create) do |profile|
        # Business documents
        profile.business_documents.attach(
          io: File.open(Rails.root.join('spec/fixtures/test_document.pdf')),
          filename: 'business_license.pdf',
          content_type: 'application/pdf'
        )
        
        # Tax documents  
        profile.tax_documents.attach(
          io: File.open(Rails.root.join('spec/fixtures/test_document.pdf')),
          filename: 'tax_document.pdf',
          content_type: 'application/pdf'
        )
        
        # Identity documents
        profile.identity_documents.attach(
          io: File.open(Rails.root.join('spec/fixtures/test_image.jpg')),
          filename: 'drivers_license.jpg', 
          content_type: 'image/jpeg'
        )
      end
    end
    
    trait :complete do
      verified
      with_bank_details
      with_documents
    end
  end
end