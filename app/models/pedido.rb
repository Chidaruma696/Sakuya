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
  validate :alcanza_para_apartar, on: :create, if: :apartar

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

  # Lo que se aparta tiene que estar disponible (hay menos lo apartado por otros pedidos).
  def alcanza_para_apartar
    return unless sucursal
    apartado = Apartado.por_producto(sucursal)
    lineas.group_by(&:producto).each do |producto, ls|
      next unless producto
      pide = ls.sum { |l| l.cantidad.to_d }
      disponible = Existencia.de(sucursal, producto) - apartado.fetch(producto.id, 0)
      next if pide <= disponible
      c = ->(v) { ApplicationController.helpers.cantidad(v, producto) }
      errors.add(:base, I18n.t("errores.pedido.no_alcanza", producto: producto.nombre, pide: c.(pide), disponible: c.([ disponible, 0 ].max)))
    end
  end

  def asignar_folio
    self.folio ||= Folio.siguiente!(sucursal, "pedido") if sucursal
  end
end
