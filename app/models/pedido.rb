# Un pedido de un cliente: lo que quiere y para cuándo. No aparta existencias ni lleva precio: se
# cobra en la caja como cualquier venta (con sus reglas) y entonces queda entregado, ligado a ella.
class Pedido < ApplicationRecord
  ESTADOS = %w[abierto entregado cancelado].freeze

  belongs_to :cliente
  belongs_to :sucursal
  belongs_to :usuario
  belongs_to :venta, optional: true
  has_many :lineas, class_name: "PedidoLinea", dependent: :destroy, inverse_of: :pedido
  accepts_nested_attributes_for :lineas, reject_if: ->(a) { a[:producto_id].blank? || a[:cantidad].blank? }

  before_validation :asignar_folio, on: :create

  validates :folio, presence: true, uniqueness: { scope: :sucursal_id }
  validates :estado, inclusion: { in: ESTADOS }
  validate(on: :create) { errors.add(:base, I18n.t("errores.pedido.sin_renglones")) if lineas.empty? }

  scope :abiertos, -> { where(estado: "abierto") }

  def abierto? = estado == "abierto"

  def entregar!(venta)
    raise ArgumentError, I18n.t("errores.pedido.no_abierto", folio: folio) unless abierto?
    update!(estado: "entregado", venta: venta)
  end

  def cancelar!(motivo:)
    raise ArgumentError, I18n.t("errores.pedido.no_abierto", folio: folio) unless abierto?
    raise ArgumentError, I18n.t("errores.hace_falta_motivo") if motivo.blank?
    update!(estado: "cancelado", motivo_cancelacion: motivo)
  end

  def to_s = folio

  private

  def asignar_folio
    self.folio ||= Folio.siguiente!(sucursal, "pedido") if sucursal
  end
end
