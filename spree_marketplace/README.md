# SpreeMarketplace

[![Gem Version](https://badge.fury.io/rb/spree_marketplace.svg)](https://badge.fury.io/rb/spree_marketplace)
[![CI](https://github.com/yourusername/spree_marketplace/workflows/CI/badge.svg)](https://github.com/yourusername/spree_marketplace/actions)
[![Code Climate](https://codeclimate.com/github/yourusername/spree_marketplace/badges/gpa.svg)](https://codeclimate.com/github/yourusername/spree_marketplace)
[![Test Coverage](https://codeclimate.com/github/yourusername/spree_marketplace/badges/coverage.svg)](https://codeclimate.com/github/yourusername/spree_marketplace/coverage)

**SpreeMarketplace** is a comprehensive, enterprise-grade multi-vendor marketplace extension for [Spree Commerce](https://spreecommerce.org). Transform your Spree store into a powerful marketplace platform with advanced vendor management, commission tracking, automated payouts, and extensive admin tools.

## 🚀 Key Features

### **Vendor Management**
- **Complete Vendor Onboarding**: Streamlined registration with document verification
- **State Machine Workflow**: Pending → Active → Suspended/Blocked states with proper transitions
- **Business Profile Management**: Tax information, bank details, business verification
- **Team Management**: Role-based vendor user system (Owner, Manager, Staff, Accountant, Viewer)
- **Document Management**: Secure upload and verification of business documents

### **Commission & Payout System**
- **Flexible Commission Rates**: Per-vendor commission rates with platform fee support
- **Automated Commission Calculation**: Real-time calculation on order completion
- **Multiple Payout Schedules**: Weekly, bi-weekly, monthly, quarterly, or manual
- **Payout Tracking**: Complete audit trail with payment references
- **Financial Reporting**: Comprehensive analytics for vendors and admins

### **Admin Interface**
- **Modern Bootstrap 4.6 UI**: Follows exact Spree admin design patterns
- **Turbo Rails Integration**: Fast, modern interactions with Turbo Streams
- **Bulk Operations**: Activate, suspend, or manage multiple vendors at once
- **Advanced Filtering**: Search and filter vendors by status, verification, date ranges
- **Analytics Dashboard**: Revenue tracking, commission reports, vendor performance

### **API Support**
- **Complete REST API**: Full v2 Storefront and Admin API endpoints
- **JSONAPI Serialization**: Fast, cacheable responses with sparse fieldsets
- **Flexible Includes**: Related data loading with performance optimization
- **Authentication Ready**: Integrates with existing Spree authentication

### **Developer Experience**
- **Enterprise Architecture**: Follows Spree patterns and Rails best practices
- **Comprehensive Tests**: 90%+ test coverage with RSpec and FactoryBot
- **Stimulus Controllers**: Modern JavaScript with Hotwire/Turbo
- **Extensible Design**: Clean interfaces for customization and extensions

## 📦 Installation

Add SpreeMarketplace to your Gemfile:

```ruby
gem 'spree_marketplace'
```

Run the installer:

```bash
bundle install
rails generate spree_marketplace:install
rails db:migrate
```

The installer will:
- Add configuration initializer
- Run database migrations
- Load seed data (optional)
- Create sample vendors (optional)

## ⚙️ Configuration

Configure SpreeMarketplace in `config/initializers/spree_marketplace.rb`:

```ruby
SpreeMarketplace.configure do |config|
  # Models that can be associated with vendors
  config.vendorized_models = %w[product variant stock_location shipping_method]
  
  # Commission and fee settings
  config.default_commission_rate = 0.15  # 15%
  config.platform_fee_rate = 0.03        # 3% of commission
  config.minimum_payout_amount = 50.00   # $50 minimum
  
  # Vendor approval settings
  config.auto_approve_vendors = false
  config.require_business_verification = true
  config.require_tax_information = true
  
  # Product management
  config.vendor_products_require_approval = true
  config.allow_vendor_product_deletion = false
  config.max_products_per_vendor = 1000
  
  # File upload settings
  config.max_vendor_logo_size = 5.megabytes
  config.max_document_size = 10.megabytes
  config.allowed_document_types = %w[application/pdf image/jpeg image/png]
end
```

## 🏗️ Architecture Overview

### Database Schema

**Core Tables:**
- `spree_vendors` - Vendor information and state
- `spree_vendor_profiles` - Business details and verification
- `spree_vendor_users` - Team management with roles
- `spree_order_commissions` - Commission tracking per order
- `spree_vendor_payouts` - Payout batches and history

**Model Extensions:**
SpreeMarketplace automatically adds `vendor_id` to configurable models:
- Products, Variants (vendor product catalog)
- Stock Locations (vendor-specific inventory)
- Shipping Methods (vendor shipping options)
- Payment Methods (vendor payment processing)

### State Machine Workflow

```
Vendor States: pending → active ↔ suspended
                     ↓         ↓
                  rejected   blocked
```

**State Transitions:**
- **Pending**: New vendor registrations await approval
- **Active**: Approved vendors can sell products and receive orders
- **Suspended**: Temporarily disabled, can be reactivated
- **Blocked**: Permanently disabled vendor account
- **Rejected**: Application rejected during review

## 🛠️ Usage Examples

### Creating a Vendor

```ruby
vendor = Spree::Vendor.create!(
  name: "Amazing Electronics",
  contact_email: "contact@amazing-electronics.com",
  phone: "+1-555-0123"
)

vendor.build_vendor_profile(
  business_name: "Amazing Electronics LLC",
  business_type: "llc",
  tax_id: "12-3456789",
  commission_rate: 0.15
)

vendor.save!
```

### Managing Vendor State

```ruby
vendor = Spree::Vendor.find_by(name: "Amazing Electronics")

# Activate vendor
vendor.activate!  # pending → active

# Suspend vendor
vendor.suspend!   # active → suspended

# Reactivate suspended vendor
vendor.activate!  # suspended → active
```

### Commission Calculation

```ruby
order = Spree::Order.complete.first
vendor = order.line_items.first.product.vendor

# Create commission record
commission = Spree::OrderCommission.create!(
  order: order,
  vendor: vendor,
  base_amount: order.item_total
)

# Commission automatically calculated:
# commission.commission_amount = base_amount * vendor.commission_rate
# commission.platform_fee = commission_amount * platform_fee_rate  
# commission.vendor_payout = commission_amount - platform_fee
```

### API Usage

**Storefront API - List Active Vendors:**

```bash
curl -X GET "https://yourstore.com/api/v2/storefront/vendors" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Admin API - Bulk Activate Vendors:**

```bash
curl -X POST "https://yourstore.com/api/v2/admin/vendors/bulk_activate" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"vendor_ids": [1, 2, 3]}'
```

## 🎨 Admin Interface

The admin interface provides comprehensive vendor management:

### Vendor Index
- **Advanced Filtering**: Status, verification status, date ranges, business type
- **Bulk Operations**: Activate, suspend, block multiple vendors
- **Quick Actions**: Direct state transitions with confirmation
- **Export Options**: CSV and Excel export with custom field selection

### Vendor Detail View
- **Performance Metrics**: Sales, commission, product counts with charts
- **Verification Status**: Document review and approval workflow  
- **Team Management**: Invite and manage vendor users with role-based permissions
- **Recent Activity**: Latest orders, products, and commission updates

### Vendor Profile Management
- **Document Verification**: Upload and review business documents
- **Business Information**: Tax details, banking information, address
- **Commission Settings**: Flexible rate management with audit trail
- **Payout Schedule**: Configure payment frequency and methods

## 🔧 Customization

### Extending Vendor Model

```ruby
# app/models/spree/vendor_decorator.rb
module Spree::VendorDecorator
  def custom_business_metric
    # Add your custom business logic
    products.sum(:price) * commission_rate
  end
end

Spree::Vendor.prepend(Spree::VendorDecorator)
```

### Custom Admin Actions

```ruby
# app/controllers/spree/admin/vendors_controller_decorator.rb
module Spree::Admin::VendorsControllerDecorator
  def custom_bulk_action
    vendor_ids = params[:vendor_ids] || []
    
    vendor_ids.each do |vendor_id|
      vendor = Spree::Vendor.find(vendor_id)
      # Custom logic here
    end
    
    redirect_to admin_vendors_path
  end
end

Spree::Admin::VendorsController.prepend(Spree::Admin::VendorsControllerDecorator)
```

### Adding Custom Serializer Attributes

```ruby
# app/serializers/spree/v2/storefront/vendor_serializer_decorator.rb
module Spree::V2::Storefront::VendorSerializerDecorator
  def self.prepended(base)
    base.attribute :custom_metric do |vendor|
      vendor.custom_business_metric
    end
  end
end

Spree::V2::Storefront::VendorSerializer.prepend(Spree::V2::Storefront::VendorSerializerDecorator)
```

## 🧪 Testing

Run the test suite:

```bash
# Run all tests
bundle exec rspec

# Run with coverage
COVERAGE=true bundle exec rspec

# Run specific test types
bundle exec rspec spec/models
bundle exec rspec spec/controllers
bundle exec rspec spec/requests
```

### Factory Usage

SpreeMarketplace provides comprehensive factories:

```ruby
# Basic vendor
vendor = create(:vendor)

# Active vendor with products
vendor = create(:vendor, :active, :with_products, products_count: 5)

# Complete vendor for integration tests
vendor = create(:vendor, :complete)

# Vendor with specific traits
vendor = create(:vendor, :verified, :high_commission, :with_orders)
```

## 📊 Performance Considerations

### Database Indexes

SpreeMarketplace includes optimized indexes for:
- Vendor state and priority queries
- Commission calculations and reporting
- Payout processing and batch operations
- Product-vendor associations

### Caching

The gem implements caching at multiple levels:
- **Fragment Caching**: Admin views with automatic cache invalidation
- **Serializer Caching**: API responses with intelligent cache keys
- **Query Optimization**: Includes and preloads to prevent N+1 queries

### Background Jobs

For production deployments, consider moving to background jobs:
- Commission calculations on large orders
- Bulk vendor operations
- Email notifications and document processing
- Payout batch processing

## 🔒 Security

SpreeMarketplace follows security best practices:
- **Authorization**: CanCanCan integration with role-based permissions
- **Data Encryption**: Sensitive vendor data encrypted at rest
- **File Validation**: Document upload restrictions and virus scanning
- **Audit Trails**: Complete activity logging for compliance
- **API Security**: Rate limiting and authentication required

## 🚀 Deployment

### Production Checklist

- [ ] Configure secure file storage (S3, GCS, etc.)
- [ ] Set up background job processing (Sidekiq, Resque)
- [ ] Configure email delivery (SendGrid, SES, etc.)
- [ ] Enable SSL for admin and API endpoints
- [ ] Set up monitoring and error tracking
- [ ] Configure regular database backups
- [ ] Review and set production configuration values

### Environment Variables

```bash
# File Storage
ACTIVE_STORAGE_SERVICE=amazon
AWS_BUCKET=your-marketplace-bucket

# Email Configuration  
SMTP_SERVER=smtp.sendgrid.net
SMTP_USERNAME=apikey
SMTP_PASSWORD=your-sendgrid-key

# Marketplace Configuration
MARKETPLACE_AUTO_APPROVE_VENDORS=false
MARKETPLACE_DEFAULT_COMMISSION_RATE=0.15
MARKETPLACE_REQUIRE_VERIFICATION=true
```

## 📈 Roadmap

### Planned Features

- **Advanced Analytics**: Revenue forecasting, vendor performance scoring
- **Multi-Currency Support**: Per-vendor currency settings and conversions
- **Subscription Plans**: Tiered vendor memberships with feature access
- **Review System**: Vendor ratings and customer feedback management
- **Mobile App Support**: React Native components for vendor management
- **Advanced Shipping**: Per-vendor shipping rules and fulfillment centers

### Integration Opportunities

- **Payment Processors**: Stripe Connect, PayPal Marketplace
- **Accounting Software**: QuickBooks, Xero integration
- **Communication Tools**: Vendor-customer messaging system
- **Inventory Management**: Third-party inventory sync and management

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
git clone https://github.com/yourusername/spree_marketplace.git
cd spree_marketplace
bundle install

# Create test application
bundle exec rake test_app

# Run tests
bundle exec rspec
```

## 📄 License

SpreeMarketplace is released under the [MIT License](LICENSE.md).

## 🆘 Support

- **Documentation**: [Wiki](https://github.com/yourusername/spree_marketplace/wiki)
- **Issues**: [GitHub Issues](https://github.com/yourusername/spree_marketplace/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/spree_marketplace/discussions)
- **Commercial Support**: [Contact Us](mailto:support@yourcompany.com)

---

**Built with ❤️ for the Spree Commerce ecosystem**