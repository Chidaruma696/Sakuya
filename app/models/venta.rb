class Venta < ApplicationRecord
  belongs_to :cliente, optional: true
  belongs_to :sucursal
  belongs_to :corte
  belongs_to :usuario
  has_many :lineas, class_name: "VentaLinea", dependent: :restrict_with_error, inverse_of: :venta
  has_many :pagos, dependent: :restrict_with_error
  has_many :devoluciones, dependent: :restrict_with_error

  validates :folio, presence: true, uniqueness: { scope: :sucursal_id }
  validates :codigo, :clave, presence: true, uniqueness: true
  validates :estado, inclusion: { in: %w[cobrada devuelta] }
  validates :total_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recientes, -> { order(created_at: :desc) }

  def cobrada? = estado == "cobrada"

  # Lo que sí se pagó: pagos menos cambio.
  def pagado_centavos
    pagos.sum(:monto_centavos) - cambio_centavos
  end

  # Lo que queda de la venta: el total menos lo devuelto.
  def saldo_centavos
    total_centavos - total_devuelto_centavos
  end

  # El ticket lleva su propio EAN-13 (prefijo 09 + sucursal + secuencia) para devoluciones.
  def self.buscar(texto)
    find_by(codigo: Barcode.variantes(texto)) || find_by(folio: texto.to_s.strip.upcase)
  end

  def total_devuelto_centavos
    devoluciones.sum(:total_centavos)
  end

  def to_s
    folio
  end

  # De lo que fue a cuenta del cliente, lo que todavía no se le ha descontado por devoluciones.
  def a_cuenta_pendiente_centavos
    pagos.where(forma: Pago::A_CUENTA).sum(:monto_centavos) - devoluciones.sum(:a_cuenta_centavos)
  end
end
