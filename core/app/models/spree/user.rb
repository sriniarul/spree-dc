class Spree::User < Spree.base_class
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  include Spree::UserAddress
  include Spree::UserMethods
  include Spree::UserPaymentSource
  include Spree::UserOauth

  validates :email, presence: true, uniqueness: { scope: spree_base_uniqueness_scope }

  before_validation :set_login

  # OAuth class method for Google authentication
  def self.from_omniauth(auth)
    # First try to find user by provider and uid
    user = find_by(provider: auth.provider, uid: auth.uid)

    if user.present?
      # Update user info from OAuth if found
      user.update(
        first_name: auth.info.first_name,
        last_name: auth.info.last_name,
        image_url: auth.info.image
      )
      return user
    end

    # Try to find existing user by email
    email = auth.info.email
    user = find_by(email: email) if email.present?

    if user.present?
      # Link OAuth account to existing user
      user.update(
        provider: auth.provider,
        uid: auth.uid,
        first_name: auth.info.first_name || user.first_name,
        last_name: auth.info.last_name || user.last_name,
        image_url: auth.info.image
      )
      return user
    end

    # Create new user from OAuth data
    if email.present?
      user = create(
        email: email,
        provider: auth.provider,
        uid: auth.uid,
        first_name: auth.info.first_name,
        last_name: auth.info.last_name,
        image_url: auth.info.image,
        password: SecureRandom.hex(16) # Generate secure random password
      )
      return user
    end

    nil
  end

  private

  def set_login
    self.login ||= email if respond_to?(:login=)
  end
end