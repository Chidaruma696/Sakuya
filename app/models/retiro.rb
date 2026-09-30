class Retiro < ApplicationRecord
  belongs_to :corte
  belongs_to :usuario
  belongs_to :autorizado_por, class_name: "Usuario", optional: true

  validates :monto_centavos, numericality: { only_integer: true, greater_than: 0 }
  validates :motivo, presence: true
end
