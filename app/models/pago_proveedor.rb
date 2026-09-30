# Pago a un proveedor. Un solo camino: si es efectivo sale de la gaveta abierta como retiro, y en
# la misma transacción abona al libro. Anularlo compensa el abono y regresa el efectivo.
class PagoProveedor < ApplicationRecord
  self.table_name = "pagos_proveedor"

  belongs_to :proveedor
  belongs_to :factura, class_name: "FacturaProveedor", foreign_key: :factura_proveedor_id, optional: true
  belongs_to :sucursal
  belongs_to :corte, optional: true
  belongs_to :retiro, optional: true
  belongs_to :usuario
  belongs_to :anulado_por, class_name: "Usuario", optional: true

  validates :monto_centavos, numericality: { only_integer: true, greater_than: 0 }
  validates :forma, inclusion: { in: Pago::FORMAS }
  validates :estado, inclusion: { in: %w[vigente anulado] }

  scope :vigentes, -> { where(estado: "vigente") }

  def vigente? = estado == "vigente"
end
