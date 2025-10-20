module Spree
  module OauthHelper
    # Generate Google OAuth login button with popup functionality
    def google_oauth_login_button(options = {})
      return unless oauth_enabled?

      begin
        button_text = options[:text] || 'Sign in with Google'
        button_class = options[:class] || 'w-full bg-white hover:bg-gray-50 border border-gray-300 rounded-lg px-6 py-3 text-sm font-medium text-gray-800 shadow-sm transition-all duration-200 ease-in-out flex items-center justify-center space-x-3 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2'
        use_popup = options.fetch(:popup, false) # Disable popup for testing

        # Use Devise OmniAuth path
        oauth_path = user_google_oauth2_omniauth_authorize_path

        if use_popup
          # Popup version
          content_tag(:button,
            class: button_class,
            type: 'button',
            onclick: "openGoogleOAuthPopup('#{oauth_path}')",
            data: { 'disable-with': 'Signing in...' }
          ) do
            google_icon_svg.html_safe +
            content_tag(:span, button_text, class: 'font-medium')
          end
        else
          # Standard form version - use POST method with Turbo disabled
          form_with(
            url: oauth_path,
            method: :post,
            local: true,
            class: 'w-full',
            data: {
              turbo: false,
              'disable-with': 'Signing in...'
            },
            authenticity_token: true
          ) do |f|
            f.button(
              type: 'submit',
              class: button_class,
              data: { turbo: false }
            ) do
              google_icon_svg.html_safe +
              content_tag(:span, button_text, class: 'font-medium')
            end
          end
        end
      rescue => e
        # Fallback button for debugging
        content_tag(:div, class: 'p-4 bg-yellow-100 border rounded') do
          "OAuth Button Error: #{e.message}"
        end
      end
    end

    # Check if OAuth is configured and enabled
    def oauth_enabled?
      defined?(Devise) &&
      Spree.user_class.respond_to?(:omniauth_providers) &&
      Spree.user_class.omniauth_providers&.include?(:google_oauth2) &&
      (Rails.application.credentials.google&.client_id.present? || ENV['GOOGLE_OAUTH_CLIENT_ID'].present?)
    end

    # Authentic Google "G" icon SVG
    def google_icon_svg
      content_tag(:svg,
        viewBox: '0 0 24 24',
        class: 'w-5 h-5 flex-shrink-0',
        xmlns: 'http://www.w3.org/2000/svg'
      ) do
        # Google's official "G" logo paths
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

    # Compact Google OAuth button
    def google_oauth_compact_button(options = {})
      return unless oauth_enabled?

      use_popup = options.fetch(:popup, true)
      button_class = 'bg-white hover:bg-gray-50 border border-gray-300 rounded-lg px-4 py-2 text-sm font-medium text-gray-800 shadow-sm transition-all duration-200 ease-in-out flex items-center space-x-2 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2'

      if use_popup
        content_tag(:button,
          class: button_class,
          type: 'button',
          onclick: "openGoogleOAuthPopup('#{spree.user_google_oauth2_omniauth_authorize_path}')",
          data: { 'disable-with': 'Signing in...' }
        ) do
          google_icon_svg.html_safe +
          content_tag(:span, 'Google', class: 'font-medium')
        end
      else
        form_with(
          url: spree.user_google_oauth2_omniauth_authorize_path,
          method: :post,
          local: true,
          class: 'inline-block'
        ) do |f|
          f.button(
            type: 'submit',
            class: button_class,
            data: { 'disable-with': 'Signing in...' }
          ) do
            google_icon_svg.html_safe +
            content_tag(:span, 'Google', class: 'font-medium')
          end
        end
      end
    end

    # JavaScript for popup OAuth window
    def google_oauth_popup_script
      content_tag(:script, type: 'text/javascript') do
        raw <<~JAVASCRIPT
          function openGoogleOAuthPopup(authUrl) {
            const popup = window.open(
              authUrl,
              'google-oauth',
              'width=500,height=600,scrollbars=yes,resizable=yes'
            );

            // Poll for popup closure
            const pollTimer = window.setInterval(function() {
              if (popup.closed !== false) {
                window.clearInterval(pollTimer);
                // Reload the page to reflect authentication state
                window.location.reload();
              }
            }, 200);
          }

          // Handle OAuth callback in popup
          if (window.opener && window.name === 'google-oauth') {
            // This runs in the popup window after successful OAuth
            window.opener.location.reload();
            window.close();
          }
        JAVASCRIPT
      end
    end
  end
end