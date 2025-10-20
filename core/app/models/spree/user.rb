class Spree::User < Spree.base_class
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  include Spree::UserAddress
  include Spree::UserMethods
  include Spree::UserPaymentSource

  validates :email, presence: true, uniqueness: { scope: spree_base_uniqueness_scope }

  before_validation :set_login

  private

  def set_login
    self.login ||= email if respond_to?(:login=)
  end
end