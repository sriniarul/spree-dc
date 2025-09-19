# frozen_string_literal: true

FactoryBot.define do
  factory :vendor, class: 'Spree::Vendor' do
    sequence(:name) { |n| "Test Vendor #{n}" }
    sequence(:contact_email) { |n| "vendor#{n}@example.com" }
    phone { '+1-555-0123' }
    about_us { 'We are a test vendor providing quality products.' }
    contact_us { 'Contact us at our email or phone number.' }
    priority { 0 }
    state { 'pending' }
    
    # Automatically create vendor profile
    after(:build) do |vendor|
      vendor.vendor_profile ||= build(:vendor_profile, vendor: vendor)
    end
    
    trait :active do
      state { 'active' }
    end
    
    trait :suspended do
      state { 'suspended' }
    end
    
    trait :blocked do
      state { 'blocked' }
    end
    
    trait :rejected do
      state { 'rejected' }  
    end
    
    trait :with_logo do
      after(:create) do |vendor|
        vendor.create_image(
          attachment: Rack::Test::UploadedFile.new(
            File.join(Rails.root, 'spec', 'fixtures', 'thinking-cat.jpg'),
            'image/jpeg'
          )
        )
      end
    end
    
    trait :with_products do
      transient do
        products_count { 3 }
      end
      
      after(:create) do |vendor, evaluator|
        create_list(:product, evaluator.products_count, vendor: vendor)
      end
    end
    
    trait :with_orders do
      transient do
        orders_count { 2 }
      end
      
      after(:create) do |vendor, evaluator|
        products = create_list(:product, 2, vendor: vendor)
        evaluator.orders_count.times do
          order = create(:order_with_line_items, line_items_count: 1)
          order.line_items.first.variant.product.update!(vendor: vendor)
          create(:order_commission, order: order, vendor: vendor)
        end
      end
    end
    
    trait :high_commission do
      after(:build) do |vendor|
        vendor.vendor_profile.commission_rate = 0.25
      end
    end
    
    trait :verified do
      after(:build) do |vendor|
        vendor.vendor_profile.verification_status = 'verified'
      end
    end
    
    trait :with_categories do
      transient do
        categories { ['Electronics', 'Fashion'] }
      end
      
      after(:create) do |vendor, evaluator|
        vendor.category_list.add(evaluator.categories)
        vendor.save!
      end
    end
    
    trait :with_tags do
      transient do
        tags { ['premium', 'fast-shipping'] }
      end
      
      after(:create) do |vendor, evaluator|
        vendor.tag_list.add(evaluator.tags)
        vendor.save!
      end
    end
    
    # Complete vendor for integration tests
    trait :complete do
      active
      verified
      with_logo
      with_products
      with_categories
      with_tags
    end
  end
end