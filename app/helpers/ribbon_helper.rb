# La cinta tipo Office: pestañas por módulo y, debajo, botones grandes con las acciones.
# Cada botón lleva su clave de texto (cinta.botones.*), el permiso que hace falta y el nombre de
# su icono (Bootstrap Icons); una pestaña se ve si alguno de sus botones se ve.
module RibbonHelper
  Boton = Struct.new(:clave, :ruta, :permiso, :icono)

  PESTANAS = [
    { id: :inicio, grupos: [
      { id: :ver, botones: [
        Boton.new(:inicio, :root_path, nil, "house"),
        Boton.new(:ventas_por_producto, :ventas_por_producto_path, "reportes.ver", "graph-up")
      ] },
      { id: :revisar, botones: [ Boton.new(:por_revisar, :revisiones_path, "revisiones.resolver", "clipboard-check") ] },
      { id: :ajustes, botones: [ Boton.new(:ajustes, :ajustes_path, nil, "gear") ] }
    ] },
    { id: :caja, grupos: [
      { id: :vender, botones: [
        Boton.new(:vender, :caja_path, "caja.vender", "cart3"),
        Boton.new(:ventas, :caja_ventas_path, "caja.vender", "receipt"),
        Boton.new(:devolucion, :caja_devolucion_path, "caja.devolver", "arrow-return-left")
      ] },
      { id: :corte, botones: [ Boton.new(:corte, :caja_corte_path, "caja.abrir", "cash-stack") ] }
    ] },
    { id: :inventario, grupos: [
      { id: :consultar, botones: [
        Boton.new(:existencias, :inventario_path, "inventario.ver", "list"),
        Boton.new(:kardex, :kardex_inventario_path, "inventario.ver", "arrow-down-up")
      ] },
      { id: :capturar, botones: [
        Boton.new(:entrada_ajuste, :nuevo_movimiento_inventario_path, "inventario.ajustar", "pencil")
      ] }
    ] },
    { id: :compras, grupos: [
      { id: :recibir, botones: [
        Boton.new(:recibir, :new_recepcion_path, "compras.recibir", "box-arrow-in-down"),
        Boton.new(:recepciones, :recepciones_path, "compras.ver", "list-ul")
      ] },
      { id: :facturas, botones: [
        Boton.new(:nueva_factura, :new_factura_path, "compras.facturar", "file-earmark-plus"),
        Boton.new(:cuentas_por_pagar, :cuentas_path, "compras.ver", "wallet2")
      ] },
      { id: :proveedores, botones: [ Boton.new(:proveedores, :proveedores_path, "compras.ver", "truck") ] }
    ] },
    { id: :clientes, grupos: [
      { id: :clientes, botones: [
        Boton.new(:clientes, :clientes_path, "clientes.ver", "people"),
        Boton.new(:nuevo_cliente, :new_cliente_path, "clientes.editar", "person-plus")
      ] },
      { id: :pedidos, botones: [
        Boton.new(:nuevo_pedido, :new_pedido_path, "clientes.pedidos", "journal-plus"),
        Boton.new(:pedidos, :pedidos_path, "clientes.ver", "journal-text")
      ] }
    ] },
    { id: :almacenes, grupos: [
      { id: :granel, botones: [
        Boton.new(:traspaso_granel, :new_traspaso_path, "almacenes.traspasar", "boxes"),
        Boton.new(:traspasos, :traspasos_path, "almacenes.traspasar", "list-ul")
      ] },
      { id: :reabasto, botones: [ Boton.new(:reabastecer, :reabasto_path, "almacenes.traspasar", "arrow-repeat") ] }
    ] },
    { id: :conteos, grupos: [
      { id: :contar, botones: [
        Boton.new(:nuevo_conteo, :new_conteo_path, "conteos.hacer", "search"),
        Boton.new(:conteos, :conteos_path, "conteos.hacer", "list-ul")
      ] },
      { id: :cargos, botones: [ Boton.new(:cargos, :cargos_path, "conteos.cargos", "cash-coin") ] }
    ] },
    { id: :admin, grupos: [
      { id: :catalogo, botones: [
        Boton.new(:productos, :admin_productos_path, "admin.catalogo", "box-seam"),
        Boton.new(:promociones, :admin_promociones_path, "admin.catalogo", "percent")
      ] },
      { id: :gente, botones: [
        Boton.new(:usuarios, :admin_usuarios_path, "admin.usuarios", "person"),
        Boton.new(:roles, :admin_roles_path, "admin.usuarios", "key"),
        Boton.new(:sucursales, :admin_sucursales_path, "admin.usuarios", "shop")
      ] }
    ] }
  ].freeze

  def boton_visible?(boton)
    boton.permiso.nil? || puede?(boton.permiso)
  end

  # Un grupo puede colgar de uno o varios módulos.
  def grupo_visible?(grupo)
    Array(grupo[:modulo]).all? { |m| Modulo.activo?(m) } && grupo[:botones].any? { |b| boton_visible?(b) }
  end

  # Una pestaña se ve si su módulo está encendido y alguno de sus grupos se ve.
  def pestanas_visibles
    PESTANAS.select do |p|
      # En un almacén no hay caja ni conteos: la mercancía solo se guarda.
      next false if %i[caja conteos].include?(p[:id]) && sucursal_actual&.almacen?
      Modulo.activo?(p[:id]) && p[:grupos].any? { |g| grupo_visible?(g) }
    end
  end

  # Ajustes cuelga de Inicio en la cinta, pero es su propia pestaña activa: cae en Inicio.
  def pestana_activa
    PESTANAS.find { |p| p[:id] == controller.pestana_ribbon } || PESTANAS.first
  end

  def ruta_de_pestana(pestana)
    boton = pestana[:grupos].select { |g| grupo_visible?(g) }.flat_map { |g| g[:botones] }.find { |b| boton_visible?(b) }
    boton ? send(boton.ruta) : root_path
  end
end
