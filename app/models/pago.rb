class Pago < ApplicationRecord
  FORMAS = %w[efectivo transferencia deposito].freeze

  belongs_to :venta

  validates :forma, inclusion: { in: FORMAS }
  validates :monto_centavos, numericality: { only_integer: true, greater_than: 0 }
end
