# La única puerta para cambiar existencias: escribe el movimiento y actualiza la proyección
# en la misma transacción. Rails abre las transacciones de SQLite en modo IMMEDIATE, así que
# dos cajas no pueden leer el mismo saldo a la vez; en PostgreSQL lo garantiza el lock de fila.
module Inventario
  class SinExistencia < StandardError; end

  def self.mover!(sucursal:, producto:, tipo:, cantidad:, usuario:, referencia: nil, motivo: nil, fecha: Date.current)
    cantidad = BigDecimal(cantidad.to_s).round(3)
    raise ArgumentError, I18n.t("errores.inventario.cantidad_cero") unless cantidad.positive?
    delta = Movimiento.signo(tipo) * cantidad

    Movimiento.transaction do
      existencia = Existencia.lock.find_or_create_by!(sucursal: sucursal, producto: producto)
      nuevo = existencia.cantidad + delta
      if nuevo.negative?
        raise SinExistencia, I18n.t("errores.inventario.insuficiente", producto: producto.nombre, sucursal: sucursal.nombre, hay: existencia.cantidad.to_s("F"), piden: cantidad.to_s("F"))
      end
      existencia.update!(cantidad: nuevo)
      Movimiento.create!(sucursal: sucursal, producto: producto, tipo: tipo, cantidad: cantidad, saldo: nuevo,
                         referencia: referencia, usuario: usuario, motivo: motivo, fecha_negocio: fecha)
    end
  end
end
