# El libro de la deuda con el proveedor, solo-inserción: cargo (factura), abono (pago) y ajuste
# (cancelaciones, con signo). El saldo es la suma de los deltas.
class MovimientoProveedor < ApplicationRecord
  self.table_name = "movimientos_proveedor"

  belongs_to :proveedor
  belongs_to :sucursal
  belongs_to :usuario
  belongs_to :factura, class_name: "FacturaProveedor", foreign_key: :factura_proveedor_id, optional: true
  belongs_to :pago, class_name: "PagoProveedor", foreign_key: :pago_proveedor_id, optional: true

  validates :tipo, inclusion: { in: %w[cargo abono ajuste] }
  validates :monto_centavos, numericality: { only_integer: true, greater_than: 0 }

  before_update { raise ActiveRecord::ReadOnlyRecord, "el libro del proveedor no se edita" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "el libro del proveedor no se borra" }
end
