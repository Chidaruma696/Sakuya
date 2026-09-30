class Devolucion < ApplicationRecord
  belongs_to :venta
  belongs_to :sucursal
  belongs_to :corte, optional: true
  belongs_to :usuario
  has_many :lineas, class_name: "DevolucionLinea", dependent: :restrict_with_error, inverse_of: :devolucion

  before_validation :asignar_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :sucursal_id }
  validates :motivo, presence: true
  validates :total_centavos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def to_s
    folio
  end

  private

  def asignar_folio
    self.sucursal ||= corte&.sucursal || venta&.sucursal
    self.folio ||= Folio.siguiente!(sucursal, "devolucion") if sucursal
  end
end
