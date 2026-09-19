Rails.application.routes.draw do
  # One lead is one project. Everything about a company -- its scans, its gaps
  # and its demo -- lives under that lead, so there is one place to go and
  # nothing to navigate between.
  root "leads#index"

  resources :leads, only: %i[index create show] do
    member do
      get :status
      post :rescan
      # Both act on the lead's latest scan, which is the only one the page ever
      # shows. Naming a scan id here would let a stale tab stop or delete
      # something the person is no longer looking at.
      post :stop
      delete :scan, action: :destroy_scan
    end
  end

  resources :findings, only: %i[show]

  # A salesperson answering a question their own website could not.
  resources :handoffs, only: %i[update]

  # The public, shareable demo. Deliberately short and unguessable.
  get "d/:slug", to: "public_demos#show", as: :public_demo
  post "d/:slug/messages", to: "public_demos#create", as: :public_demo_messages
  post "d/:slug/handoffs", to: "public_demos#handoff", as: :public_demo_handoffs
  get "d/:slug/widget.js", to: "public_demos#widget", as: :public_demo_widget, defaults: { format: :js }

  get "up" => "rails/health#show", as: :rails_health_check

  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, request| "#{request.protocol}localhost:#{request.port}/#{params[:path]}" }
  end
end
