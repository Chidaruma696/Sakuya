Rails.application.routes.draw do
  root "home#index"
  get "sales-by-product", to: "home#sales", as: :sales_by_product
  scope "settings", controller: "settings", as: "settings" do
    get "/", action: :index
    patch "preferences", action: :preferences, as: :preferences
    patch "system", action: :system, as: :system
    patch "ticket", action: :save_ticket, as: :ticket
    get ":section", action: :index, as: :section, constraints: { section: /for_you|business|folios|features|till|purchases|ticket/ }
  end
  # Advanced settings. The Home dashboard, written in Lisp: edit, try without saving, save and go
  # back to a version.
  scope "settings/advanced/dashboard", controller: "dashboard", as: "dashboard" do
    get "edit", action: :edit, as: :edit
    post "/", action: :save, as: :save
    post "versions/:id/restore", action: :restore, as: :restore
  end
  # Lisp plugins: functions for the rules, reports for the REPL and translations.
  resources :plugins, only: %i[index create destroy], path: "settings/advanced/plugins" do
    member { post :toggle }
  end
  # The read-only REPL: asking the live data questions.
  get "settings/advanced/repl", to: "repl#show", as: :repl
  post "settings/advanced/repl", to: "repl#evaluate", as: :repl_evaluate
  get "settings/advanced/repl/log", to: "repl#log", as: :repl_log
  # All the business's rules in one .lisp file: download it and upload it.
  scope "settings/advanced/file", controller: "rules_file" do
    get "/", action: :show, as: :rules_file
    get "export", action: :export, as: :export_rules
    post "import", action: :import, as: :import_rules
  end
  # The rules that decide (closing the till, the price…), with a shared editor.
  scope "settings/advanced/rules/:hook", controller: "rules", as: "rule", constraints: { hook: /shift|price|sale|credit|withdrawal|movement|receipt|invoice/ } do
    get "edit", action: :edit, as: :edit
    post "/", action: :save, as: :save
    post "versions/:id/restore", action: :restore, as: :restore
  end
  resources :reviews, only: %i[index] do
    member { post :resolve }
  end

  get "install", to: "setup#new", as: :install
  post "install", to: "setup#create"
  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  scope "till", controller: "till", as: "till" do
    get "/", action: :index
    get "scan", action: :scan
    post "checkout", action: :checkout
    get "sales", action: :sales
    get "sales/:id/ticket", action: :ticket, as: :ticket
    get "sales/:id/escpos", action: :escpos, as: :escpos
    get "catalog", action: :catalog, as: :catalog
    get "token", action: :token, as: :token
    post "sales/:id/print", action: :print, as: :print
    get "shift", action: :shift
    post "shift/open", action: :open, as: :open
    post "shift/close", action: :close, as: :close
    post "shift/withdraw", action: :withdraw, as: :withdraw
    get "shift/:id/summary", action: :summary, as: :summary
    get "shift/:id/escpos", action: :summary_escpos, as: :summary_escpos
    post "shift/:id/print", action: :summary_print, as: :summary_print
    get "refund", action: :refund
    post "refund", action: :create_refund, as: :create_refund
  end

  get "inventory", to: "inventory#index", as: :inventory
  get "products/search", to: "inventory#search", as: :search_products
  get "restock", to: "restock#index", as: :restock
  get "restock/:branch_id/minimums", to: "restock#minimums", as: :restock_minimums
  patch "restock/:branch_id/minimums", to: "restock#save_minimums"
  resources :stock_transfers, only: %i[index new create show] do
    member { post :cancel }
  end
  get "inventory/kardex", to: "inventory#kardex", as: :kardex_inventory
  get "inventory/movement/new", to: "inventory#new_movement", as: :new_movement_inventory
  post "inventory/movement", to: "inventory#create_movement", as: :movements_inventory

  # Customers: the catalog; their account and orders hang off it
  resources :customers, only: %i[index new create edit update] do
    member do
      get :account
      post :pay_account
    end
  end
  resources :orders, only: %i[index new create show] do
    member { post :cancel }
  end

  # Purchases: suppliers, receipts, invoices and accounts payable
  resources :suppliers, except: %i[show destroy]
  resources :receipts, only: %i[index new create show] do
    member { post :cancel; patch :invoice }
  end
  resources :invoices, controller: "supplier_invoices", only: %i[index new create show] do
    member { post :cancel }
  end
  get "accounts", to: "accounts#index", as: :accounts
  get "accounts/:id", to: "accounts#show", as: :account
  post "accounts/:id/pay", to: "accounts#pay", as: :pay_account
  post "payments/:id/void", to: "accounts#void_payment", as: :void_payment
  resources :stock_counts, only: %i[index new create show] do
    member do
      post :scan
      post :manual
      post :close
    end
  end
  resources :charges, only: %i[index] do
    member { post :resolve }
  end

  namespace :admin do
    resources :products, except: %i[show destroy] do
      resources :codes, only: %i[create destroy], controller: "product_barcodes"
    end
    resources :promotions, except: %i[show]
    resources :users, except: %i[show destroy]
    resources :roles, except: %i[show destroy]
    resources :branches, except: %i[show destroy]
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # PWA: manifest and service worker (app/views/pwa)
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
