# Dinero que se le cobra a alguien: el faltante de un conteo o una operación observada en revisión.
class Cargo < ApplicationRecord
  belongs_to :usuario
  belongs_to :sucursal
  belongs_to :conteo, optional: true
  belongs_to :revision, optional: true
  belongs_to :resuelto_por, class_name: "Usuario", optional: true

  validates :monto_centavos, numericality: { only_integer: true, greater_than: 0 }
  validates :estado, inclusion: { in: %w[pendiente cobrado perdonado] }
  validate { errors.add(:base, I18n.t("errores.cargo.sin_origen")) if conteo.nil? && revision.nil? }

  scope :pendientes, -> { where(estado: "pendiente") }

  def resolver!(estado, usuario:)
    raise ArgumentError, I18n.t("errores.cargo.ya_esta", estado: I18n.t("estados.#{self.estado}")) unless self.estado == "pendiente"
    update!(estado: estado, resuelto_por: usuario, resuelto_en: Time.current)
  end
end
