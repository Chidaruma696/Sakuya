module RevisionesHelper
  # A dónde lleva la operación revisada.
  def enlace_de_revision(revision)
    r = revision.revisable
    case r
    when Movimiento then kardex_inventario_path(producto_id: r.producto_id, sucursal_id: r.sucursal_id)
    when Retiro then caja_corte_path
    when VentaLinea then caja_ticket_path(r.venta)
    when Venta then caja_ticket_path(r)
    when Recepcion then recepcion_path(r)
    when Producto then kardex_inventario_path(producto_id: r.id, sucursal_id: revision.sucursal_id)
    when Proveedor then facturas_path(proveedor_id: r.id)
    else revisiones_path
    end
  end
end
