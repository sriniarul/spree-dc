Spree::Core::Engine.add_routes do
  namespace :admin do
    resources :social_media, only: [:index] do
      collection do
        get :analytics
        get :campaigns
      end
    end

    # Product-specific social media posting
    resources :products, only: [] do
      member do
        get 'social_media/post', to: 'social_media/product_posts#new', as: :post_to_social_media
        post 'social_media/post', to: 'social_media/product_posts#create'
      end
    end

    namespace :social_media do
      resources :accounts do
        member do
          post :sync_analytics
          post :test_connection
          delete :disconnect
        end
      end

      # Product posting routes
      resources :product_posts, only: [] do
        collection do
          get :bulk_new
          post :bulk_create
        end
      end

      # Content publishing routes
      resources :content, only: [:index, :show] do
        collection do
          get :new_post
          post :create_post
          post :validate_post
          get :schedule_dashboard
          post :bulk_schedule
          get :get_optimal_times
        end
        member do
          post :publish_post
          post :reschedule_post
          delete :delete_post
          delete :cancel_schedule
        end
      end

      resources :posts do
        member do
          post :schedule
          post :post_now
          post :cancel
          get :preview
        end

        collection do
          get :bulk_actions
          post :bulk_schedule
          post :bulk_cancel
        end
      end

      resources :campaigns do
        resources :posts, controller: 'campaign_posts'
        member do
          post :activate
          post :pause
          post :schedule_all
        end
      end

      resources :analytics, only: [:index, :show] do
        collection do
          get :dashboard
          get :export
          get :chart_data
          get :top_posts
          get :hashtag_analysis
        end
        member do
          post :sync_account_analytics
        end
      end

      resources :hashtags, only: [:index] do
        collection do
          get :search
          get :suggestions
          get :strategy
          get :performance_report
          get :trending_analysis
          post :validate_hashtags
          post :save_hashtag_set
          get :load_hashtag_sets
          get :auto_suggest
        end
        member do
          get :insights
        end
      end

      resources :templates do
        collection do
          get :library
          post :import_from_library
          post :bulk_actions
          get :export
          post :validate_template
          post :create_from_post
        end
        member do
          post :duplicate
          get :preview
          get :analytics
        end
      end

      resources :stories_and_reels, only: [:index] do
        collection do
          get :new_story
          post :create_story
          get :new_reel
          post :create_reel
          post :validate_story_media
          post :validate_reel_video
          get :preview_story
          get :preview_reel
          get :trending_audio
          get :search_audio
          get :analytics
          get :export_analytics
          post :bulk_actions
        end
      end

      # Platform-specific setup routes
      resources :facebook_setup, only: [:new, :create, :show]
      resources :instagram_setup, only: [:new, :create, :show]
      resources :whatsapp_setup, only: [:new, :create, :show]
      resources :youtube_setup, only: [:new, :create, :show]
      resources :tiktok_setup, only: [:new, :create, :show]
    end
  end

  # OAuth initiation routes
  get '/auth/instagram', to: 'social_media/oauth_initiation#instagram'
  get '/auth/facebook', to: 'social_media/oauth_initiation#facebook'
  get '/auth/google_oauth2', to: 'social_media/oauth_initiation#google'
  get '/auth/tiktok', to: 'social_media/oauth_initiation#tiktok'
  get '/auth/twitter', to: 'social_media/oauth_initiation#twitter'

  # OAuth callback routes
  # Instagram uses custom callback (not OmniAuth)
  get '/social_media/oauth/instagram/callback', to: 'social_media/oauth/instagram#callback'

  # Legacy OAuth callbacks (Facebook, Google, etc via OmniAuth)
  get '/auth/:provider/callback', to: 'social_media/oauth_callbacks#create'
  get '/auth/failure', to: 'social_media/oauth_callbacks#failure'

  # Webhook routes for social media platforms
  namespace :social_media do
    namespace :webhooks do
      post :facebook
      post :instagram
      post :youtube
      post :tiktok
      post :whatsapp
    end
  end

  # API routes for social media integration
  namespace :api, defaults: { format: :json } do
    namespace :v2 do
      namespace :storefront do
        resources :social_media_posts, only: [:index, :show] do
          member do
            get :analytics
          end
        end
      end

      namespace :platform do
        namespace :social_media do
          resources :accounts, only: [:index, :show, :create, :update, :destroy]
          resources :posts, only: [:index, :show, :create, :update, :destroy] do
            member do
              post :schedule
              post :post_now
            end
          end
          resources :analytics, only: [:index, :show]
        end
      end
    end
  end
end