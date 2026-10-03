class PedidoLinea < ApplicationRecord
  belongs_to :pedido
  belongs_to :producto

  validates :cantidad, numericality: { greater_than: 0 }
  validate { errors.add(:cantidad, I18n.t("errores.caja.piezas_enteras", producto: producto.nombre)) if producto && !producto.fraccionable? && cantidad.to_d != cantidad.to_d.floor }
end
