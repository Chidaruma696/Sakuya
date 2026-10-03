# Claves de permiso. Un rol tiene una lista de claves; "*" lo permite todo y "caja.*" todo un módulo.
module Permiso
  CLAVES = {
    "caja.vender" => "Vender en caja",
    "caja.abrir" => "Abrir y cerrar caja",
    "caja.retirar" => "Retirar efectivo a caja fuerte",
    "caja.diferencia" => "Cerrar el corte con una diferencia mayor al tope",
    "caja.bajar_precio" => "Autorizar un precio por debajo del catálogo",
    "caja.forzar_venta" => "Cobrar una venta que la regla de ventas frena (queda por revisar)",
    "caja.devolver" => "Recibir devoluciones de clientes",
    "inventario.ver" => "Ver existencias y movimientos",
    "inventario.ajustar" => "Ajustar existencias con justificación",
    "conteos.hacer" => "Hacer conteos físicos y cargar faltantes",
    "conteos.cargos" => "Cobrar o perdonar cargos",
    "reportes.ver" => "Ver el tablero y los reportes",
    "revisiones.resolver" => "Revisar lo que se hizo sin autorización (aprobar, observar, cargar)",
    "clientes.ver" => "Ver clientes",
    "clientes.editar" => "Dar de alta y editar clientes",
    "clientes.pedidos" => "Tomar y cancelar pedidos de clientes",
    "clientes.abonar" => "Recibir abonos de clientes en la caja",
    "clientes.forzar_credito" => "Vender a cuenta aunque la regla de crédito lo frene (queda por revisar)",
    "compras.ver" => "Ver proveedores y cuentas por pagar",
    "compras.recibir" => "Recibir mercancía del proveedor",
    "compras.facturar" => "Capturar y cancelar facturas del proveedor",
    "compras.pagar" => "Pagar a proveedores desde la caja",
    "compras.forzar_recepcion" => "Recibir mercancía que la regla de recepciones frena (queda por revisar)",
    "compras.exceder" => "Registrar una factura con más de lo recibido (con motivo, queda por revisar)",
    "almacenes.traspasar" => "Traspasos a granel entre sucursales y almacenes",
    "admin.catalogo" => "Administrar productos y códigos",
    "admin.usuarios" => "Administrar usuarios, roles y sucursales",
    "reglas.editar" => "Escribir los programas en Lisp del negocio (el tablero)"
  }.freeze

  MODULOS = CLAVES.keys.map { |c| c.split(".").first }.uniq.freeze

  # Nombre para mostrar, en el idioma del usuario (permisos.* en config/locales).
  def self.nombre(clave)
    # La clave lleva punto, así que no se puede pedir "permisos.caja.vender" (I18n lo anidaría).
    I18n.t("permisos", default: {})[clave.to_sym] || CLAVES[clave]
  end

  def self.valida?(clave)
    clave == "*" || CLAVES.key?(clave) || (clave.end_with?(".*") && MODULOS.include?(clave.delete_suffix(".*")))
  end

  # ¿La lista de claves de un rol cubre esta clave?
  def self.cubre?(permisos, clave)
    return false unless CLAVES.key?(clave)
    modulo = clave.split(".").first
    permisos.include?("*") || permisos.include?(clave) || permisos.include?("#{modulo}.*")
  end
end
