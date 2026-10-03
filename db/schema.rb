# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_03_000002) do
  create_table "ajustes", force: :cascade do |t|
    t.string "clave", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "valor"
    t.index ["clave"], name: "index_ajustes_on_clave", unique: true
  end

  create_table "cargos", force: :cascade do |t|
    t.integer "conteo_id"
    t.datetime "created_at", null: false
    t.text "detalle"
    t.string "estado", default: "pendiente", null: false
    t.integer "monto_centavos", null: false
    t.datetime "resuelto_en"
    t.integer "resuelto_por_id"
    t.integer "revision_id"
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["conteo_id"], name: "index_cargos_on_conteo_id"
    t.index ["resuelto_por_id"], name: "index_cargos_on_resuelto_por_id"
    t.index ["revision_id"], name: "index_cargos_on_revision_id"
    t.index ["sucursal_id"], name: "index_cargos_on_sucursal_id"
    t.index ["usuario_id"], name: "index_cargos_on_usuario_id"
    t.check_constraint "estado IN ('pendiente', 'cobrado', 'perdonado')", name: "cargos_estado"
    t.check_constraint "monto_centavos > 0", name: "cargos_monto"
  end

  create_table "codigos_barras", force: :cascade do |t|
    t.string "codigo", null: false
    t.datetime "created_at", null: false
    t.integer "producto_id", null: false
    t.datetime "updated_at", null: false
    t.index ["codigo"], name: "index_codigos_barras_on_codigo", unique: true
    t.index ["producto_id"], name: "index_codigos_barras_on_producto_id"
  end

  create_table "contadores", force: :cascade do |t|
    t.string "clave", null: false
    t.datetime "created_at", null: false
    t.integer "ultimo", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["clave"], name: "index_contadores_on_clave", unique: true
  end

  create_table "conteo_lineas", force: :cascade do |t|
    t.integer "conteo_id", null: false
    t.datetime "created_at", null: false
    t.decimal "diferencia", precision: 12, scale: 3
    t.integer "diferencia_centavos"
    t.decimal "escaneado", precision: 12, scale: 3, default: "0.0", null: false
    t.decimal "manual", precision: 12, scale: 3, default: "0.0", null: false
    t.integer "producto_id", null: false
    t.decimal "sistema", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["conteo_id", "producto_id"], name: "index_conteo_lineas_on_conteo_id_and_producto_id", unique: true
    t.index ["conteo_id"], name: "index_conteo_lineas_on_conteo_id"
    t.index ["producto_id"], name: "index_conteo_lineas_on_producto_id"
  end

  create_table "conteos", force: :cascade do |t|
    t.string "alcance", default: "total", null: false
    t.datetime "cerrado_en"
    t.datetime "created_at", null: false
    t.string "estado", default: "abierto", null: false
    t.integer "faltante_centavos"
    t.string "folio", null: false
    t.text "notas"
    t.integer "responsable_id", null: false
    t.integer "sobrante_centavos"
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["responsable_id"], name: "index_conteos_on_responsable_id"
    t.index ["sucursal_id", "estado"], name: "index_conteos_on_sucursal_id_and_estado"
    t.index ["sucursal_id", "folio"], name: "index_conteos_on_sucursal_y_folio", unique: true
    t.index ["sucursal_id"], name: "index_conteos_on_sucursal_id"
    t.index ["usuario_id"], name: "index_conteos_on_usuario_id"
    t.check_constraint "estado IN ('abierto', 'cerrado')", name: "conteos_estado"
  end

  create_table "cortes", force: :cascade do |t|
    t.datetime "abierto_en", null: false
    t.datetime "cerrado_en"
    t.integer "cerrado_por_id"
    t.integer "contado_centavos"
    t.datetime "created_at", null: false
    t.text "desglose"
    t.integer "diferencia_centavos"
    t.integer "esperado_centavos"
    t.string "estado", default: "abierto", null: false
    t.string "folio", null: false
    t.integer "fondo_centavos", default: 0, null: false
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["cerrado_por_id"], name: "index_cortes_on_cerrado_por_id"
    t.index ["sucursal_id", "estado"], name: "index_cortes_on_sucursal_id_and_estado"
    t.index ["sucursal_id", "folio"], name: "index_cortes_on_sucursal_y_folio", unique: true
    t.index ["sucursal_id"], name: "index_cortes_on_sucursal_id"
    t.index ["usuario_id"], name: "index_cortes_on_usuario_id"
    t.check_constraint "estado IN ('abierto', 'cerrado')", name: "cortes_estado"
    t.check_constraint "fondo_centavos >= 0", name: "cortes_fondo"
  end

  create_table "devolucion_lineas", force: :cascade do |t|
    t.decimal "cantidad", precision: 12, scale: 3, null: false
    t.datetime "created_at", null: false
    t.integer "devolucion_id", null: false
    t.integer "importe_centavos", null: false
    t.datetime "updated_at", null: false
    t.integer "venta_linea_id", null: false
    t.index ["devolucion_id"], name: "index_devolucion_lineas_on_devolucion_id"
    t.index ["venta_linea_id"], name: "index_devolucion_lineas_on_venta_linea_id"
    t.check_constraint "cantidad > 0", name: "devolucion_lineas_cantidad"
  end

  create_table "devoluciones", force: :cascade do |t|
    t.integer "corte_id"
    t.datetime "created_at", null: false
    t.string "folio", null: false
    t.string "motivo", null: false
    t.integer "sucursal_id", null: false
    t.integer "total_centavos", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.integer "venta_id", null: false
    t.index ["corte_id"], name: "index_devoluciones_on_corte_id"
    t.index ["sucursal_id", "folio"], name: "index_devoluciones_on_sucursal_y_folio", unique: true
    t.index ["sucursal_id"], name: "index_devoluciones_on_sucursal_id"
    t.index ["usuario_id"], name: "index_devoluciones_on_usuario_id"
    t.index ["venta_id"], name: "index_devoluciones_on_venta_id"
  end

  create_table "existencias", force: :cascade do |t|
    t.decimal "cantidad", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "producto_id", null: false
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.index ["producto_id"], name: "index_existencias_on_producto_id"
    t.index ["sucursal_id", "producto_id"], name: "index_existencias_on_sucursal_id_and_producto_id", unique: true
    t.index ["sucursal_id"], name: "index_existencias_on_sucursal_id"
    t.check_constraint "cantidad >= 0", name: "existencias_no_negativas"
  end

  create_table "factura_proveedor_lineas", force: :cascade do |t|
    t.integer "cajas", default: 0, null: false
    t.decimal "cantidad", precision: 12, scale: 3, null: false
    t.datetime "created_at", null: false
    t.integer "factura_proveedor_id", null: false
    t.integer "importe_centavos", null: false
    t.integer "precio_centavos", null: false
    t.integer "producto_id", null: false
    t.datetime "updated_at", null: false
    t.index ["factura_proveedor_id"], name: "index_factura_proveedor_lineas_on_factura_proveedor_id"
    t.index ["producto_id"], name: "index_factura_proveedor_lineas_on_producto_id"
  end

  create_table "facturas_proveedor", force: :cascade do |t|
    t.string "concepto"
    t.datetime "created_at", null: false
    t.string "estado", default: "abierta", null: false
    t.date "fecha", null: false
    t.string "folio", null: false
    t.integer "monto_centavos", default: 0, null: false
    t.string "motivo_cancelacion"
    t.integer "proveedor_id", null: false
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.date "vence"
    t.index ["proveedor_id", "folio"], name: "index_facturas_proveedor_on_proveedor_id_and_folio", unique: true
    t.index ["proveedor_id"], name: "index_facturas_proveedor_on_proveedor_id"
    t.index ["sucursal_id"], name: "index_facturas_proveedor_on_sucursal_id"
    t.index ["usuario_id"], name: "index_facturas_proveedor_on_usuario_id"
    t.check_constraint "estado IN ('abierta', 'cancelada')", name: "facturas_proveedor_estado"
  end

  create_table "folios", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "prefijo", null: false
    t.integer "sucursal_id", null: false
    t.integer "ultimo", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["sucursal_id", "prefijo"], name: "index_folios_on_sucursal_id_and_prefijo", unique: true
    t.index ["sucursal_id"], name: "index_folios_on_sucursal_id"
  end

  create_table "movimientos", force: :cascade do |t|
    t.decimal "cantidad", precision: 12, scale: 3, null: false
    t.datetime "created_at", null: false
    t.date "fecha_negocio", null: false
    t.string "motivo"
    t.integer "producto_id", null: false
    t.integer "referencia_id"
    t.string "referencia_type"
    t.decimal "saldo", precision: 12, scale: 3, null: false
    t.integer "sucursal_id", null: false
    t.string "tipo", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["producto_id"], name: "index_movimientos_on_producto_id"
    t.index ["referencia_type", "referencia_id"], name: "index_movimientos_on_referencia"
    t.index ["sucursal_id", "fecha_negocio"], name: "index_movimientos_on_sucursal_id_and_fecha_negocio"
    t.index ["sucursal_id", "producto_id", "created_at"], name: "idx_on_sucursal_id_producto_id_created_at_be784bb004"
    t.index ["sucursal_id"], name: "index_movimientos_on_sucursal_id"
    t.index ["usuario_id"], name: "index_movimientos_on_usuario_id"
    t.check_constraint "cantidad > 0", name: "movimientos_cantidad_positiva"
    t.check_constraint "tipo IN ('entrada', 'recepcion', 'devolucion_cliente', 'ajuste_entrada', 'venta', 'salida', 'merma', 'ajuste_salida')", name: "movimientos_tipo"
  end

  create_table "movimientos_proveedor", force: :cascade do |t|
    t.string "concepto"
    t.datetime "created_at", null: false
    t.integer "delta_centavos", null: false
    t.integer "factura_proveedor_id"
    t.date "fecha", null: false
    t.integer "monto_centavos", null: false
    t.integer "pago_proveedor_id"
    t.integer "proveedor_id", null: false
    t.integer "saldo_centavos", null: false
    t.integer "sucursal_id", null: false
    t.string "tipo", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["factura_proveedor_id"], name: "index_movimientos_proveedor_on_factura_proveedor_id"
    t.index ["pago_proveedor_id"], name: "index_movimientos_proveedor_on_pago_proveedor_id"
    t.index ["proveedor_id"], name: "index_movimientos_proveedor_on_proveedor_id"
    t.index ["sucursal_id"], name: "index_movimientos_proveedor_on_sucursal_id"
    t.index ["usuario_id"], name: "index_movimientos_proveedor_on_usuario_id"
    t.check_constraint "tipo IN ('cargo', 'abono', 'ajuste')", name: "movimientos_proveedor_tipo"
  end

  create_table "pagos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "forma", null: false
    t.integer "monto_centavos", null: false
    t.datetime "updated_at", null: false
    t.integer "venta_id", null: false
    t.index ["venta_id"], name: "index_pagos_on_venta_id"
    t.check_constraint "forma IN ('efectivo', 'transferencia', 'deposito')", name: "pagos_forma"
    t.check_constraint "monto_centavos > 0", name: "pagos_monto"
  end

  create_table "pagos_proveedor", force: :cascade do |t|
    t.integer "anulado_por_id"
    t.integer "corte_id"
    t.datetime "created_at", null: false
    t.string "estado", default: "vigente", null: false
    t.integer "factura_proveedor_id"
    t.string "forma", default: "efectivo", null: false
    t.integer "monto_centavos", null: false
    t.string "motivo_anulacion"
    t.integer "proveedor_id", null: false
    t.string "referencia"
    t.integer "retiro_id"
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["anulado_por_id"], name: "index_pagos_proveedor_on_anulado_por_id"
    t.index ["corte_id"], name: "index_pagos_proveedor_on_corte_id"
    t.index ["factura_proveedor_id"], name: "index_pagos_proveedor_on_factura_proveedor_id"
    t.index ["proveedor_id"], name: "index_pagos_proveedor_on_proveedor_id"
    t.index ["retiro_id"], name: "index_pagos_proveedor_on_retiro_id"
    t.index ["sucursal_id"], name: "index_pagos_proveedor_on_sucursal_id"
    t.index ["usuario_id"], name: "index_pagos_proveedor_on_usuario_id"
    t.check_constraint "estado IN ('vigente', 'anulado')", name: "pagos_proveedor_estado"
  end

  create_table "precios_sucursal", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "precio_centavos", null: false
    t.integer "producto_id", null: false
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.index ["producto_id", "sucursal_id"], name: "index_precios_sucursal_on_producto_id_and_sucursal_id", unique: true
    t.index ["producto_id"], name: "index_precios_sucursal_on_producto_id"
    t.index ["sucursal_id"], name: "index_precios_sucursal_on_sucursal_id"
    t.check_constraint "precio_centavos >= 0", name: "precios_sucursal_no_negativo"
  end

  create_table "productos", force: :cascade do |t|
    t.boolean "activo", default: true, null: false
    t.string "clave", null: false
    t.datetime "created_at", null: false
    t.string "linea"
    t.string "nombre", null: false
    t.integer "plu", null: false
    t.integer "precio_centavos", default: 0, null: false
    t.string "unidad", default: "kg", null: false
    t.datetime "updated_at", null: false
    t.index ["clave"], name: "index_productos_on_clave", unique: true
    t.index ["plu"], name: "index_productos_on_plu", unique: true
    t.check_constraint "plu BETWEEN 1 AND 99999", name: "productos_plu_rango"
    t.check_constraint "precio_centavos >= 0", name: "productos_precio_no_negativo"
    t.check_constraint "unidad IN ('kg', 'pieza', 'litro', 'metro')", name: "productos_unidad"
  end

  create_table "promociones", force: :cascade do |t|
    t.boolean "activa", default: true, null: false
    t.decimal "cantidad_minima", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.date "desde"
    t.date "hasta"
    t.string "nombre", null: false
    t.decimal "porcentaje", precision: 5, scale: 2
    t.integer "precio_centavos"
    t.integer "producto_id", null: false
    t.integer "sucursal_id"
    t.string "tipo", null: false
    t.datetime "updated_at", null: false
    t.index ["producto_id", "activa"], name: "index_promociones_on_producto_id_and_activa"
    t.index ["producto_id"], name: "index_promociones_on_producto_id"
    t.index ["sucursal_id"], name: "index_promociones_on_sucursal_id"
    t.check_constraint "tipo IN ('precio', 'porcentaje', 'por_cantidad')", name: "promociones_tipo"
  end

  create_table "proveedores", force: :cascade do |t|
    t.boolean "activo", default: true, null: false
    t.string "contacto"
    t.datetime "created_at", null: false
    t.integer "dias_credito", default: 0, null: false
    t.string "nombre", null: false
    t.string "notas"
    t.string "rfc"
    t.string "telefono"
    t.datetime "updated_at", null: false
    t.index ["nombre"], name: "index_proveedores_on_nombre", unique: true
  end

  create_table "recepcion_lineas", force: :cascade do |t|
    t.integer "cajas", default: 0, null: false
    t.decimal "cantidad", precision: 12, scale: 3, null: false
    t.datetime "created_at", null: false
    t.integer "producto_id", null: false
    t.integer "recepcion_id", null: false
    t.datetime "updated_at", null: false
    t.index ["producto_id"], name: "index_recepcion_lineas_on_producto_id"
    t.index ["recepcion_id"], name: "index_recepcion_lineas_on_recepcion_id"
  end

  create_table "recepciones", force: :cascade do |t|
    t.string "clave"
    t.datetime "created_at", null: false
    t.string "estado", default: "registrada", null: false
    t.integer "factura_proveedor_id"
    t.date "fecha", null: false
    t.string "folio", null: false
    t.string "motivo_cancelacion"
    t.string "notas"
    t.integer "proveedor_id", null: false
    t.string "remision"
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["factura_proveedor_id"], name: "index_recepciones_on_factura_proveedor_id"
    t.index ["proveedor_id"], name: "index_recepciones_on_proveedor_id"
    t.index ["sucursal_id", "clave"], name: "index_recepciones_on_sucursal_id_and_clave", unique: true, where: "clave IS NOT NULL"
    t.index ["sucursal_id", "folio"], name: "index_recepciones_on_sucursal_id_and_folio", unique: true
    t.index ["sucursal_id"], name: "index_recepciones_on_sucursal_id"
    t.index ["usuario_id"], name: "index_recepciones_on_usuario_id"
    t.check_constraint "estado IN ('registrada', 'cancelada')", name: "recepciones_estado"
  end

  create_table "reglas", force: :cascade do |t|
    t.text "codigo", null: false
    t.datetime "created_at", null: false
    t.string "gancho", null: false
    t.integer "usuario_id", null: false
    t.integer "version", default: 1, null: false
    t.index ["gancho", "id"], name: "index_reglas_on_gancho_and_id"
    t.index ["usuario_id"], name: "index_reglas_on_usuario_id"
  end

  create_table "retiros", force: :cascade do |t|
    t.integer "autorizado_por_id"
    t.integer "corte_id", null: false
    t.datetime "created_at", null: false
    t.integer "monto_centavos", null: false
    t.string "motivo", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["autorizado_por_id"], name: "index_retiros_on_autorizado_por_id"
    t.index ["corte_id"], name: "index_retiros_on_corte_id"
    t.index ["usuario_id"], name: "index_retiros_on_usuario_id"
    t.check_constraint "monto_centavos > 0", name: "retiros_monto"
  end

  create_table "revisiones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "estado", default: "pendiente", null: false
    t.boolean "frenado", default: false, null: false
    t.string "motivo", null: false
    t.string "nota"
    t.integer "revisable_id", null: false
    t.string "revisable_type", null: false
    t.datetime "revisado_en"
    t.integer "revisado_por_id"
    t.integer "sucursal_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.integer "valor_centavos", default: 0, null: false
    t.index ["revisable_type", "revisable_id"], name: "index_revisiones_on_revisable"
    t.index ["revisado_por_id"], name: "index_revisiones_on_revisado_por_id"
    t.index ["sucursal_id", "estado"], name: "index_revisiones_on_sucursal_id_and_estado"
    t.index ["sucursal_id"], name: "index_revisiones_on_sucursal_id"
    t.index ["usuario_id"], name: "index_revisiones_on_usuario_id"
    t.check_constraint "estado IN ('pendiente', 'aprobada', 'observada')", name: "revisiones_estado"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "nombre", null: false
    t.json "permisos", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["nombre"], name: "index_roles_on_nombre", unique: true
  end

  create_table "sucursales", force: :cascade do |t|
    t.boolean "activa", default: true, null: false
    t.string "codigo", null: false
    t.datetime "created_at", null: false
    t.integer "dias_conteo"
    t.integer "limite_efectivo_centavos", default: 300000, null: false
    t.string "nombre", null: false
    t.string "tipo", default: "tienda", null: false
    t.datetime "updated_at", null: false
    t.index ["codigo"], name: "index_sucursales_on_codigo", unique: true
    t.check_constraint "tipo IN ('matriz', 'tienda', 'almacen')", name: "sucursales_tipo"
  end

  create_table "traspaso_lineas", force: :cascade do |t|
    t.integer "cajas", default: 0, null: false
    t.decimal "cantidad", precision: 12, scale: 3, null: false
    t.datetime "created_at", null: false
    t.integer "producto_id", null: false
    t.integer "traspaso_id", null: false
    t.datetime "updated_at", null: false
    t.index ["producto_id"], name: "index_traspaso_lineas_on_producto_id"
    t.index ["traspaso_id"], name: "index_traspaso_lineas_on_traspaso_id"
  end

  create_table "traspasos", force: :cascade do |t|
    t.string "clave"
    t.datetime "created_at", null: false
    t.string "estado", default: "registrado", null: false
    t.date "fecha", null: false
    t.string "folio", null: false
    t.string "motivo_cancelacion"
    t.string "notas"
    t.integer "sucursal_destino_id", null: false
    t.integer "sucursal_origen_id", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["sucursal_destino_id"], name: "index_traspasos_on_sucursal_destino_id"
    t.index ["sucursal_origen_id", "clave"], name: "index_traspasos_on_sucursal_origen_id_and_clave", unique: true, where: "clave IS NOT NULL"
    t.index ["sucursal_origen_id", "folio"], name: "index_traspasos_on_sucursal_origen_id_and_folio", unique: true
    t.index ["sucursal_origen_id"], name: "index_traspasos_on_sucursal_origen_id"
    t.index ["usuario_id"], name: "index_traspasos_on_usuario_id"
    t.check_constraint "estado IN ('registrado', 'cancelado')", name: "traspasos_estado"
  end

  create_table "usuarios", force: :cascade do |t|
    t.boolean "activo", default: true, null: false
    t.datetime "created_at", null: false
    t.string "densidad", default: "normal", null: false
    t.string "idioma", default: "en", null: false
    t.string "letra", default: "normal", null: false
    t.string "nombre", null: false
    t.string "password_digest", null: false
    t.integer "rol_id", null: false
    t.integer "sucursal_id", null: false
    t.string "tema", default: "claro", null: false
    t.datetime "updated_at", null: false
    t.string "usuario", null: false
    t.index ["rol_id"], name: "index_usuarios_on_rol_id"
    t.index ["sucursal_id"], name: "index_usuarios_on_sucursal_id"
    t.index ["usuario"], name: "index_usuarios_on_usuario", unique: true
  end

  create_table "venta_lineas", force: :cascade do |t|
    t.integer "autorizado_por_id"
    t.decimal "cantidad", precision: 12, scale: 3, null: false
    t.integer "catalogo_centavos", null: false
    t.datetime "created_at", null: false
    t.integer "importe_centavos", null: false
    t.integer "precio_centavos", null: false
    t.integer "producto_id", null: false
    t.integer "promocion_id"
    t.datetime "updated_at", null: false
    t.integer "venta_id", null: false
    t.index ["autorizado_por_id"], name: "index_venta_lineas_on_autorizado_por_id"
    t.index ["producto_id"], name: "index_venta_lineas_on_producto_id"
    t.index ["promocion_id"], name: "index_venta_lineas_on_promocion_id"
    t.index ["venta_id"], name: "index_venta_lineas_on_venta_id"
    t.check_constraint "cantidad > 0", name: "venta_lineas_cantidad"
    t.check_constraint "precio_centavos >= 0 AND importe_centavos >= 0", name: "venta_lineas_dinero"
  end

  create_table "ventas", force: :cascade do |t|
    t.integer "cambio_centavos", default: 0, null: false
    t.string "clave", null: false
    t.string "codigo", limit: 13, null: false
    t.integer "corte_id", null: false
    t.datetime "created_at", null: false
    t.string "estado", default: "cobrada", null: false
    t.date "fecha_negocio", null: false
    t.string "folio", null: false
    t.integer "sucursal_id", null: false
    t.integer "total_centavos", null: false
    t.datetime "updated_at", null: false
    t.integer "usuario_id", null: false
    t.index ["clave"], name: "index_ventas_on_clave", unique: true
    t.index ["codigo"], name: "index_ventas_on_codigo", unique: true
    t.index ["corte_id", "estado"], name: "index_ventas_on_corte_id_and_estado"
    t.index ["corte_id"], name: "index_ventas_on_corte_id"
    t.index ["sucursal_id", "folio"], name: "index_ventas_on_sucursal_y_folio", unique: true
    t.index ["sucursal_id"], name: "index_ventas_on_sucursal_id"
    t.index ["usuario_id"], name: "index_ventas_on_usuario_id"
    t.check_constraint "estado IN ('cobrada', 'devuelta')", name: "ventas_estado"
    t.check_constraint "total_centavos >= 0", name: "ventas_total"
  end

  add_foreign_key "cargos", "conteos"
  add_foreign_key "cargos", "revisiones"
  add_foreign_key "cargos", "sucursales"
  add_foreign_key "cargos", "usuarios"
  add_foreign_key "cargos", "usuarios", column: "resuelto_por_id"
  add_foreign_key "codigos_barras", "productos"
  add_foreign_key "conteo_lineas", "conteos"
  add_foreign_key "conteo_lineas", "productos"
  add_foreign_key "conteos", "sucursales"
  add_foreign_key "conteos", "usuarios"
  add_foreign_key "conteos", "usuarios", column: "responsable_id"
  add_foreign_key "cortes", "sucursales"
  add_foreign_key "cortes", "usuarios"
  add_foreign_key "cortes", "usuarios", column: "cerrado_por_id"
  add_foreign_key "devolucion_lineas", "devoluciones"
  add_foreign_key "devolucion_lineas", "venta_lineas"
  add_foreign_key "devoluciones", "cortes"
  add_foreign_key "devoluciones", "sucursales"
  add_foreign_key "devoluciones", "usuarios"
  add_foreign_key "devoluciones", "ventas"
  add_foreign_key "existencias", "productos"
  add_foreign_key "existencias", "sucursales"
  add_foreign_key "factura_proveedor_lineas", "facturas_proveedor", column: "factura_proveedor_id"
  add_foreign_key "factura_proveedor_lineas", "productos"
  add_foreign_key "facturas_proveedor", "proveedores"
  add_foreign_key "facturas_proveedor", "sucursales"
  add_foreign_key "facturas_proveedor", "usuarios"
  add_foreign_key "folios", "sucursales"
  add_foreign_key "movimientos", "productos"
  add_foreign_key "movimientos", "sucursales"
  add_foreign_key "movimientos", "usuarios"
  add_foreign_key "movimientos_proveedor", "facturas_proveedor", column: "factura_proveedor_id"
  add_foreign_key "movimientos_proveedor", "pagos_proveedor", column: "pago_proveedor_id"
  add_foreign_key "movimientos_proveedor", "proveedores"
  add_foreign_key "movimientos_proveedor", "sucursales"
  add_foreign_key "movimientos_proveedor", "usuarios"
  add_foreign_key "pagos", "ventas"
  add_foreign_key "pagos_proveedor", "cortes"
  add_foreign_key "pagos_proveedor", "facturas_proveedor", column: "factura_proveedor_id"
  add_foreign_key "pagos_proveedor", "proveedores"
  add_foreign_key "pagos_proveedor", "retiros"
  add_foreign_key "pagos_proveedor", "sucursales"
  add_foreign_key "pagos_proveedor", "usuarios"
  add_foreign_key "pagos_proveedor", "usuarios", column: "anulado_por_id"
  add_foreign_key "precios_sucursal", "productos"
  add_foreign_key "precios_sucursal", "sucursales"
  add_foreign_key "promociones", "productos"
  add_foreign_key "promociones", "sucursales"
  add_foreign_key "recepcion_lineas", "productos"
  add_foreign_key "recepcion_lineas", "recepciones"
  add_foreign_key "recepciones", "facturas_proveedor", column: "factura_proveedor_id"
  add_foreign_key "recepciones", "proveedores"
  add_foreign_key "recepciones", "sucursales"
  add_foreign_key "recepciones", "usuarios"
  add_foreign_key "reglas", "usuarios"
  add_foreign_key "retiros", "cortes"
  add_foreign_key "retiros", "usuarios"
  add_foreign_key "retiros", "usuarios", column: "autorizado_por_id"
  add_foreign_key "revisiones", "sucursales"
  add_foreign_key "revisiones", "usuarios"
  add_foreign_key "revisiones", "usuarios", column: "revisado_por_id"
  add_foreign_key "traspaso_lineas", "productos"
  add_foreign_key "traspaso_lineas", "traspasos"
  add_foreign_key "traspasos", "sucursales", column: "sucursal_destino_id"
  add_foreign_key "traspasos", "sucursales", column: "sucursal_origen_id"
  add_foreign_key "traspasos", "usuarios"
  add_foreign_key "usuarios", "roles"
  add_foreign_key "usuarios", "sucursales"
  add_foreign_key "venta_lineas", "productos"
  add_foreign_key "venta_lineas", "promociones"
  add_foreign_key "venta_lineas", "usuarios", column: "autorizado_por_id"
  add_foreign_key "venta_lineas", "ventas"
  add_foreign_key "ventas", "cortes"
  add_foreign_key "ventas", "sucursales"
  add_foreign_key "ventas", "usuarios"
end
