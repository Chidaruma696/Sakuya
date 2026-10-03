class Pago < ApplicationRecord
  # Las formas en que entra dinero. Vender a cuenta no mete dinero: se carga a la cuenta del cliente.
  FORMAS = %w[efectivo transferencia deposito].freeze
  A_CUENTA = "credito".freeze

  belongs_to :venta

  validates :forma, inclusion: { in: FORMAS + [ A_CUENTA ] }
  validates :monto_centavos, numericality: { only_integer: true, greater_than: 0 }
end
