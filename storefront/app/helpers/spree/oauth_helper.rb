module Spree
  module OauthHelper
    # Generate Google OAuth login button
    def google_oauth_login_button(options = {})
      return unless oauth_enabled?

      button_class = options[:class] || 'w-full flex justify-center items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500'
      button_text = options[:text] || I18n.t('spree.oauth.sign_in_with_google')

      link_to(
        spree.user_google_oauth2_omniauth_authorize_path,
        method: :post,
        class: button_class,
        data: {
          turbo: false,
          'disable-with': I18n.t('spree.oauth.signing_in')
        }
      ) do
        content_tag(:span, class: 'flex items-center') do
          google_icon_svg +
          content_tag(:span, button_text, class: 'ml-2')
        end
      end
    end

    # Check if OAuth is configured and enabled
    def oauth_enabled?
      defined?(Devise) &&
      Spree.user_class.respond_to?(:omniauth_providers) &&
      Spree.user_class.omniauth_providers&.include?(:google_oauth2) &&
      Rails.application.credentials.google&.client_id.present?
    end

    # Google icon SVG
    def google_icon_svg
      content_tag(:svg,
        viewBox: '0 0 24 24',
        class: 'w-5 h-5',
        fill: 'none',
        xmlns: 'http://www.w3.org/2000/svg'
      ) do
        concat(
          content_tag(:path,
            '',
            d: 'M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z',
            fill: '#4285F4'
          )
        )
        concat(
          content_tag(:path,
            '',
            d: 'M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z',
            fill: '#34A853'
          )
        )
        concat(
          content_tag(:path,
            '',
            d: 'm2.18 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.32-.62z',
            fill: '#FBBC05'
          )
        )
        concat(
          content_tag(:path,
            '',
            d: 'M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z',
            fill: '#EA4335'
          )
        )
      end
    end

    # Alternative text-based Google button for simpler styling
    def google_oauth_text_link(text = nil, options = {})
      return unless oauth_enabled?

      text ||= I18n.t('spree.oauth.sign_in_with_google')
      css_classes = options[:class] || 'text-blue-600 hover:text-blue-800 underline'

      link_to(
        text,
        spree.user_google_oauth2_omniauth_authorize_path,
        method: :post,
        class: css_classes,
        data: {
          turbo: false,
          'disable-with': I18n.t('spree.oauth.signing_in')
        }
      )
    end
  end
end