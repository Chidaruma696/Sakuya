# Recepción de mercancía del proveedor: es una entrada al inventario con proveedor y remisión. No
# hay orden de compra; la factura se liga cuando llega.
class Recepcion < ApplicationRecord
  self.table_name = "recepciones"

  belongs_to :sucursal
  belongs_to :proveedor
  belongs_to :factura, class_name: "FacturaProveedor", foreign_key: :factura_proveedor_id, optional: true
  belongs_to :usuario
  has_many :lineas, class_name: "RecepcionLinea", dependent: :destroy, inverse_of: :recepcion
  has_many :movimientos, as: :referencia

  before_validation :asignar_folio, on: :create
  validates :folio, presence: true, uniqueness: { scope: :sucursal_id }
  validates :fecha, presence: true
  validates :estado, inclusion: { in: %w[registrada cancelada] }

  scope :registradas, -> { where(estado: "registrada") }

  def registrada? = estado == "registrada"
  def cancelada? = estado == "cancelada"

  # { producto => cantidad } de lo recibido.
  def por_producto = lineas.includes(:producto).group_by(&:producto).transform_values { |ls| ls.sum(&:cantidad) }

  def to_s = folio

  private

  def asignar_folio
    self.folio ||= Folio.siguiente!(sucursal, "recepcion") if sucursal
  end
end
