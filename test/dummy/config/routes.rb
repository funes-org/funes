Rails.application.routes.draw do
  mount Funes::Engine => "/funes"

  namespace :examples do
    resources :deposit_snapshots, only: :show
  end
end
