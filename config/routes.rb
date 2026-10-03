Rails.application.routes.draw do
  root "inicio#index"
  get "ventas-por-producto", to: "inicio#ventas", as: :ventas_por_producto
  scope "ajustes", controller: "ajustes", as: "ajustes" do
    get "/", action: :index
    patch "preferencias", action: :preferencias, as: :preferencias
    patch "sistema", action: :sistema, as: :sistema
    patch "ticket", action: :guardar_ticket, as: :ticket
    get ":seccion", action: :index, as: :seccion, constraints: { seccion: /para_ti|negocio|folios|modulos|caja|compras|ticket/ }
  end
  # Opciones avanzadas de Ajustes. El tablero de Inicio, escrito en Lisp: editar, probar sin
  # guardar, guardar y volver a una versión.
  scope "ajustes/avanzado/tablero", controller: "tablero", as: "tablero" do
    get "editar", action: :edit, as: :editar
    post "/", action: :guardar, as: :guardar
    post "versiones/:id/restaurar", action: :restaurar, as: :restaurar
  end
  # El REPL de solo lectura: preguntarle cosas a los datos en vivo.
  get "ajustes/avanzado/repl", to: "repl#show", as: :repl
  post "ajustes/avanzado/repl", to: "repl#evaluar", as: :repl_evaluar
  # Todas las reglas del negocio en un archivo .lisp: bajarlo y subirlo.
  scope "ajustes/avanzado/archivo", controller: "archivo_reglas" do
    get "/", action: :show, as: :archivo_reglas
    get "exportar", action: :exportar, as: :exportar_reglas
    post "importar", action: :importar, as: :importar_reglas
  end
  # Las reglas que deciden (el cierre de caja, el precio…), con un editor común.
  scope "ajustes/avanzado/reglas/:gancho", controller: "reglas", as: "regla", constraints: { gancho: /corte|precio|venta|credito|retiro|movimiento|recepcion|factura/ } do
    get "editar", action: :edit, as: :editar
    post "/", action: :guardar, as: :guardar
    post "versiones/:id/restaurar", action: :restaurar, as: :restaurar
  end
  resources :revisiones, only: %i[index] do
    member { post :resolver }
  end

  get "instalar", to: "instalacion#new", as: :instalar
  post "instalar", to: "instalacion#create"
  get "entrar", to: "sesiones#new", as: :entrar
  post "entrar", to: "sesiones#create"
  delete "salir", to: "sesiones#destroy", as: :salir

  scope "caja", controller: "caja", as: "caja" do
    get "/", action: :index
    get "escanear", action: :escanear
    post "cobrar", action: :cobrar
    get "ventas", action: :ventas
    get "ventas/:id/ticket", action: :ticket, as: :ticket
    get "corte", action: :corte
    post "corte/abrir", action: :abrir, as: :abrir
    post "corte/cerrar", action: :cerrar, as: :cerrar
    post "corte/retirar", action: :retirar, as: :retirar
    get "corte/:id/resumen", action: :resumen, as: :resumen
    get "devolucion", action: :devolucion
    post "devolucion", action: :devolver, as: :devolver
  end

  get "inventario", to: "inventario#index", as: :inventario
  get "productos/buscar", to: "inventario#buscar", as: :buscar_productos
  resources :traspasos, only: %i[index new create show] do
    member { post :cancelar }
  end
  get "inventario/kardex", to: "inventario#kardex", as: :kardex_inventario
  get "inventario/movimiento/nuevo", to: "inventario#nuevo_movimiento", as: :nuevo_movimiento_inventario
  post "inventario/movimiento", to: "inventario#crear_movimiento", as: :movimientos_inventario

  # Clientes: el catálogo; su cuenta y sus pedidos cuelgan de aquí
  resources :clientes, only: %i[index new create edit update] do
    member do
      get :cuenta
      post :abonar
    end
  end
  resources :pedidos, only: %i[index new create show] do
    member { post :cancelar }
  end

  # Compras: proveedores, recepción, facturas y cuentas por pagar
  resources :proveedores, except: %i[show destroy]
  resources :recepciones, only: %i[index new create show] do
    member { post :cancelar; patch :factura }
  end
  resources :facturas, controller: "facturas_proveedor", only: %i[index new create show] do
    member { post :cancelar }
  end
  get "cuentas", to: "cuentas#index", as: :cuentas
  get "cuentas/:id", to: "cuentas#show", as: :cuenta
  post "cuentas/:id/pagar", to: "cuentas#pagar", as: :pagar_cuenta
  post "pagos/:id/anular", to: "cuentas#anular_pago", as: :anular_pago
  resources :conteos, only: %i[index new create show] do
    member do
      post :escanear
      post :manual
      post :cerrar
    end
  end
  resources :cargos, only: %i[index] do
    member { post :resolver }
  end

  namespace :admin do
    resources :productos, except: %i[show destroy] do
      resources :codigos, only: %i[create destroy], controller: "codigos_barras"
    end
    resources :promociones, except: %i[show]
    resources :usuarios, except: %i[show destroy]
    resources :roles, except: %i[show destroy]
    resources :sucursales, except: %i[show destroy]
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # PWA: manifiesto y service worker (app/views/pwa)
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
