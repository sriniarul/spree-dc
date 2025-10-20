class Spree::User < Spree.base_class
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :omniauthable,
         omniauth_providers: [:google_oauth2]

  include Spree::UserAddress
  include Spree::UserMethods
  include Spree::UserPaymentSource
  include Spree::UserOauth if defined?(Spree::UserOauth)

  validates :email, presence: true, uniqueness: { scope: spree_base_uniqueness_scope }

  before_validation :set_login

  def self.from_omniauth(auth)
    where(email: auth.info.email).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.login = auth.info.email
    end
  end

  private

  def set_login
    self.login ||= email if respond_to?(:login=)
  end
end