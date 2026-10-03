# Lo apartado por los pedidos abiertos de clientes y lo que queda disponible. Vender y traspasar
# respetan lo apartado; mermas y ajustes no, porque registran algo que ya pasó.
module Apartado
  class Error < ArgumentError; end

  # { producto_id => cantidad apartada } en una sucursal, sin contar un pedido (el que se cobra).
  def self.por_producto(sucursal, excepto: nil)
    return {} unless Modulo.activo?("clientes")
    lineas = PedidoLinea.joins(:pedido).where(pedidos: { sucursal_id: sucursal.id, estado: "abierto", apartar: true })
    lineas = lineas.where.not(pedido_id: excepto.id) if excepto
    lineas.group(:producto_id).sum(:cantidad)
  end

  def self.de(sucursal, producto, excepto: nil) = por_producto(sucursal, excepto: excepto).fetch(producto.id, BigDecimal("0"))

  def self.disponible(sucursal, producto, excepto: nil) = Existencia.de(sucursal, producto) - de(sucursal, producto, excepto: excepto)

  # Que lo que sale ([[producto, cantidad]]) no se coma lo apartado. Si no alcanza por otra cosa
  # (no hay existencias), lo dice el kardex al mover.
  def self.comprobar!(sucursal, salidas, excepto: nil)
    apartado = por_producto(sucursal, excepto: excepto)
    return if apartado.empty?
    salidas.group_by(&:first).each do |producto, filas|
      cantidad = filas.sum(&:last)
      hay = Existencia.de(sucursal, producto)
      reservado = apartado.fetch(producto.id, 0)
      next if reservado.zero? || cantidad <= hay - reservado || cantidad > hay
      c = ->(v) { ApplicationController.helpers.cantidad(v, producto) }
      raise Error, I18n.t("errores.apartado.no_alcanza", producto: producto.nombre, hay: c.(hay), apartado: c.(reservado), disponible: c.(hay - reservado))
    end
  end
end
